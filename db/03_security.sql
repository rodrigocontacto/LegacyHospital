/*
    03_security.sql
    Creates the hospital_web login/user.
    hospital_web only gets EXECUTE on schema app (the app stored
    procedures). It has no direct access to any table.

    Requirements:
      - Run 01_schema.sql and 02_procedures.sql first.
      - SQL Server must allow "SQL Server and Windows Authentication mode".
      - The password is passed as a sqlcmd variable, never stored in the repo.
        It must NOT contain a single quote (').

    Run with (PowerShell: single quotes outside, double quotes inside,
    otherwise a password containing "=" is cut):
        sqlcmd -S .\SQLEXPRESS -E -b -i db\03_security.sql -v 'WebPassword="<strong password>"'

    Safe to re-run. Re-running does NOT change an existing login's password.
*/
:on error exit
SET NOCOUNT ON;
GO

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'hospital_web')
    CREATE LOGIN hospital_web
        WITH PASSWORD = N'$(WebPassword)',
             DEFAULT_DATABASE = LegacyHospital,
             CHECK_POLICY = ON,
             CHECK_EXPIRATION = OFF;
GO

USE LegacyHospital;
GO

IF DATABASE_PRINCIPAL_ID(N'hospital_web') IS NULL
    CREATE USER hospital_web FOR LOGIN hospital_web WITH DEFAULT_SCHEMA = app;
GO

/* The only permission the web app has. */
GRANT EXECUTE ON SCHEMA::app TO hospital_web;
GO

PRINT N'03_security.sql completed.';
GO
