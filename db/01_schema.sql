/*
    01_schema.sql
    Creates the LegacyHospital database and its tables.

    Run with sqlcmd (or SSMS in SQLCMD mode):
        sqlcmd -S .\SQLEXPRESS -E -b -i db\01_schema.sql

    Safe to re-run: every object is created only if it does not exist.
*/
:on error exit
SET NOCOUNT ON;
GO

IF DB_ID(N'LegacyHospital') IS NULL
    CREATE DATABASE LegacyHospital;
GO

USE LegacyHospital;
GO

/* Schema for every stored procedure the web app may call.
   hospital_web gets EXECUTE on this schema only (03_security.sql). */
IF SCHEMA_ID(N'app') IS NULL
    EXEC (N'CREATE SCHEMA app AUTHORIZATION dbo;');
GO

/* ---------------------------------------------------------------
   Users: doctors who log in to the portal.
   Passwords are stored as salted, iterated SHA2_512 hashes
   (computed by a stored procedure in 02_procedures.sql).
   --------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users
    (
        UserId           INT IDENTITY(1,1) NOT NULL
                         CONSTRAINT PK_Users PRIMARY KEY,
        Username         NVARCHAR(50)  NOT NULL
                         CONSTRAINT UQ_Users_Username UNIQUE,
        FullName         NVARCHAR(100) NOT NULL,
        Role             NVARCHAR(20)  NOT NULL
                         CONSTRAINT DF_Users_Role DEFAULT (N'Doctor'),
        PasswordHash     VARBINARY(64) NOT NULL,
        PasswordSalt     VARBINARY(32) NOT NULL,
        FailedLoginCount INT           NOT NULL
                         CONSTRAINT DF_Users_FailedLoginCount DEFAULT (0),
        LockoutUntil     DATETIME2(0)  NULL,
        IsActive         BIT           NOT NULL
                         CONSTRAINT DF_Users_IsActive DEFAULT (1),
        CreatedAt        DATETIME2(0)  NOT NULL
                         CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT CK_Users_Username
            CHECK (LEN(Username) >= 3 AND Username NOT LIKE N'%[^a-zA-Z0-9._-]%'),
        CONSTRAINT CK_Users_FullName
            CHECK (LEN(FullName) > 0),
        CONSTRAINT CK_Users_Role
            CHECK (Role IN (N'Doctor')),
        CONSTRAINT CK_Users_PasswordHash
            CHECK (DATALENGTH(PasswordHash) = 64),
        CONSTRAINT CK_Users_PasswordSalt
            CHECK (DATALENGTH(PasswordSalt) = 32),
        CONSTRAINT CK_Users_FailedLoginCount
            CHECK (FailedLoginCount >= 0)
    );
END
GO

/* ---------------------------------------------------------------
   Patients: each patient is assigned to exactly one doctor.
   Access checks (no IDOR) are based on AssignedUserId.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Patients', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Patients
    (
        PatientId           INT IDENTITY(1,1) NOT NULL
                            CONSTRAINT PK_Patients PRIMARY KEY,
        MedicalRecordNumber VARCHAR(20)   NOT NULL
                            CONSTRAINT UQ_Patients_MedicalRecordNumber UNIQUE,
        FirstName           NVARCHAR(50)  NOT NULL,
        LastName            NVARCHAR(50)  NOT NULL,
        DateOfBirth         DATE          NOT NULL,
        AssignedUserId      INT           NOT NULL
                            CONSTRAINT FK_Patients_AssignedUser
                            REFERENCES dbo.Users (UserId),
        CreatedAt           DATETIME2(0)  NOT NULL
                            CONSTRAINT DF_Patients_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT CK_Patients_FirstName
            CHECK (LEN(FirstName) > 0),
        CONSTRAINT CK_Patients_LastName
            CHECK (LEN(LastName) > 0),
        CONSTRAINT CK_Patients_MedicalRecordNumber
            CHECK (LEN(MedicalRecordNumber) > 0 AND MedicalRecordNumber NOT LIKE '%[^A-Z0-9-]%'),
        CONSTRAINT CK_Patients_DateOfBirth
            CHECK (DateOfBirth >= '19000101' AND DateOfBirth <= CAST(SYSUTCDATETIME() AS DATE))
    );
END
GO

/* Search is always "my patients by last name", so one index covers it. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_Patients_AssignedUserId_LastName'
                 AND object_id = OBJECT_ID(N'dbo.Patients'))
    CREATE INDEX IX_Patients_AssignedUserId_LastName
        ON dbo.Patients (AssignedUserId, LastName, FirstName);
GO

/* ---------------------------------------------------------------
   PatientNotes: clinical notes. Stored as plain text, encoded
   on output with Server.HTMLEncode (never stored pre-encoded).
   --------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.PatientNotes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PatientNotes
    (
        NoteId       INT IDENTITY(1,1) NOT NULL
                     CONSTRAINT PK_PatientNotes PRIMARY KEY,
        PatientId    INT            NOT NULL
                     CONSTRAINT FK_PatientNotes_Patient
                     REFERENCES dbo.Patients (PatientId),
        AuthorUserId INT            NOT NULL
                     CONSTRAINT FK_PatientNotes_AuthorUser
                     REFERENCES dbo.Users (UserId),
        NoteText     NVARCHAR(2000) NOT NULL,
        CreatedAt    DATETIME2(0)   NOT NULL
                     CONSTRAINT DF_PatientNotes_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT CK_PatientNotes_NoteText
            CHECK (LEN(NoteText) > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_PatientNotes_PatientId_CreatedAt'
                 AND object_id = OBJECT_ID(N'dbo.PatientNotes'))
    CREATE INDEX IX_PatientNotes_PatientId_CreatedAt
        ON dbo.PatientNotes (PatientId, CreatedAt DESC);
GO

/* ---------------------------------------------------------------
   Appointments: scheduled visits. ScheduledAt is clinic local time.
   Access is checked through the patient's AssignedUserId (same rule
   as patient records).
   --------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Appointments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Appointments
    (
        AppointmentId INT IDENTITY(1,1) NOT NULL
                      CONSTRAINT PK_Appointments PRIMARY KEY,
        PatientId     INT           NOT NULL
                      CONSTRAINT FK_Appointments_Patient
                      REFERENCES dbo.Patients (PatientId),
        ScheduledAt   DATETIME2(0)  NOT NULL,
        Status        VARCHAR(20)   NOT NULL
                      CONSTRAINT DF_Appointments_Status DEFAULT ('Scheduled'),
        Reason        NVARCHAR(200) NOT NULL,
        CreatedAt     DATETIME2(0)  NOT NULL
                      CONSTRAINT DF_Appointments_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT CK_Appointments_Status
            CHECK (Status IN ('Scheduled', 'Completed', 'Cancelled')),
        CONSTRAINT CK_Appointments_Reason
            CHECK (LEN(Reason) > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_Appointments_PatientId_ScheduledAt'
                 AND object_id = OBJECT_ID(N'dbo.Appointments'))
    CREATE INDEX IX_Appointments_PatientId_ScheduledAt
        ON dbo.Appointments (PatientId, ScheduledAt)
        INCLUDE (Status);
GO

/* ---------------------------------------------------------------
   AppErrorLog: technical error details. Users only ever see a
   generic message; the detail goes here.
   UserId has no foreign key on purpose: logging must never fail.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.AppErrorLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AppErrorLog
    (
        ErrorId     INT IDENTITY(1,1) NOT NULL
                    CONSTRAINT PK_AppErrorLog PRIMARY KEY,
        CreatedAt   DATETIME2(0)   NOT NULL
                    CONSTRAINT DF_AppErrorLog_CreatedAt DEFAULT (SYSUTCDATETIME()),
        PageName    NVARCHAR(200)  NOT NULL,
        ErrorDetail NVARCHAR(4000) NOT NULL,
        UserId      INT            NULL
    );
END
GO

PRINT N'01_schema.sql completed.';
GO
