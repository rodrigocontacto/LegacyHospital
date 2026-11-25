<#
.SYNOPSIS
    Starts LegacyHospital locally: LocalDB + IIS Express on web/.

.DESCRIPTION
    1. Checks prerequisites (IIS Express, LocalDB, sqlcmd, OLE DB Driver 19).
    2. Starts LocalDB.
    3. With -RebuildDatabase (or when the database does not exist): generates
       two random passwords, recreates the database from db/01..04, writes
       config/hospital.udl (UTF-16) and prints the passwords ONCE.
    4. Restricts config/ to the current user, Administrators and SYSTEM (F-08).
    5. Checks that the .udl connects with ADO (the same driver ASP uses).
    6. Starts IIS Express on web/ in its own window (keeps running after this
       script ends), unless the site already answers on the port.
       HTTP (8080) only redirects to HTTPS (44300) (F-03). IIS Express
       installs a trusted development certificate for ports 44300-44399.
       The HTTP -> HTTPS port pair is also in web.config (HttpsPortSuffix):
       change both together.

    Development only: -RebuildDatabase DROPS the LocalDB database.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-local.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-local.ps1 -RebuildDatabase
#>
param(
    [switch]$RebuildDatabase,
    [int]$Port = 8080,
    [int]$HttpsPort = 44300
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$webRoot = Join-Path $repoRoot 'web'
$configDir = Join-Path $repoRoot 'config'
$udlPath = Join-Path $configDir 'hospital.udl'
$server = '(localdb)\MSSQLLocalDB'
$iisExpress = 'C:\Program Files\IIS Express\iisexpress.exe'
$siteUrl = "https://localhost:$HttpsPort/login.asp"

# Windows PowerShell 5.1 may default to old TLS versions.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Step($text) { Write-Host "-> $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "ERROR: $text" -ForegroundColor Red; exit 1 }

function Test-Site {
    try { return (Invoke-WebRequest $siteUrl -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { return $false }
}

# F-16: sqlcmd variables are pasted into the scripts as text, so passwords
# are passed as hex of their UTF-16LE bytes (see db/03_security.sql).
function ConvertTo-PasswordHex([string]$password) {
    return -join ([Text.Encoding]::Unicode.GetBytes($password) | ForEach-Object { $_.ToString('X2') })
}

# Passwords without characters that break PowerShell or the .udl: ' " ; = $ `
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
    Invoke-Sql @('-S', $server, '-E', '-b', '-i', (Join-Path $repoRoot 'db\03_security.sql'), '-v', "WebPasswordHex=$(ConvertTo-PasswordHex $webPassword)")
    Invoke-Sql @('-S', $server, '-E', '-b', '-i', (Join-Path $repoRoot 'db\04_seed.sql'), '-v', 'Environment=Dev', "SeedPasswordHex=$(ConvertTo-PasswordHex $seedPassword)")

    Step 'Writing config\hospital.udl'
    New-Item -ItemType Directory -Force $configDir | Out-Null
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
else {
    # Existing databases get the new schema and procedures (both scripts
    # are safe to re-run; they never drop data or change passwords).
    Step 'Updating schema and procedures (db\01, db\02)'
    Invoke-Sql @('-S', $server, '-E', '-b', '-i', (Join-Path $repoRoot 'db\01_schema.sql'))
    Invoke-Sql @('-S', $server, '-E', '-b', '-i', (Join-Path $repoRoot 'db\02_procedures.sql'))
}

# ---- 4. config\ permissions (F-08) ---------------------------------------
# The .udl holds the hospital_web password. Only the current user (who
# runs IIS Express), Administrators and SYSTEM may read the folder.
# SIDs instead of names: names are localized ("Administradores").
# On full IIS: grant the app pool identity read access instead of the
# current user, or better, use Windows authentication (see docs).
Step 'Restricting config\ to the current user, Administrators and SYSTEM (F-08)'
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls $configDir '/inheritance:r' '/grant:r' "*${userSid}:(OI)(CI)F" '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '/Q' | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "icacls could not restrict $configDir" }
# Files inside inherit exactly the folder's ACL (and nothing else).
if (Get-ChildItem $configDir -Force) {
    & icacls (Join-Path $configDir '*') '/reset' '/T' '/Q' | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "icacls could not reset the permissions inside $configDir" }
}

# ---- 5. Connection check ------------------------------------------------
Step 'Checking the database connection through config\hospital.udl'
$conn = New-Object -ComObject ADODB.Connection
try { $conn.Open("File Name=$udlPath;"); $conn.Close() }
catch { Fail "ADO could not connect with config\hospital.udl: $($_.Exception.Message)" }

# ---- 6. IIS Express -----------------------------------------------------
# A dedicated IIS Express config (outside the repo) instead of /path:
# /path regenerates a temp config from the template in Program Files on
# every start, so settings such as F-01 below would be lost.
$appcmd = 'C:\Program Files\IIS Express\appcmd.exe'
$siteName = 'LegacyHospital'
$iisConfigDir = Join-Path $env:LOCALAPPDATA 'LegacyHospital\iisexpress'
$iisConfig = Join-Path $iisConfigDir 'applicationhost.config'

function Invoke-AppCmd([string[]]$appcmdArgs, [string]$config) {
    $output = & $appcmd @appcmdArgs "/apphostconfig:$config" 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "appcmd $($appcmdArgs -join ' ') failed: $output" }
}

Step "Preparing IIS Express config ($iisConfig)"
if (-not (Test-Path $iisConfig)) {
    New-Item -ItemType Directory -Force $iisConfigDir | Out-Null
    Copy-Item 'C:\Program Files\IIS Express\AppServer\applicationhost.config' $iisConfig
}
& $appcmd list site $siteName "/apphostconfig:$iisConfig" | Out-Null
$bindings = "http/:${Port}:localhost,https/:${HttpsPort}:localhost"
if ($LASTEXITCODE -ne 0) {
    Invoke-AppCmd @('add', 'site', "/name:$siteName", "/physicalPath:$webRoot", "/bindings:$bindings") $iisConfig
}
Invoke-AppCmd @('set', 'vdir', "$siteName/", "/physicalPath:$webRoot") $iisConfig
Invoke-AppCmd @('set', 'site', $siteName, "/bindings:$bindings") $iisConfig

# The Visual Studio config (.vs, used when the site runs from
# LegacyHospital.sln) gets the same root (F-10: web/, never the repo
# root, which would expose config/ and db/) and the HTTPS binding (F-03).
$vsConfig = Join-Path $repoRoot '.vs\LegacyHospital\config\applicationhost.config'
if (Test-Path $vsConfig) {
    $vsSite = 'WebSite1'
    & $appcmd list site $vsSite "/apphostconfig:$vsConfig" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Invoke-AppCmd @('set', 'vdir', "$vsSite/", "/physicalPath:$webRoot") $vsConfig
        Invoke-AppCmd @('set', 'site', $vsSite, "/bindings:$bindings") $vsConfig
    }
}

# ASP settings: the <asp> section is locked for web.config, so they are
# set here, in this config and in the Visual Studio one.
#   F-01: never send ASP error details to the browser.
#   F-03: the ASP session cookie only travels over HTTPS (Secure).
Step 'Configuring ASP: no error details in the browser (F-01), Secure session cookie (F-03)'
$apphostConfigs = @($iisConfig, $vsConfig) | Where-Object { Test-Path $_ }
foreach ($config in $apphostConfigs) {
    Invoke-AppCmd @('set', 'config', '-section:system.webServer/asp', '/scriptErrorSentToBrowser:false', '/session.keepSessionIdSecure:true', '/commit:apphost') $config
}

if (Test-Site) {
    Step "The site already answers on port $HttpsPort (restart it to apply config changes)"
}
else {
    foreach ($p in @($Port, $HttpsPort)) {
        if (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) {
            Fail "Port $p is in use by something that is not this site (an old instance started before HTTPS was added? stop it). Or use -Port / -HttpsPort."
        }
    }
    Step "Starting IIS Express on ports $Port (redirect) and $HttpsPort (HTTPS) (separate window; press Q there to stop it)"
    Start-Process -FilePath $iisExpress -ArgumentList "/config:`"$iisConfig`"", "/site:$siteName" -WindowStyle Minimized | Out-Null
    $deadline = (Get-Date).AddSeconds(20)
    while (-not (Test-Site)) {
        if ((Get-Date) -gt $deadline) { Fail "IIS Express started but $siteUrl does not answer. Check the IIS Express window." }
        Start-Sleep -Milliseconds 500
    }
}

Write-Host ''
Write-Host "Ready: $siteUrl" -ForegroundColor Green
