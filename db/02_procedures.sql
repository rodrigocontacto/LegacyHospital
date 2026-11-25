/*
    02_procedures.sql
    Functions and stored procedures.

      dbo.*  internal: password hashing and user creation. hospital_web
             can NOT execute these (no permission on schema dbo).
      app.*  called by the web app. Every procedure that returns patient
             data filters by @UserId (the logged-in doctor): no IDOR.

    Return codes used by app procedures:
      0 = success, 1 = not found / not allowed / invalid login,
      2 = invalid input, 3 = rate limited (login only).
    Tampered sort parameters raise error 50001.

    Run after 01_schema.sql:
        sqlcmd -S .\SQLEXPRESS -E -b -i db\02_procedures.sql

    Safe to re-run (CREATE OR ALTER).
*/
:on error exit
SET NOCOUNT ON;
GO

USE LegacyHospital;
GO

/* ---------------------------------------------------------------
   Execution principal for procedures with dynamic SQL.
   sp_executesql breaks ownership chaining, so those procedures run
   WITH EXECUTE AS this user, which can only SELECT two tables.
   It has no login: nobody can connect as it.
   --------------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID(N'app_dynamic_reader') IS NULL
    CREATE USER app_dynamic_reader WITHOUT LOGIN;
GO
GRANT SELECT ON dbo.Patients TO app_dynamic_reader;
GRANT SELECT ON dbo.Appointments TO app_dynamic_reader;
GO

/* F-15 cleanup for databases created by older versions of this script:
   the notes report is no longer used, and without it app_dynamic_reader
   does not need PatientNotes. */
IF OBJECT_ID(N'app.usp_NoteReport_Get', N'P') IS NOT NULL
    DROP PROCEDURE app.usp_NoteReport_Get;
REVOKE SELECT ON dbo.PatientNotes FROM app_dynamic_reader;
GO

/* ===============================================================
   Internal (dbo)
   =============================================================== */

/* Password hashing (F-05).
   Salted SHA2_512, iterated. The iteration count is versioned
   (Users.HashVersion) so it can grow: a user whose hash is older than
   the current version is rehashed on the next successful login.

     Version 1: 10,000 iterations  (~45 ms; original, too fast)
     Version 2: 60,000 iterations  (target: >= 100 ms per hash, measured)

   Known limitation: still weaker against GPUs than bcrypt/Argon2, which
   SQL Server and VBScript do not provide. To raise the cost again, add
   version 3 here and in CK_Users_HashVersion, and make it current. */
CREATE OR ALTER FUNCTION dbo.ufn_Password_CurrentVersion()
RETURNS TINYINT
AS
BEGIN
    RETURN 2;
END
GO

CREATE OR ALTER FUNCTION dbo.ufn_Password_Iterations(@HashVersion TINYINT)
RETURNS INT
AS
BEGIN
    RETURN CASE @HashVersion
               WHEN 1 THEN 10000
               WHEN 2 THEN 60000
           END;
END
GO

CREATE OR ALTER FUNCTION dbo.ufn_Password_Hash
(
    @Password   NVARCHAR(128),
    @Salt       VARBINARY(32),
    @Iterations INT
)
RETURNS VARBINARY(64)
AS
BEGIN
    DECLARE @PasswordBytes VARBINARY(256) = CAST(@Password AS VARBINARY(256));
    DECLARE @Hash VARBINARY(64) = HASHBYTES('SHA2_512', @Salt + @PasswordBytes);
    DECLARE @Iteration INT = 1;

    /* An unknown version gives NULL iterations: return NULL, which never
       equals a stored hash, instead of a weak hash. */
    IF @Iterations IS NULL OR @Iterations < 10000
        RETURN NULL;

    WHILE @Iteration < @Iterations
    BEGIN
        SET @Hash = HASHBYTES('SHA2_512', @Hash + @Salt + @PasswordBytes);
        SET @Iteration += 1;
    END

    RETURN @Hash;
END
GO

/* Admin/seed only. Not callable by the web app. */
CREATE OR ALTER PROCEDURE dbo.usp_User_Create
    @Username NVARCHAR(50),
    @FullName NVARCHAR(100),
    @Password NVARCHAR(128),
    @UserId   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Password IS NULL OR LEN(@Password) < 12
        THROW 50002, N'Password must have at least 12 characters.', 1;

    DECLARE @Salt VARBINARY(32) = CRYPT_GEN_RANDOM(32);
    DECLARE @HashVersion TINYINT = dbo.ufn_Password_CurrentVersion();

    INSERT dbo.Users (Username, FullName, PasswordHash, PasswordSalt, HashVersion)
    VALUES (@Username, @FullName,
            dbo.ufn_Password_Hash(@Password, @Salt, dbo.ufn_Password_Iterations(@HashVersion)),
            @Salt, @HashVersion);

    SET @UserId = SCOPE_IDENTITY();
END
GO

/* Writes one SecurityAudit row (F-06). Called only by app procedures
   (ownership chaining); hospital_web cannot execute dbo.* directly.
   Never fails because of long input.

   Flood cap (F-14): when one IP already has 100 non-success events in
   the last minute, further non-success events from it are dropped (the
   first 100 are enough to see the attack). Success events are always
   written: the access trail of signed-in users must be complete.
   Retention: rows older than 6 years are purged, 100 per call. */
CREATE OR ALTER PROCEDURE dbo.usp_SecurityAudit_Write
    @EventType  VARCHAR(20),
    @Outcome    VARCHAR(10),
    @UserId     INT,
    @Username   NVARCHAR(50),
    @IpAddress  VARCHAR(45),
    @ResourceId INT,
    @Detail     VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    SET @IpAddress = LEFT(ISNULL(NULLIF(@IpAddress, ''), 'unknown'), 45);

    IF @Outcome <> 'Success'
       AND (SELECT COUNT(*)
            FROM dbo.SecurityAudit
            WHERE IpAddress = @IpAddress
              AND CreatedAt >= DATEADD(SECOND, -60, @Now)
              AND Outcome <> 'Success') >= 100
        RETURN 0;

    INSERT dbo.SecurityAudit (CreatedAt, EventType, Outcome, UserId, Username, IpAddress, ResourceId, Detail)
    VALUES (@Now, @EventType, @Outcome, @UserId, LEFT(@Username, 50), @IpAddress, @ResourceId, LEFT(@Detail, 50));

    DELETE TOP (100) FROM dbo.SecurityAudit
    WHERE CreatedAt < DATEADD(DAY, -2190, @Now);

    RETURN 0;
END
GO

/* ===============================================================
   Web app (app)
   =============================================================== */

/* Sign-in. Return codes:
     0  success: @UserId, @FullName and @Role are filled
     1  any credential failure: unknown user, wrong password, inactive,
        locked. All look the same (no user enumeration)
     3  too many failures from this IP: the caller answers 429

   Three limits, all counted in the database (they survive new sessions
   and app restarts and are shared by every worker process):
     - Per IP (F-04, password spraying): 30 failures in 60 seconds
       (failed logins, blocked logins and CSRF failures) -> code 3,
       without checking the password.
     - Per IP + username (F-13): 5 failed passwords in 15 minutes since
       the last success from that IP lock that pair only. Somebody who
       knows a doctor's username can no longer lock the doctor out from
       another machine.
     - Per account, any IP: 50 consecutive failures lock the account for
       15 minutes. Safety net against guessing spread over many IPs;
       locking a doctor out now needs at least 10 IPs.

   The hash is computed for unknown users too, so the response time does
   not reveal whether the user exists. An old-version hash (HashVersion)
   is checked with its own iteration count and, on success, replaced by
   a current-version hash with a new salt (F-05); the new hash is always
   computed for those users so success and failure take the same time.

   Every attempt is written to dbo.SecurityAudit (F-06), with the reason
   in Detail. Only the database sees the reason; the user never does. */
CREATE OR ALTER PROCEDURE app.usp_User_Login
    @Username  NVARCHAR(50),
    @Password  NVARCHAR(128),
    @IpAddress VARCHAR(45),
    @UserId    INT OUTPUT,
    @FullName  NVARCHAR(100) OUTPUT,
    @Role      NVARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @IpMaxFailures        INT = 30,
            @IpWindowSeconds      INT = 60,
            @PairMaxFailures      INT = 5,
            @PairWindowMinutes    INT = 15,
            @AccountMaxFailures   INT = 50,
            @AccountLockMinutes   INT = 15;

    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @CurrentVersion TINYINT = dbo.ufn_Password_CurrentVersion();

    DECLARE @StoredUserId   INT,
            @StoredFullName NVARCHAR(100),
            @StoredRole     NVARCHAR(20),
            @StoredHash     VARBINARY(64),
            @Salt           VARBINARY(32),
            @HashVersion    TINYINT,
            @IsActive       BIT,
            @LockoutUntil   DATETIME2(0),
            @ComputedHash   VARBINARY(64),
            @NewSalt        VARBINARY(32),
            @NewHash        VARBINARY(64),
            @IpFailures     INT,
            @PairFailures   INT,
            @LastSuccess    DATETIME2(3),
            @LockResult     INT,
            @LockName       NVARCHAR(255),
            @Outcome        VARCHAR(10),
            @Detail         VARCHAR(50);

    SET @UserId = NULL;
    SET @FullName = NULL;
    SET @Role = NULL;
    SET @IpAddress = LEFT(ISNULL(NULLIF(@IpAddress, ''), 'unknown'), 45);
    SET @Username = LEFT(@Username, 50);

    BEGIN TRANSACTION;

    /* One sign-in at a time per IP, until COMMIT. Without it, many
       parallel requests would all read the failure count before any of
       them writes its failure, and pass the limit together. */
    SET @LockName = N'app.usp_User_Login:' + CONVERT(NVARCHAR(45), @IpAddress);
    EXEC @LockResult = sys.sp_getapplock
        @Resource = @LockName, @LockMode = 'Exclusive',
        @LockOwner = 'Transaction', @LockTimeout = 15000;
    IF @LockResult < 0
    BEGIN
        ROLLBACK TRANSACTION;
        RETURN 3;
    END

    /* ---- Per-IP limit (no password check, no hash) ---- */
    SELECT @IpFailures = COUNT(*)
    FROM dbo.SecurityAudit
    WHERE IpAddress = @IpAddress
      AND CreatedAt >= DATEADD(SECOND, -@IpWindowSeconds, @Now)
      AND (   (EventType = 'Login' AND Outcome IN ('Failure', 'Blocked'))
           OR (EventType = 'CsrfCheck' AND Outcome = 'Failure'));

    IF @IpFailures >= @IpMaxFailures
    BEGIN
        EXEC dbo.usp_SecurityAudit_Write 'Login', 'Blocked', NULL, @Username, @IpAddress, NULL, 'IpRateLimit';
        COMMIT TRANSACTION;
        RETURN 3;
    END

    /* ---- Credentials ---- */
    SELECT @StoredUserId   = UserId,
           @StoredFullName = FullName,
           @StoredRole     = Role,
           @StoredHash     = PasswordHash,
           @Salt           = PasswordSalt,
           @HashVersion    = HashVersion,
           @IsActive       = IsActive,
           @LockoutUntil   = LockoutUntil
    FROM dbo.Users
    WHERE Username = @Username;

    /* Same work whether or not the user exists. */
    SET @ComputedHash = dbo.ufn_Password_Hash(
        ISNULL(@Password, N''),
        ISNULL(@Salt, CRYPT_GEN_RANDOM(32)),
        dbo.ufn_Password_Iterations(ISNULL(@HashVersion, @CurrentVersion)));

    IF @StoredUserId IS NOT NULL AND @HashVersion < @CurrentVersion
    BEGIN
        SET @NewSalt = CRYPT_GEN_RANDOM(32);
        SET @NewHash = dbo.ufn_Password_Hash(ISNULL(@Password, N''), @NewSalt,
                                             dbo.ufn_Password_Iterations(@CurrentVersion));
    END

    /* ---- Per IP + username lock ---- */
    SELECT @LastSuccess = MAX(CreatedAt)
    FROM dbo.SecurityAudit
    WHERE IpAddress = @IpAddress
      AND Username = @Username
      AND EventType = 'Login'
      AND Outcome = 'Success'
      AND CreatedAt >= DATEADD(MINUTE, -@PairWindowMinutes, @Now);

    SELECT @PairFailures = COUNT(*)
    FROM dbo.SecurityAudit
    WHERE IpAddress = @IpAddress
      AND Username = @Username
      AND EventType = 'Login'
      AND Outcome = 'Failure'
      AND CreatedAt >= DATEADD(MINUTE, -@PairWindowMinutes, @Now)
      AND (@LastSuccess IS NULL OR CreatedAt > @LastSuccess);

    IF @PairFailures >= @PairMaxFailures
        SET @Detail = 'IpUserLockout';
    ELSE IF @StoredUserId IS NULL
        SET @Detail = 'UnknownUser';
    ELSE IF @IsActive = 0
        SET @Detail = 'Inactive';
    ELSE IF @LockoutUntil IS NOT NULL AND @LockoutUntil > @Now
        SET @Detail = 'AccountLockout';
    ELSE IF @ComputedHash IS NULL OR @ComputedHash <> @StoredHash
        SET @Detail = 'BadPassword';

    IF @Detail IS NOT NULL
    BEGIN
        IF @Detail = 'BadPassword'
        BEGIN
            /* Atomic update. An expired lockout restarts the count at 1. */
            UPDATE dbo.Users
            SET FailedLoginCount =
                    CASE WHEN LockoutUntil IS NOT NULL AND LockoutUntil <= @Now
                         THEN 1 ELSE FailedLoginCount + 1 END,
                LockoutUntil =
                    CASE WHEN (CASE WHEN LockoutUntil IS NOT NULL AND LockoutUntil <= @Now
                                    THEN 1 ELSE FailedLoginCount + 1 END) >= @AccountMaxFailures
                             THEN DATEADD(MINUTE, @AccountLockMinutes, @Now)
                         ELSE NULL END
            WHERE UserId = @StoredUserId;

            IF EXISTS (SELECT 1 FROM dbo.Users
                       WHERE UserId = @StoredUserId AND LockoutUntil > @Now)
                SET @Detail = 'BadPasswordLockoutStarted';
        END

        SET @Outcome = CASE WHEN @Detail IN ('BadPassword', 'BadPasswordLockoutStarted', 'UnknownUser')
                            THEN 'Failure' ELSE 'Blocked' END;
        EXEC dbo.usp_SecurityAudit_Write
            'Login', @Outcome, @StoredUserId, @Username, @IpAddress, NULL, @Detail;

        COMMIT TRANSACTION;
        RETURN 1;
    END

    /* ---- Success ---- */
    UPDATE dbo.Users
    SET FailedLoginCount = 0,
        LockoutUntil = NULL,
        PasswordHash = CASE WHEN @NewHash IS NOT NULL THEN @NewHash ELSE PasswordHash END,
        PasswordSalt = CASE WHEN @NewHash IS NOT NULL THEN @NewSalt ELSE PasswordSalt END,
        HashVersion  = CASE WHEN @NewHash IS NOT NULL THEN @CurrentVersion ELSE HashVersion END
    WHERE UserId = @StoredUserId;

    SET @Detail = CASE WHEN @NewHash IS NOT NULL THEN 'PasswordRehashed' END;
    EXEC dbo.usp_SecurityAudit_Write
        'Login', 'Success', @StoredUserId, @Username, @IpAddress, NULL, @Detail;

    COMMIT TRANSACTION;

    SET @UserId = @StoredUserId;
    SET @FullName = @StoredFullName;
    SET @Role = @StoredRole;
    RETURN 0;
END
GO

/* For signed-in sessions (F-12): is the user still allowed in?
   A deactivated user (IsActive = 0) or a missing one gives 0. */
CREATE OR ALTER PROCEDURE app.usp_User_IsActive
    @UserId   INT,
    @IsActive BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @IsActive = 0;
    SELECT @IsActive = IsActive
    FROM dbo.Users
    WHERE UserId = @UserId;

    RETURN 0;
END
GO

/* Security events written by the web app (F-06): CSRF failures, record
   views and denied access, notes added, sign-outs and ended sessions.
   Sign-in attempts are written by app.usp_User_Login itself.
   Returns 2 for an unknown event type or outcome. */
CREATE OR ALTER PROCEDURE app.usp_SecurityAudit_Add
    @UserId     INT,
    @IpAddress  VARCHAR(45),
    @EventType  VARCHAR(20),
    @Outcome    VARCHAR(10),
    @ResourceId INT,
    @Detail     VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF @EventType NOT IN ('Logout', 'CsrfCheck', 'PatientView', 'NoteAdd', 'Session')
       OR @Outcome NOT IN ('Success', 'Failure', 'Denied', 'Blocked')
        RETURN 2;

    EXEC dbo.usp_SecurityAudit_Write
        @EventType, @Outcome, @UserId, NULL, @IpAddress, @ResourceId, @Detail;

    RETURN 0;
END
GO

/* 32 cryptographically random bytes as 64 hex characters. */
CREATE OR ALTER PROCEDURE app.usp_Token_Generate
    @Token CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Token = CONVERT(CHAR(64), CRYPT_GEN_RANDOM(32), 2);
    RETURN 0;
END
GO

/* Search the logged-in doctor's patients by prefix of last name,
   first name or medical record number. Empty term = all (max 100).
   Wildcards in the term are escaped. ORDER BY comes from a whitelist
   and goes through QUOTENAME; values go through sp_executesql. */
CREATE OR ALTER PROCEDURE app.usp_Patient_Search
    @UserId        INT,
    @SearchTerm    NVARCHAR(50),
    @SortColumn    VARCHAR(30) = 'LastName',
    @SortDirection VARCHAR(4)  = 'ASC'
WITH EXECUTE AS N'app_dynamic_reader'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderColumn SYSNAME,
            @Direction   NVARCHAR(4),
            @Pattern     NVARCHAR(110),
            @Sql         NVARCHAR(MAX);

    SET @OrderColumn = CASE @SortColumn
                           WHEN 'LastName'            THEN N'LastName'
                           WHEN 'FirstName'           THEN N'FirstName'
                           WHEN 'DateOfBirth'         THEN N'DateOfBirth'
                           WHEN 'MedicalRecordNumber' THEN N'MedicalRecordNumber'
                       END;
    SET @Direction = CASE UPPER(@SortDirection)
                         WHEN 'ASC'  THEN N'ASC'
                         WHEN 'DESC' THEN N'DESC'
                     END;

    IF @OrderColumn IS NULL OR @Direction IS NULL
        THROW 50001, N'Invalid sort column or direction.', 1;

    /* Escape \ first, then the LIKE wildcards. */
    SET @Pattern = LTRIM(RTRIM(ISNULL(@SearchTerm, N'')));
    SET @Pattern = REPLACE(@Pattern, N'\', N'\\');
    SET @Pattern = REPLACE(@Pattern, N'%', N'\%');
    SET @Pattern = REPLACE(@Pattern, N'_', N'\_');
    SET @Pattern = REPLACE(@Pattern, N'[', N'\[');
    SET @Pattern = @Pattern + N'%';

    SET @Sql = N'
SELECT TOP (100) PatientId, MedicalRecordNumber, FirstName, LastName, DateOfBirth
FROM dbo.Patients
WHERE AssignedUserId = @UserId
  AND (LastName LIKE @Pattern ESCAPE N''\''
       OR FirstName LIKE @Pattern ESCAPE N''\''
       OR MedicalRecordNumber LIKE @Pattern ESCAPE N''\'')
ORDER BY ' + QUOTENAME(@OrderColumn) + N' ' + @Direction + N', PatientId;';

    EXEC sys.sp_executesql
        @Sql,
        N'@UserId INT, @Pattern NVARCHAR(110)',
        @UserId = @UserId,
        @Pattern = @Pattern;

    RETURN 0;
END
GO

/* One patient, only if assigned to the logged-in doctor.
   "Does not exist" and "not yours" look the same (empty result). */
CREATE OR ALTER PROCEDURE app.usp_Patient_Get
    @UserId    INT,
    @PatientId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT PatientId, MedicalRecordNumber, FirstName, LastName, DateOfBirth
    FROM dbo.Patients
    WHERE PatientId = @PatientId
      AND AssignedUserId = @UserId;

    RETURN 0;
END
GO

/* Notes of one patient, only if assigned to the logged-in doctor. */
CREATE OR ALTER PROCEDURE app.usp_PatientNote_List
    @UserId    INT,
    @PatientId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT n.NoteId, n.NoteText, n.CreatedAt, u.FullName AS AuthorName
    FROM dbo.PatientNotes AS n
    JOIN dbo.Patients AS p ON p.PatientId = n.PatientId
    JOIN dbo.Users AS u ON u.UserId = n.AuthorUserId
    WHERE n.PatientId = @PatientId
      AND p.AssignedUserId = @UserId
    ORDER BY n.CreatedAt DESC, n.NoteId DESC;

    RETURN 0;
END
GO

/* Returns 0 (added), 1 (patient not found / not yours),
   2 (empty or longer than 2000 characters).
   @NoteText is wider than the column so long input is rejected,
   not silently truncated. */
CREATE OR ALTER PROCEDURE app.usp_PatientNote_Add
    @UserId    INT,
    @PatientId INT,
    @NoteText  NVARCHAR(4000),
    @NoteId    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @NoteId = NULL;
    SET @NoteText = LTRIM(RTRIM(@NoteText));

    IF @NoteText IS NULL OR LEN(@NoteText) = 0 OR LEN(@NoteText) > 2000
        RETURN 2;

    /* Ownership check and insert in one statement. */
    INSERT dbo.PatientNotes (PatientId, AuthorUserId, NoteText)
    SELECT PatientId, @UserId, @NoteText
    FROM dbo.Patients
    WHERE PatientId = @PatientId
      AND AssignedUserId = @UserId;

    IF @@ROWCOUNT = 0
        RETURN 1;

    SET @NoteId = SCOPE_IDENTITY();
    RETURN 0;
END
GO

/* Appointments of the logged-in doctor's patients between two dates
   (both inclusive, ToDate - FromDate <= 90 days). Returns 2 for an
   invalid range. Max 500 rows.

   ORDER BY cannot be a parameter, so the column name is built into the
   SQL text in two steps:
     1. Whitelist: the request value is only COMPARED with fixed
        literals; what goes into the SQL is the literal, never the input.
     2. QUOTENAME: the chosen name is written as a delimited identifier
        ([LastName]); a "]" inside would be doubled, so it can never
        close the identifier and add SQL.
   Every value (user, dates) is a real parameter of sp_executesql. */
CREATE OR ALTER PROCEDURE app.usp_Appointment_Report
    @UserId        INT,
    @FromDate      DATE,
    @ToDate        DATE,
    @SortColumn    VARCHAR(30) = 'ScheduledAt',
    @SortDirection VARCHAR(4)  = 'ASC'
WITH EXECUTE AS N'app_dynamic_reader'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderColumn SYSNAME,
            @Direction   NVARCHAR(4),
            @TieBreak    NVARCHAR(100),
            @Sql         NVARCHAR(MAX);

    IF @FromDate IS NULL OR @ToDate IS NULL OR @FromDate > @ToDate
       OR DATEDIFF(DAY, @FromDate, @ToDate) > 90
        RETURN 2;

    SET @OrderColumn = CASE @SortColumn
                           WHEN 'ScheduledAt' THEN N'ScheduledAt'
                           WHEN 'LastName'    THEN N'LastName'
                           WHEN 'Status'      THEN N'Status'
                       END;
    SET @Direction = CASE UPPER(@SortDirection)
                         WHEN 'ASC'  THEN N'ASC'
                         WHEN 'DESC' THEN N'DESC'
                     END;

    IF @OrderColumn IS NULL OR @Direction IS NULL
        THROW 50001, N'Invalid sort column or direction.', 1;

    /* SQL Server rejects a column repeated in ORDER BY, so ScheduledAt
       is only a tie-breaker when it is not already the sort column.
       Fixed literals only: nothing from the input. */
    SET @TieBreak = CASE WHEN @OrderColumn = N'ScheduledAt'
                         THEN N'a.AppointmentId'
                         ELSE N'a.ScheduledAt, a.AppointmentId' END;

    SET @Sql = N'
SELECT TOP (500) a.AppointmentId, a.ScheduledAt, a.Status, a.Reason,
       p.PatientId, p.MedicalRecordNumber, p.LastName, p.FirstName
FROM dbo.Appointments AS a
JOIN dbo.Patients AS p ON p.PatientId = a.PatientId
WHERE p.AssignedUserId = @UserId
  AND a.ScheduledAt >= @FromDate
  AND a.ScheduledAt < DATEADD(DAY, 1, @ToDate)
ORDER BY ' + QUOTENAME(@OrderColumn) + N' ' + @Direction + N', ' + @TieBreak + N';';

    EXEC sys.sp_executesql
        @Sql,
        N'@UserId INT, @FromDate DATE, @ToDate DATE',
        @UserId = @UserId,
        @FromDate = @FromDate,
        @ToDate = @ToDate;

    RETURN 0;
END
GO

/* Technical error detail. Never fails because of long or empty input.
   F-14: at most 100 rows per minute (a flood of errors adds nothing
   after the first ones) and rows older than 90 days are purged, 100 per
   call. CSRF failures are not errors: they go to dbo.SecurityAudit. */
CREATE OR ALTER PROCEDURE app.usp_Error_Log
    @PageName    NVARCHAR(200),
    @ErrorDetail NVARCHAR(4000),
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    IF (SELECT COUNT(*) FROM dbo.AppErrorLog
        WHERE CreatedAt >= DATEADD(SECOND, -60, @Now)) >= 100
        RETURN 0;

    INSERT dbo.AppErrorLog (PageName, ErrorDetail, UserId)
    VALUES (LEFT(ISNULL(NULLIF(@PageName, N''), N'(unknown)'), 200),
            LEFT(ISNULL(NULLIF(@ErrorDetail, N''), N'(no detail)'), 4000),
            @UserId);

    DELETE TOP (100) FROM dbo.AppErrorLog
    WHERE CreatedAt < DATEADD(DAY, -90, @Now);

    RETURN 0;
END
GO

PRINT N'02_procedures.sql completed.';
GO
