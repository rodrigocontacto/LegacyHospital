/*
    03_security.sql
    Creates the hospital_web login/user.
    hospital_web only gets EXECUTE on schema app (the app stored
    procedures). It has no direct access to any table.

    Requirements:
      - Run 01_schema.sql and 02_procedures.sql first.
      - SQL Server must allow "SQL Server and Windows Authentication mode".
      - The password is passed as a sqlcmd variable, never stored in the repo.

    F-16: sqlcmd pastes variables into the script as text, so a password
    written inside a literal ('...$(var)...') could close the literal and
    run SQL. The password is therefore passed as HEX (its UTF-16LE bytes):
    hex has no quotes, any password works, and a value that is not hex
    stops the script before anything runs. The login is created with
    dynamic SQL where the password goes through QUOTENAME.

    PowerShell:
        $hex = -join ([Text.Encoding]::Unicode.GetBytes('<strong password>') | ForEach-Object { $_.ToString('X2') })
        sqlcmd -S .\SQLEXPRESS -E -b -i db\03_security.sql -v "WebPasswordHex=$hex"

    Safe to re-run. Re-running does NOT change an existing login's password.
*/
:on error exit
SET NOCOUNT ON;
GO

USE master;
GO

/* VARCHAR(MAX): a fixed size would silently cut a long value before
   the length check. */
DECLARE @PasswordHex VARCHAR(MAX) = '$(WebPasswordHex)';
DECLARE @Password NVARCHAR(128), @Sql NVARCHAR(MAX);

IF LEN(@PasswordHex) = 0 OR LEN(@PasswordHex) > 512 OR LEN(@PasswordHex) % 4 <> 0
   OR @PasswordHex LIKE '%[^0-9A-Fa-f]%'
    THROW 50010, N'WebPasswordHex must be the password as UTF-16LE bytes in hex (see the header of this script).', 1;

SET @Password = CAST(CONVERT(VARBINARY(256), @PasswordHex, 2) AS NVARCHAR(128));

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'hospital_web')
BEGIN
    SET @Sql = N'CREATE LOGIN hospital_web WITH PASSWORD = ' + QUOTENAME(@Password, N'''') +
               N', DEFAULT_DATABASE = LegacyHospital, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;';
    IF @Sql IS NULL
        THROW 50010, N'Invalid password.', 1;
    EXEC sys.sp_executesql @Sql;
END
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
