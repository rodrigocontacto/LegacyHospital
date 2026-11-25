<#
.SYNOPSIS
    Starts LegacyHospital locally: LocalDB + IIS Express on web/.

.DESCRIPTION
    1. Checks prerequisites (IIS Express, LocalDB, sqlcmd, OLE DB Driver 19).
    2. Starts LocalDB.
    3. With -RebuildDatabase (or when the database does not exist): generates
       two random passwords, recreates the database from db/01..04, writes
       config/hospital.udl (UTF-16) and prints the passwords ONCE.
    4. Checks that the .udl connects with ADO (the same driver ASP uses).
    5. Starts IIS Express on web/ in its own window (keeps running after this
       script ends), unless the site already answers on the port.

    Development only: -RebuildDatabase DROPS the LocalDB database.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-local.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-local.ps1 -RebuildDatabase
#>
param(
    [switch]$RebuildDatabase,
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$webRoot = Join-Path $repoRoot 'web'
$udlPath = Join-Path $repoRoot 'config\hospital.udl'
$server = '(localdb)\MSSQLLocalDB'
$iisExpress = 'C:\Program Files\IIS Express\iisexpress.exe'
$siteUrl = "http://localhost:$Port/login.asp"

function Step($text) { Write-Host "-> $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "ERROR: $text" -ForegroundColor Red; exit 1 }

function Test-Site {
    try { return (Invoke-WebRequest $siteUrl -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { return $false }
}

# Passwords without characters that break sqlcmd, PowerShell or the .udl: ' " ; = $ `
function New-SafePassword {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789#%+!-_'.ToCharArray()
    $bytes = New-Object byte[] 20
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return 'Aa1#' + (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] }))
}

function Invoke-Sql([string[]]$sqlcmdArgs) {
    & sqlcmd @sqlcmdArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "sqlcmd failed: $($sqlcmdArgs -join ' ')" }
}

# ---- 1. Prerequisites ---------------------------------------------------
Step 'Checking prerequisites'
if (-not (Test-Path $iisExpress)) { Fail "IIS Express not found at $iisExpress" }
if (-not (Get-Command sqllocaldb -ErrorAction SilentlyContinue)) { Fail 'SQL Server LocalDB (sqllocaldb) not found' }
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { Fail 'sqlcmd not found' }
if (-not (Test-Path "$env:windir\System32\msoledbsql19.dll")) { Fail 'Microsoft OLE DB Driver 19 for SQL Server not installed' }

# ---- 2. LocalDB ---------------------------------------------------------
Step 'Starting LocalDB'
& sqllocaldb start MSSQLLocalDB | Out-Null
$dbExists = ((& sqlcmd -S $server -E -h -1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN DB_ID('LegacyHospital') IS NULL THEN 0 ELSE 1 END") -join '').Trim() -eq '1'

# ---- 3. Database + .udl -------------------------------------------------
if ($RebuildDatabase -or -not $dbExists) {
    Step 'Rebuilding the LegacyHospital database (development data only)'
    $webPassword = New-SafePassword
    $seedPassword = New-SafePassword
    Invoke-Sql @('-S', $server, '-E', '-b', '-Q', "IF DB_ID('LegacyHospital') IS NOT NULL BEGIN ALTER DATABASE LegacyHospital SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE LegacyHospital; END; IF SUSER_ID('hospital_web') IS NOT NULL DROP LOGIN hospital_web;")
    Invoke-Sql @('-S', $server, '-E', '-b', '-i', (Join-Path $repoRoot 'db\01_schema.sql'))
    Invoke-Sql @('-S', $server, '-E', '-b', '-i', (Join-Path $repoRoot 'db\02_procedures.sql'))
    Invoke-Sql @('-S', $server, '-E', '-b', '-i', (Join-Path $repoRoot 'db\03_security.sql'), '-v', "WebPassword=`"$webPassword`"")
    Invoke-Sql @('-S', $server, '-E', '-b', '-i', (Join-Path $repoRoot 'db\04_seed.sql'), '-v', "SeedPassword=`"$seedPassword`"")

    Step 'Writing config\hospital.udl'
    New-Item -ItemType Directory -Force (Split-Path $udlPath -Parent) | Out-Null
    $udl = "[oledb]`r`n; Everything after this line is an OLE DB initstring`r`n" +
           "Provider=MSOLEDBSQL19;Data Source=$server;Initial Catalog=LegacyHospital;User ID=hospital_web;" +
           "Password=$webPassword;Persist Security Info=False;Use Encryption for Data=Mandatory;Trust Server Certificate=True`r`n"
    [IO.File]::WriteAllText($udlPath, $udl, [Text.Encoding]::Unicode)

    Write-Host ''
    Write-Host 'New passwords (shown only now; save them in your password manager):' -ForegroundColor Yellow
    Write-Host "  Doctors (dr.garcia, dr.smith, dr.chen): $seedPassword"
    Write-Host "  hospital_web (already in config\hospital.udl): $webPassword"
    Write-Host ''
}
elseif (-not (Test-Path $udlPath)) {
    Fail 'config\hospital.udl is missing and the database already exists (its password is unknown). Run again with -RebuildDatabase.'
}

# ---- 4. Connection check ------------------------------------------------
Step 'Checking the database connection through config\hospital.udl'
$conn = New-Object -ComObject ADODB.Connection
try { $conn.Open("File Name=$udlPath;"); $conn.Close() }
catch { Fail "ADO could not connect with config\hospital.udl: $($_.Exception.Message)" }

# ---- 5. IIS Express -----------------------------------------------------
if (Test-Site) {
    Step "The site already answers on port $Port"
}
else {
    if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
        Fail "Port $Port is in use by something that is not this site. Stop it or use -Port."
    }
    Step "Starting IIS Express on port $Port (separate window; press Q there to stop it)"
    Start-Process -FilePath $iisExpress -ArgumentList "/path:`"$webRoot`"", "/port:$Port" -WindowStyle Minimized | Out-Null
    $deadline = (Get-Date).AddSeconds(20)
    while (-not (Test-Site)) {
        if ((Get-Date) -gt $deadline) { Fail "IIS Express started but $siteUrl does not answer. Check the IIS Express window." }
        Start-Sleep -Milliseconds 500
    }
}

Write-Host ''
Write-Host "Ready: $siteUrl" -ForegroundColor Green
