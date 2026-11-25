---
name: run-local
description: Start LegacyHospital locally (LocalDB + IIS Express on web/, https://localhost:44300; http://localhost:8080 redirects) and diagnose why it does not start. Use when the user wants to run, start, restart or "levantar" the site, sees "Something went wrong" on every page, cannot log in, or needs a fresh database.
---

# Run LegacyHospital locally

Everything is automated in `tools/run-local.ps1`. Do not repeat its steps by hand.

## Start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-local.ps1
```

It checks prerequisites, starts LocalDB, applies `db\01` and `db\02` to an existing
database (safe to re-run, no data loss), restricts `config\` to the current user,
checks that `config\hospital.udl` connects, and starts IIS Express on `web\` in its own
window (it survives the Claude session): HTTPS on 44300 (IIS Express development
certificate), HTTP on 8080 only redirects. If the site already answers, it does not
start a second server.

Fresh database (DROPS the LocalDB database, generates new passwords, rewrites the `.udl`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-local.ps1 -RebuildDatabase
```

Ask the user before using `-RebuildDatabase`: it deletes all local data. The new
passwords are printed once. Show them to the user once, never write them to a file in
the repo, a commit message or a doc.

Other ports: `-Port 8081 -HttpsPort 44301` (HTTPS must stay in 44300-44399, where the
development certificate is bound; also change the `HttpsPortSuffix` map in
`web/web.config`).

## Verify

```powershell
$env:LEGACYHOSPITAL_SEED_PASSWORD = '<doctors password>'
powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e-security.ps1
```

All checks must pass. If the seed password is not known, ask the user (or rebuild).
The last checks trigger the login rate limit: sign-ins from this machine get 429 for
about a minute afterwards, and dr.smith stays locked for this IP for 15 minutes.

## Diagnose

| Symptom | Check |
|---|---|
| Every page shows "Something went wrong" | `sqlcmd -S "(localdb)\MSSQLLocalDB" -E -d LegacyHospital -Q "SELECT TOP 5 CreatedAt, PageName, ErrorDetail FROM dbo.AppErrorLog ORDER BY ErrorId DESC"` |
| `Login failed for user 'hospital_web'` in the log | The `.udl` password does not match the login: run with `-RebuildDatabase` (ask first) |
| Script says `.udl` missing and database exists | The password is unknown: `-RebuildDatabase` (ask first) |
| "Invalid username or password" with the right password | 5 failures for that username from this IP lock the pair for 15 minutes; 50 from anywhere lock the account for 15 minutes. See why: `sqlcmd -S "(localdb)\MSSQLLocalDB" -E -d LegacyHospital -Q "SELECT TOP 10 CreatedAt, Username, IpAddress, Outcome, Detail FROM dbo.SecurityAudit WHERE EventType = 'Login' ORDER BY AuditId DESC"`. Development only, to unlock: `UPDATE dbo.Users SET FailedLoginCount = 0, LockoutUntil = NULL; DELETE dbo.SecurityAudit WHERE EventType IN ('Login', 'CsrfCheck') AND Outcome <> 'Success'` |
| "Too many attempts" (429) | 30 failures from this IP in the last minute (F-04). Wait a minute |
| "Your session has ended" | 8 hours since sign-in, or the user was deactivated (F-12) |
| Port 8080 or 44300 in use | Visual Studio may be running the site already (that is fine: the script detects it), or an IIS Express started before HTTPS was added (stop it). Otherwise use `-Port` / `-HttpsPort` |
| Browser warns about the certificate | The IIS Express development certificate is not trusted for this user: repair IIS Express, or trust it in `certmgr.msc` |
| Visual Studio shows old files | Solution Explorer > right-click `web` > Refresh Folder, or reopen `LegacyHospital.sln` |
| `/includes/...`, `/global.asa`, `/web.config` reset the connection | Expected under IIS Express: request filtering blocks them |

The script starts IIS Express with its own config (`/config` + `/site`, in
`%LOCALAPPDATA%\LegacyHospital\iisexpress`), never with `/path`: `/path` regenerates a
temp config from the Program Files template on every start and would undo
`scriptErrorSentToBrowser="false"` (finding F-01). Never re-enable it; the error detail
is in `AppErrorLog`. After changing IIS settings, stop IIS Express (Q in its window) and
run the script again.

If Visual Studio adds `<system.web><compilation debug="true"/>` to `web/web.config`
(it offers it on F5), remove it: start the site with Ctrl+F5 instead.
