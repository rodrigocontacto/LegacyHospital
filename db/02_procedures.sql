/*
    02_procedures.sql
    Functions and stored procedures.

      dbo.*  internal: password hashing and user creation. hospital_web
             can NOT execute these (no permission on schema dbo).
      app.*  called by the web app. Every procedure that returns patient
             data filters by @UserId (the logged-in doctor): no IDOR.

    Return codes used by app procedures:
      0 = success, 1 = not found / not allowed / invalid login,
      2 = invalid input. Tampered sort parameters raise error 50001.

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

/* Salted SHA2_512, iterated 10,000 times.
   Known limitation: weaker than bcrypt/Argon2, which SQL Server and
   VBScript do not provide. */
CREATE OR ALTER FUNCTION dbo.ufn_Password_Hash
(
    @Password NVARCHAR(128),
    @Salt     VARBINARY(32)
)
RETURNS VARBINARY(64)
AS
BEGIN
    DECLARE @PasswordBytes VARBINARY(256) = CAST(@Password AS VARBINARY(256));
    DECLARE @Hash VARBINARY(64) = HASHBYTES('SHA2_512', @Salt + @PasswordBytes);
    DECLARE @Iteration INT = 1;

    WHILE @Iteration < 10000
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

    INSERT dbo.Users (Username, FullName, PasswordHash, PasswordSalt)
    VALUES (@Username, @FullName, dbo.ufn_Password_Hash(@Password, @Salt), @Salt);

    SET @UserId = SCOPE_IDENTITY();
END
GO

/* ===============================================================
   Web app (app)
   =============================================================== */

/* Returns 0 and the user data on success, 1 on any failure.
   Unknown user, wrong password, locked and inactive all return the same
   code (no user enumeration). The hash is always computed so the response
   time does not reveal whether the user exists.
   5 failed attempts lock the account for 5 minutes. The counter lives
   in the database: it survives new sessions, app restarts and is shared
   by every worker process. */
CREATE OR ALTER PROCEDURE app.usp_User_Login
    @Username NVARCHAR(50),
    @Password NVARCHAR(128),
    @UserId   INT OUTPUT,
    @FullName NVARCHAR(100) OUTPUT,
    @Role     NVARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @MaxFailedAttempts INT = 5;
    DECLARE @LockoutMinutes    INT = 5;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    DECLARE @StoredUserId   INT,
            @StoredFullName NVARCHAR(100),
            @StoredRole     NVARCHAR(20),
            @StoredHash     VARBINARY(64),
            @Salt           VARBINARY(32),
            @IsActive       BIT,
            @LockoutUntil   DATETIME2(0),
            @ComputedHash   VARBINARY(64);

    SET @UserId = NULL;
    SET @FullName = NULL;
    SET @Role = NULL;

    SELECT @StoredUserId   = UserId,
           @StoredFullName = FullName,
           @StoredRole     = Role,
           @StoredHash     = PasswordHash,
           @Salt           = PasswordSalt,
           @IsActive       = IsActive,
           @LockoutUntil   = LockoutUntil
    FROM dbo.Users
    WHERE Username = @Username;

    /* Same work whether or not the user exists. */
    SET @ComputedHash = dbo.ufn_Password_Hash(ISNULL(@Password, N''),
                                              ISNULL(@Salt, CRYPT_GEN_RANDOM(32)));

    IF @StoredUserId IS NULL
        RETURN 1;

    IF @IsActive = 0 OR (@LockoutUntil IS NOT NULL AND @LockoutUntil > @Now)
        RETURN 1;

    IF @ComputedHash <> @StoredHash
    BEGIN
        /* Atomic update. An expired lockout restarts the count at 1. */
        UPDATE dbo.Users
        SET FailedLoginCount =
                CASE WHEN LockoutUntil IS NOT NULL AND LockoutUntil <= @Now
                     THEN 1 ELSE FailedLoginCount + 1 END,
            LockoutUntil =
                CASE WHEN LockoutUntil IS NOT NULL AND LockoutUntil > @Now
                         THEN LockoutUntil
                     WHEN (CASE WHEN LockoutUntil IS NOT NULL AND LockoutUntil <= @Now
                                THEN 1 ELSE FailedLoginCount + 1 END) >= @MaxFailedAttempts
                         THEN DATEADD(MINUTE, @LockoutMinutes, @Now)
                     ELSE NULL END
        WHERE UserId = @StoredUserId;

        RETURN 1;
    END

    UPDATE dbo.Users
    SET FailedLoginCount = 0,
        LockoutUntil = NULL
    WHERE UserId = @StoredUserId;

    SET @UserId = @StoredUserId;
    SET @FullName = @StoredFullName;
    SET @Role = @StoredRole;
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

/* Technical error detail. Never fails because of long or empty input. */
CREATE OR ALTER PROCEDURE app.usp_Error_Log
    @PageName    NVARCHAR(200),
    @ErrorDetail NVARCHAR(4000),
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT dbo.AppErrorLog (PageName, ErrorDetail, UserId)
    VALUES (LEFT(ISNULL(NULLIF(@PageName, N''), N'(unknown)'), 200),
            LEFT(ISNULL(NULLIF(@ErrorDetail, N''), N'(no detail)'), 4000),
            @UserId);

    RETURN 0;
END
GO

PRINT N'02_procedures.sql completed.';
GO
