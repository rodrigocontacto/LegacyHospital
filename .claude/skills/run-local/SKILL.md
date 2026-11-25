---
name: run-local
description: Start LegacyHospital locally (LocalDB + IIS Express on web/, http://localhost:8080) and diagnose why it does not start. Use when the user wants to run, start, restart or "levantar" the site, sees "Something went wrong" on every page, cannot log in, or needs a fresh database.
---

# Run LegacyHospital locally

Everything is automated in `tools/run-local.ps1`. Do not repeat its steps by hand.

## Start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-local.ps1
```

It checks prerequisites, starts LocalDB, checks that `config\hospital.udl` connects,
and starts IIS Express on `web\` in its own window (it survives the Claude session).
If the site already answers on the port, it does not start a second server.

Fresh database (DROPS the LocalDB database, generates new passwords, rewrites the `.udl`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-local.ps1 -RebuildDatabase
```

Ask the user before using `-RebuildDatabase`: it deletes all local data. The new
passwords are printed once. Show them to the user once, never write them to a file in
the repo, a commit message or a doc.

Other port: `-Port 8081`.

## Verify

```powershell
$env:LEGACYHOSPITAL_SEED_PASSWORD = '<doctors password>'
powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e-security.ps1
```

All checks must pass. If the seed password is not known, ask the user (or rebuild).

## Diagnose

| Symptom | Check |
|---|---|
| Every page shows "Something went wrong" | `sqlcmd -S "(localdb)\MSSQLLocalDB" -E -d LegacyHospital -Q "SELECT TOP 5 CreatedAt, PageName, ErrorDetail FROM dbo.AppErrorLog ORDER BY ErrorId DESC"` |
| `Login failed for user 'hospital_web'` in the log | The `.udl` password does not match the login: run with `-RebuildDatabase` (ask first) |
| Script says `.udl` missing and database exists | The password is unknown: `-RebuildDatabase` (ask first) |
| "Invalid username or password" with the right password | 5 failures lock the account for 5 minutes. Unlock: `sqlcmd -S "(localdb)\MSSQLLocalDB" -E -d LegacyHospital -Q "UPDATE dbo.Users SET FailedLoginCount = 0, LockoutUntil = NULL"` |
| Port 8080 in use | Visual Studio may be running the site already (that is fine: the script detects it). Otherwise stop the other process or use `-Port` |
| Visual Studio shows old files | Solution Explorer > right-click `web` > Refresh Folder, or reopen `LegacyHospital.sln` |
| `/includes/...`, `/global.asa`, `/web.config` reset the connection | Expected under IIS Express: request filtering blocks them |

ASP error details in the browser come from IIS Express `scriptErrorSentToBrowser="true"`
(finding F-01). Useful while debugging; tell the user to turn it off afterwards:
`& "C:\Program Files\IIS Express\appcmd.exe" set config -section:system.webServer/asp /scriptErrorSentToBrowser:false /commit:apphost`
