/*
    04_seed.sql
    Fake demo data: 3 doctors, 12 patients, clinical notes, appointments.
    ALL DATA IS FICTIONAL.

    Includes two records for security tests:
      - patient "O'Brien": quotes must not break anything.
      - a note with <script>alert(1)</script>: must be shown encoded.

    The doctors' password is a sqlcmd variable (never stored in the repo).
    At least 12 characters, no single quote (').

    PowerShell (single quotes outside, double quotes inside):
        sqlcmd -S .\SQLEXPRESS -E -b -i db\04_seed.sql -v 'SeedPassword="<password>"'

    Safe to re-run: users are created only if missing; patients and
    notes only if Patients is empty; appointments only if Appointments
    is empty.
*/
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE LegacyHospital;
GO

DECLARE @Ignored INT;

IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Username = N'dr.garcia')
    EXEC dbo.usp_User_Create N'dr.garcia', N'Ana Garcia', N'$(SeedPassword)', @Ignored OUTPUT;
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Username = N'dr.smith')
    EXEC dbo.usp_User_Create N'dr.smith', N'John Smith', N'$(SeedPassword)', @Ignored OUTPUT;
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Username = N'dr.chen')
    EXEC dbo.usp_User_Create N'dr.chen', N'Mei Chen', N'$(SeedPassword)', @Ignored OUTPUT;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Patients)
BEGIN
    BEGIN TRANSACTION;

    DECLARE @Garcia INT = (SELECT UserId FROM dbo.Users WHERE Username = N'dr.garcia');
    DECLARE @Smith  INT = (SELECT UserId FROM dbo.Users WHERE Username = N'dr.smith');
    DECLARE @Chen   INT = (SELECT UserId FROM dbo.Users WHERE Username = N'dr.chen');

    INSERT dbo.Patients (MedicalRecordNumber, FirstName, LastName, DateOfBirth, AssignedUserId)
    VALUES ('MRN-0001', N'Laura',   N'Martinez', '19780312', @Garcia),
           ('MRN-0002', N'Peter',   N'O''Brien', '19650704', @Garcia),
           ('MRN-0003', N'Sofia',   N'Rossi',    '19900121', @Garcia),
           ('MRN-0004', N'Daniel',  N'Moreno',   '20010930', @Garcia),
           ('MRN-0005', N'Emma',    N'Johnson',  '19851115', @Smith),
           ('MRN-0006', N'Lucas',   N'Brown',    '19720208', @Smith),
           ('MRN-0007', N'Olivia',  N'Taylor',   '19950617', @Smith),
           ('MRN-0008', N'Noah',    N'Wilson',   '19580423', @Smith),
           ('MRN-0009', N'Hana',    N'Kim',      '19880805', @Chen),
           ('MRN-0010', N'Ravi',    N'Patel',    '19670126', @Chen),
           ('MRN-0011', N'Chloe',   N'Dubois',   '19990311', @Chen),
           ('MRN-0012', N'Martin',  N'Martinez', '19810719', @Chen);

    /* Dates relative to today so the report always has data. */
    INSERT dbo.PatientNotes (PatientId, AuthorUserId, NoteText, CreatedAt)
    SELECT p.PatientId, p.AssignedUserId, v.NoteText,
           DATEADD(DAY, -v.DaysAgo, SYSUTCDATETIME())
    FROM (VALUES
            ('MRN-0001', N'Routine check-up. Blood pressure 120/80.', 40),
            ('MRN-0001', N'Follow-up: lab results within normal range.', 5),
            ('MRN-0002', N'Patient reports mild knee pain after running.', 20),
            ('MRN-0002', N'<script>alert(1)</script> Test note: must be displayed as text, never executed.', 2),
            ('MRN-0003', N'Seasonal allergy. Prescribed antihistamine.', 12),
            ('MRN-0005', N'Annual physical. No issues found.', 30),
            ('MRN-0006', N'Cholesterol slightly high. Diet advice given.', 8),
            ('MRN-0008', N'Follow-up on blood pressure medication.', 3),
            ('MRN-0009', N'Vaccination record updated.', 15),
            ('MRN-0010', N'Patient reports better sleep after treatment change.', 6),
            ('MRN-0012', N'Sprained ankle. Rest and ice for one week.', 1)
         ) AS v (MedicalRecordNumber, NoteText, DaysAgo)
    JOIN dbo.Patients AS p ON p.MedicalRecordNumber = v.MedicalRecordNumber;

    COMMIT TRANSACTION;
END
GO

/* Appointments relative to today: past ones Completed/Cancelled,
   future ones Scheduled. Inserted only if the table is empty. */
IF NOT EXISTS (SELECT 1 FROM dbo.Appointments)
BEGIN
    DECLARE @Today DATETIME2(0) = CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME2(0));

    INSERT dbo.Appointments (PatientId, ScheduledAt, Status, Reason)
    SELECT p.PatientId,
           DATEADD(MINUTE, v.MinuteOfDay, DATEADD(DAY, v.DayOffset, @Today)),
           v.Status, v.Reason
    FROM (VALUES
            ('MRN-0001', -20, 540, 'Completed', N'Routine check-up'),
            ('MRN-0001',  10, 600, 'Scheduled', N'Lab results review'),
            ('MRN-0002',  -5, 630, 'Completed', N'Knee pain follow-up'),
            ('MRN-0002',   3, 900, 'Scheduled', N'<b>Physiotherapy</b> referral (test: tags must show as text)'),
            ('MRN-0003',  -2, 570, 'Cancelled', N'Allergy follow-up'),
            ('MRN-0003',  14, 660, 'Scheduled', N'Allergy test'),
            ('MRN-0004',   7, 720, 'Scheduled', N'Sports medical certificate'),
            ('MRN-0005', -10, 540, 'Completed', N'Annual physical'),
            ('MRN-0006',   5, 600, 'Scheduled', N'Cholesterol check'),
            ('MRN-0008',   1, 480, 'Scheduled', N'Blood pressure control'),
            ('MRN-0009', -30, 840, 'Completed', N'Vaccination'),
            ('MRN-0010',  20, 870, 'Scheduled', N'Sleep follow-up'),
            ('MRN-0012',   2, 510, 'Cancelled', N'Ankle check')
         ) AS v (MedicalRecordNumber, DayOffset, MinuteOfDay, Status, Reason)
    JOIN dbo.Patients AS p ON p.MedicalRecordNumber = v.MedicalRecordNumber;
END
GO

PRINT N'04_seed.sql completed.';
GO
