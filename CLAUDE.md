# LegacyHospital

Small patient portal for a fictional hospital, built in Classic ASP (VBScript)
on IIS with SQL Server. Portfolio project that shows secure coding in a
legacy Microsoft stack. All patient data is fake.

## Stack
- Classic ASP + VBScript, IIS (site root: /web, https://localhost:44300;
  http://localhost:8080 only redirects to HTTPS)
- SQL Server Express, database LegacyHospital, T-SQL scripts in /db
- Security tests: xUnit + HttpClient in /tests (.NET 8)

## Naming
- Everything in English: files, tables, columns, procedures, functions,
  variables and comments.
- Stored procedures use the usp_ prefix (never sp_, reserved for system procs).

## Security rules (mandatory, no exceptions)
- Every query uses ADODB.Command with parameters. Never build SQL by
  concatenating strings, not even for numeric values.
- Stored procedures with dynamic SQL use sp_executesql with parameters.
  Column names for ORDER BY come from a whitelist and go through QUOTENAME.
- Every value written to HTML goes through Server.HTMLEncode.
  HTML attributes always use double quotes (HTMLEncode does not encode ').
- Every page includes /web/includes/app.asp (plus, at the end, its own
  view from includes/views/) and, except login.asp, calls RequireLogin()
  first.
  Exception: error.asp does not call RequireLogin() (fixed message, no
  data, no actions; avoids a redirect loop when login.asp fails).
- IDs from Request are validated as integers before use, and access to
  the resource is checked against the logged-in user (no IDOR).
- Every POST form includes a CSRF token and the handler validates it.
- Random tokens come from SQL Server CRYPT_GEN_RANDOM, never from Rnd().
- The web app connects with a dedicated SQL login (hospital_web) that only
  has EXECUTE on the app stored procedures. Never use sa.
- Connection strings live outside the web root, never in code.
- Users never see technical errors. Log the detail, show a generic message.

## Structure (web/)
- Pages (*.asp in web/) are controllers: RequireLogin, read and validate
  input, call data functions, then include their view. No SQL, no long HTML.
- includes/core/: infrastructure (db, errors, http, encoding,
  validation, csrf, auth).
- includes/data/: one file per entity, one function per stored procedure
  (Entity_Action, e.g. Patients_Search). Stored procedures are only
  called from here.
- includes/views/: layout.asp, components.asp and one *_view.asp per
  page. Views only print variables through Html() / HtmlMultiline().
- Constants are prefixed by file (PATIENT_COL_*, NOTE_COL_*): VBScript has
  no namespaces and a repeated name breaks every page.
- Styles live in web/assets/css/app.css. No inline style or script (CSP).

## Tooling
- tools/run-local.ps1: start LocalDB + IIS Express on web/ (https://localhost:44300).
  -RebuildDatabase recreates the database and config/hospital.udl.
- tests/asp-syntax-check.ps1: compile-only check of every page. Runs
  automatically after each Edit/Write of web/*.asp|asa (hook in
  .claude/settings.json).
- tests/e2e-security.ps1: HTTP security checks against the running site
  (password from LEGACYHOSPITAL_SEED_PASSWORD). To be ported to xUnit.
- Skills: /run-local, /new-page, /asp-review (.claude/skills/).

## Code style
- Option Explicit at the top of every .asp file.
- Response.CodePage = 65001 and Response.Charset = "utf-8" (set once in
  includes/app.asp; pages also declare CodePage="65001").
- Short functions in the includes, not repeated code.
- Always close and release ADO objects (rs.Close, Set rs = Nothing).

## How to work with me
- Work one part at a time. Do not create files outside what I ask for.
- Before writing code, show me a short plan.
- After writing code, tell me how to test it manually in the browser.
- If you are not sure something works in VBScript (not VB.NET), say so.
- Never weaken a security rule to make something work. Ask me instead.