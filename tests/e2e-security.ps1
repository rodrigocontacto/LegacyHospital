<#
.SYNOPSIS
    End-to-end security checks over HTTP against the running site.

.DESCRIPTION
    Acts like a browser (cookies, no automatic redirects) and checks login,
    CSRF, session fixation, SQL injection, XSS, IDOR, input validation, the
    report sort whitelist, logout, security headers and static assets.

    Expects the seed data from db/04_seed.sql (dr.garcia with 4 patients and
    7 appointments in the default report range). Run it against a development
    database only: it performs failed logins and writes to AppErrorLog.

    Temporary: CLAUDE.md asks for xUnit tests in /tests. These checks will be
    ported to xUnit once the .NET version is decided.

.PARAMETER BaseUrl
    Site root. Default http://localhost:8080

.PARAMETER Password
    Password of the seed doctors. If omitted, read from the environment
    variable LEGACYHOSPITAL_SEED_PASSWORD. Never commit it.

.EXAMPLE
    $env:LEGACYHOSPITAL_SEED_PASSWORD = '<seed password>'
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e-security.ps1
#>
param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$Password = $env:LEGACYHOSPITAL_SEED_PASSWORD,
    # Used only to confirm that a rejected note was not inserted (Windows auth).
    [string]$SqlServer = '(localdb)\MSSQLLocalDB'
)

$ErrorActionPreference = 'Stop'
if (-not $Password) {
    Write-Error 'Seed password missing: pass -Password or set LEGACYHOSPITAL_SEED_PASSWORD.'
    exit 1
}

$base = $BaseUrl.TrimEnd('/')
$jar = New-Object System.Net.CookieContainer
$script:passed = 0
$script:failed = 0

function Send([string]$method, [string]$path, [string]$body = $null) {
    $req = [System.Net.HttpWebRequest]::Create("$base$path")
    $req.Method = $method
    $req.AllowAutoRedirect = $false
    $req.CookieContainer = $jar
    try {
        if ($body) {
            $req.ContentType = 'application/x-www-form-urlencoded'
            $bytes = [Text.Encoding]::UTF8.GetBytes($body)
            $req.ContentLength = $bytes.Length
            $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        }
        $resp = $req.GetResponse()
    } catch [System.Net.WebException] { $resp = $_.Exception.Response }
    # No response at all (e.g. IIS Express resets requests blocked by request filtering).
    if ($resp -eq $null) { return [pscustomobject]@{ Status = 0; Location = $null; SetCookie = $null; Headers = @{}; Body = '' } }
    $reader = New-Object IO.StreamReader($resp.GetResponseStream())
    $result = [pscustomobject]@{
        Status = [int]$resp.StatusCode
        Location = $resp.Headers['Location']
        SetCookie = $resp.Headers['Set-Cookie']
        Headers = $resp.Headers
        Body = $reader.ReadToEnd()
    }
    $resp.Close()
    return $result
}
function SessionId { ($jar.GetCookies([Uri]$base) | Where-Object { $_.Name -like 'ASPSESSIONID*' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';' }
function Csrf($html) { [regex]::Match($html, 'name="csrf_token" value="([0-9A-F]{64})"').Groups[1].Value }
function Enc($v) { [Uri]::EscapeDataString($v) }
function Check($desc, $ok) {
    if ($ok) { $script:passed++ } else { $script:failed++ }
    "{0,-58} {1}" -f $desc, $(if ($ok) { 'OK' } else { 'FAIL' })
}

# --- Preflight: the site must be running
$first = Send GET '/login.asp'
if ($first.Status -ne 200) {
    Write-Error "Site not reachable at $base/login.asp. Start it first (see the run-local skill)."
    exit 1
}

# --- ASP session cookie attributes (F-02, URL Rewrite outbound rule)
$sessionCookiePattern = 'ASPSESSIONID[A-Z]{8}=[^;,]+; path=/; HttpOnly; SameSite=Lax'
Check 'ASP session cookie has HttpOnly; SameSite=Lax (F-02)' ($first.SetCookie -match $sessionCookiePattern)

# --- Unauthenticated access
$r = Send GET '/search.asp'
Check 'search.asp without login -> 302 login.asp' ($r.Status -eq 302 -and $r.Location -like '*login.asp*')

# --- Login page + headers
$r = Send GET '/login.asp'
$token = Csrf $r.Body
Check 'login.asp 200 with CSRF token' ($r.Status -eq 200 -and $token.Length -eq 64)
Check 'header X-Frame-Options: DENY' ($r.Headers['X-Frame-Options'] -eq 'DENY')
Check 'header X-Content-Type-Options: nosniff' ($r.Headers['X-Content-Type-Options'] -eq 'nosniff')
Check 'header Content-Security-Policy present' ([bool]$r.Headers['Content-Security-Policy'])
Check 'header Cache-Control: no-store' ($r.Headers['Cache-Control'] -like '*no-store*')
Check 'no Server / X-Powered-By headers' (-not $r.Headers['Server'] -and -not $r.Headers['X-Powered-By'])

# --- Failed logins (generic message)
$r = Send POST '/login.asp' ("csrf_token=$token&username=dr.garcia&password=" + (Enc 'wrong-password'))
Check 'wrong password -> generic message' ($r.Status -eq 200 -and $r.Body -like '*Invalid username or password.*')
$r = Send POST '/login.asp' ("csrf_token=$token&username=nobody&password=x")
Check 'unknown user -> same generic message' ($r.Body -like '*Invalid username or password.*')

# --- CSRF missing
$r = Send POST '/login.asp' ("username=dr.garcia&password=" + (Enc $Password))
Check 'login POST without CSRF token -> redirect to error.asp' ($r.Status -eq 302 -and $r.Location -like '*error.asp*')

# --- Correct login (two steps) and session fixation (F-07)
$r = Send GET '/login.asp'; $token = Csrf $r.Body; $before = SessionId
$r = Send POST '/login.asp' ("csrf_token=$token&username=dr.garcia&password=" + (Enc $Password))
Check 'login step 1: POST -> 302 login.asp' ($r.Status -eq 302 -and $r.Location -like '*login.asp*')
$r = Send GET '/login.asp'
Check 'login step 2: GET with ticket -> 302 search.asp' ($r.Status -eq 302 -and $r.Location -like '*search.asp*')
Check 'login step 2: new session cookie has HttpOnly (F-02)' ($r.SetCookie -match $sessionCookiePattern)
Check 'login step 2: LoginTicket deleted, attributes intact' ($r.SetCookie -match 'LoginTicket=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/; HttpOnly; SameSite=Strict')
$after = SessionId
Check 'session ID changed after login (F-07)' ($before -ne $after -and $after -ne '')

# --- Search: SQL injection and XSS
$r = Send GET '/search.asp?q='
Check 'search empty -> 4 patients' ($r.Body -like '*>4 patients<*')
$r = Send GET ('/search.asp?q=' + (Enc "' OR 1=1 --"))
Check "search ' OR 1=1 -- -> no results" ($r.Body -like '*No patients found.*')
$r = Send GET ('/search.asp?q=' + (Enc '<script>alert(1)</script>'))
Check 'search <script> -> encoded, not raw' ($r.Body -like '*&lt;script&gt;alert(1)&lt;/script&gt;*' -and $r.Body -notlike '*<script>alert(1)*')
$r = Send GET ('/search.asp?q=' + (Enc '"><img src=x onerror=alert(1)>'))
Check 'search attribute breakout -> &quot; encoded' ($r.Body -like '*value="&quot;&gt;&lt;img*')
$r = Send GET ('/search.asp?q=' + (Enc "O'Brien"))
Check "search O'Brien -> found" ($r.Body -like '*>1 patient<*' -and $r.Body -like '*MRN-0002*')

# --- Patient record: IDOR and ID validation
$r = Send GET '/patient.asp?id=2'
Check 'patient 2 (own) -> 200, XSS note encoded' ($r.Status -eq 200 -and $r.Body -like '*&lt;script&gt;alert(1)&lt;/script&gt;*')
$r5 = Send GET '/patient.asp?id=5'
$r99 = Send GET '/patient.asp?id=99999'
Check 'patient 5 (other doctor) -> 404' ($r5.Status -eq 404)
Check 'patient 99999 (missing) -> 404' ($r99.Status -eq 404)
Check '404 bodies identical (no existence leak)' ($r5.Body -eq $r99.Body)
foreach ($bad in @('abc', '-1', '1%20OR%201=1', '1&id=5', '007')) {
    $r = Send GET "/patient.asp?id=$bad"
    Check "patient id=$bad -> 400" ($r.Status -eq 400)
}

# --- Add note: CSRF, IDOR, validation, stored XSS
# Each run adds two notes to patient 2 (O'Brien); no check depends on the count.
function NoteCount([int]$patientId) {
    if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { return $null }
    $value = (& sqlcmd -S $SqlServer -E -d LegacyHospital -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.PatientNotes WHERE PatientId = $patientId") -join ''
    if ($LASTEXITCODE -ne 0) { return $null }
    return [int]$value.Trim()
}

$r = Send GET '/add_note.asp?id=2'
$noteToken = Csrf $r.Body
Check 'add_note own patient -> 200 form with CSRF token' ($r.Status -eq 200 -and $r.Body -like '*name="note_text"*' -and $noteToken.Length -eq 64)
$r = Send GET '/add_note.asp?id=5'
Check 'add_note other doctor -> 404, same body as patient.asp' ($r.Status -eq 404 -and $r.Body -eq $r5.Body)
$r = Send GET '/add_note.asp?id=abc'
Check 'add_note id=abc -> 400' ($r.Status -eq 400)
$r = Send POST '/add_note.asp?id=2' ('note_text=' + (Enc 'no token'))
Check 'add_note POST without CSRF token -> error.asp' ($r.Status -eq 302 -and $r.Location -like '*error.asp*')

$before = NoteCount 5
$r = Send POST '/add_note.asp?id=5' ("csrf_token=$noteToken&note_text=" + (Enc 'note on another doctor''s patient'))
$after = NoteCount 5
Check 'add_note POST to other doctor -> 404' ($r.Status -eq 404)
if ($before -eq $null) { "{0,-58} {1}" -f 'add_note POST to other doctor -> no row inserted', 'SKIP (no sqlcmd)' }
else { Check 'add_note POST to other doctor -> no row inserted' ($before -eq $after) }

$r = Send POST '/add_note.asp?id=2' ("csrf_token=$noteToken&note_text=" + (Enc "   `r`n  "))
Check 'add_note blank note -> validation message' ($r.Status -eq 200 -and $r.Body -like '*Write the note before saving.*')
$r = Send POST '/add_note.asp?id=2' ("csrf_token=$noteToken&note_text=" + ('a' * 2001))
Check 'add_note 2001 chars -> validation message, text kept' ($r.Body -like '*at most 2000 characters*' -and $r.Body -like ('*>' + ('a' * 2001) + '</textarea>*'))
# 1998 chars + CRLF + 1 char = 2001 bytes sent, 2000 characters for the browser.
$r = Send POST '/add_note.asp?id=2' ("csrf_token=$noteToken&note_text=" + ('b' * 1998) + '%0D%0Ac')
Check 'add_note 2000 chars with CRLF -> saved (line breaks normalized)' ($r.Status -eq 302 -and $r.Location -like '*patient.asp?id=2&added=1*')
$xssNote = '<img src=x onerror=alert(1)> e2e stored XSS test'
$r = Send POST '/add_note.asp?id=2' ("csrf_token=$noteToken&note_text=" + (Enc $xssNote))
Check 'add_note valid note -> 302 patient.asp?id=2&added=1' ($r.Status -eq 302 -and $r.Location -like '*patient.asp?id=2&added=1*')
$r = Send GET '/patient.asp?id=2&added=1'
Check 'stored note shown encoded, success message' ($r.Body -like '*&lt;img src=x onerror=alert(1)&gt; e2e stored XSS test*' -and $r.Body -notlike '*<img src=x*' -and $r.Body -like '*Note added.*')

# --- Appointments report: whitelist, validation, encoding
$r = Send GET '/report.asp'
Check 'report default -> 7 appointments' ($r.Body -like '*>7 appointments<*')
Check 'report stats: 4 scheduled, 2 completed, 1 cancelled' ($r.Body -match 'Scheduled</span>\s*<span class="stat__value">4<' -and $r.Body -match 'Completed</span>\s*<span class="stat__value">2<' -and $r.Body -match 'Cancelled</span>\s*<span class="stat__value">1<')
Check 'report <b> reason encoded' ($r.Body -like '*&lt;b&gt;Physiotherapy&lt;/b&gt;*')
$r = Send GET ('/report.asp?from=2026-11-01&to=2026-11-30&sort=' + (Enc 'LastName;DROP TABLE PatientNotes'))
Check 'report injected sort -> 400' ($r.Status -eq 400)
$r = Send GET '/report.asp?from=2026-01-01&to=2026-12-31&sort=LastName'
Check 'report 364-day range -> validation message' ($r.Body -like '*at most 90 days*')

# --- Logout
$r = Send GET '/logout.asp'
Check 'logout via GET -> no logout (302 search.asp)' ($r.Status -eq 302 -and $r.Location -like '*search.asp*')
$r = Send GET '/search.asp'; $token = Csrf $r.Body
$r = Send POST '/logout.asp' "csrf_token=$token"
Check 'logout via POST -> 302 login.asp?signedout=1' ($r.Status -eq 302 -and $r.Location -like '*signedout=1*')
$r = Send GET '/patient.asp?id=2'
Check 'after logout, patient.asp -> 302 login' ($r.Status -eq 302 -and $r.Location -like '*login.asp*')

# --- Hidden files and static assets
$r = Send GET '/includes/app.asp'
Check '/includes/app.asp -> not served (404 or reset)' ($r.Status -eq 404 -or $r.Status -eq 0)
$r = Send GET '/assets/css/app.css'
Check '/assets/css/app.css -> 200 text/css' ($r.Status -eq 200 -and $r.Headers['Content-Type'] -like 'text/css*')
$r = Send GET '/assets/img/logo.svg'
Check '/assets/img/logo.svg -> 200' ($r.Status -eq 200)
$r = Send GET '/login.asp'
Check 'login.asp has no inline style or script (CSP)' ($r.Body -notmatch 'style=|<style|<script')

""
"{0} passed, {1} failed" -f $script:passed, $script:failed
if ($script:failed -gt 0) { exit 1 }
exit 0
