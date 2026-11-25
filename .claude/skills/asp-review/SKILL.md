---
name: asp-review
description: Security review of LegacyHospital's Classic ASP and T-SQL code against the CLAUDE.md rules (encoding, CSRF, IDOR, parameterized SQL, layers, CSP). Use when the user asks to review, audit or check a page, a change or the whole web/ and db/ folders, or before a commit. Reports findings; does not change code unless asked.
argument-hint: [file or folder; default web/ and db/]
---

# LegacyHospital security review

Scope: the files the user names, otherwise `web/` and `db/`. Do not edit code unless the
user asks. Read each file in scope in full; the searches below find candidates, they do
not replace reading.

## Checks

| ID | Rule (CLAUDE.md) | How to find candidates |
|---|---|---|
| R1 | Every page includes `includes/app.asp`; every page except `login.asp` and `error.asp` calls `RequireLogin` before anything else | Read the top of each `web/*.asp` |
| R2 | Stored procedures are called only from `includes/data/` | Grep `CreateSpCommand\(` and `ADODB.Command` outside `web/includes/data/` (`core/errors.asp` LogError is the one allowed exception) |
| R3 | Every value written to HTML goes through `Html()` / `HtmlMultiline()` | Grep `<%=` and `Response.Write` in `web/`; allowed without `Html()`: `CsrfField()`, `Icon()`, `StatusBadge()`, `Avatar()`, `ActiveClass()`, `AriaCurrent()` and fixed strings |
| R4 | Attributes use double quotes | Grep `\s[a-zA-Z-]+=('<%=|<%=)` (a query string inside a quoted attribute, like `href="/patient.asp?id=<%= …`, is fine and does not match) |
| R5 | IDs from Request validated with `IsValidInteger` before use; ownership checked in the procedure by `@UserId` | Grep `Request\.(QueryString|Form)` and `CLng\(`; check the procedure filters by `@UserId` |
| R6 | User ID only from `CurrentUserId()` / session | Grep `UserId` in `web/*.asp`: never from Request |
| R7 | Every POST handler calls `ValidateCsrfToken`; every `method="post"` form has `CsrfField()` | Grep `IsPostRequest\(\)` and `method="post"` |
| R8 | Dates via `ParseIsoDate`, sort/filter values via a whitelist (`IsInList`) in ASP and again in SQL | Grep `ParseIsoDate`, `IsInList`, `QUOTENAME` |
| R9 | SQL: no string concatenation of values; dynamic SQL only `sp_executesql` with parameters; identifiers from a whitelist + `QUOTENAME`; procedures prefixed `usp_` in schema `app` | In `db/*.sql` grep `EXEC\s*\(`, `EXECUTE\s*\(`, `+ @`, `sp_executesql`, `CREATE OR ALTER PROCEDURE` |
| R10 | Procedures filter by `@UserId`; "not found" and "not yours" are indistinguishable | Read each `app.usp_*` |
| R11 | Redirects only to fixed URLs | Grep `RedirectTo` and `Response.Redirect`: argument never built from Request |
| R12 | Users never see technical errors | Grep `Err.Description`, `Err.Number` in views/pages: only passed to `HandleFatalError`/`LogError` |
| R13 | No inline style or script (CSP) | Grep `style=`, `<style`, `<script` in `web/`; ignore VBScript comment lines (starting with `'`) |
| R14 | Constants prefixed by file; no duplicates | `tests/asp-syntax-check.ps1` reports "Name redefined" |
| R15 | Names and comments in English; `Option Explicit` on every page | Read |

Also check `web/web.config`, `.gitignore` (nothing from `config/` or `.vs/` committed)
and that no password or connection string appears in the repo
(grep `Password=` and `PWD=` followed by a value; placeholders like
`Password=CLAVE_WEB` in docs and this file are fine).

## Run the automated checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\asp-syntax-check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e-security.ps1   # needs the site running (run-local skill)
```

## Report

One table, most severe first:

| ID | File:line | Rule | Severity (High/Medium/Low) | Why it is a problem | Fix |

Mark uncertain items as "low confidence" and say why. Then list what is done well.
Compare with open findings in `docs/security-review.md`; do not duplicate them, reference
their F-ID instead. Offer to add new findings to that file.
