---
name: new-page
description: Add a new Classic ASP page to LegacyHospital following the layered structure (controller in web/, data function in includes/data, view in includes/views) and the CLAUDE.md security rules. Use when the user asks to create a page, screen, form or endpoint in web/ (for example add_note.asp).
argument-hint: <page name> <what it does>
---

# Add a page

Read `CLAUDE.md` first ("Security rules" and "Structure"). Before writing code, show the
user a short plan (CLAUDE.md requires it):

1. URL, method (GET read-only, or GET form + POST handler) and what it shows or changes.
2. Stored procedure: existing one, or a new `app.usp_Entity_Action` (show its signature).
3. Data function name (`Entity_Action`), controller variables and view.
4. Security: which IDs come from the request, how ownership is checked, CSRF if POST.

Wait for approval, then create the pieces in this order.

## 1. Stored procedure (only if needed) - `db/02_procedures.sql`

- `CREATE OR ALTER PROCEDURE app.usp_Entity_Action` (never `sp_`), `SET NOCOUNT ON`.
- Takes `@UserId` and filters every row by it (for patients: `AssignedUserId = @UserId`).
  "Not found" and "not yours" must look the same.
- Return codes: 0 ok, 1 not found / not allowed, 2 invalid input.
- Text parameters wider than the column so long input is rejected, not truncated.
- Dynamic SQL only with `sp_executesql`, whitelist + `QUOTENAME` for identifiers, and
  `WITH EXECUTE AS N'app_dynamic_reader'` (grant it SELECT on any new table).
- Re-run `02_procedures.sql` on LocalDB and test the procedure as `hospital_web`
  (`EXECUTE AS USER = 'hospital_web'`), including another doctor's ID.

## 2. Data function - `web/includes/data/<entity>.asp`

```vbscript
' Column positions in the rows of Notes_Something.
Const NOTE_COL_SOMETHING = 0

Function Notes_Add(ByVal userId, ByVal patientId, ByVal noteText)
    Dim cmd
    ' app.usp_PatientNote_Add @UserId, @PatientId, @NoteText, @NoteId OUT
    Set cmd = CreateSpCommand("app.usp_PatientNote_Add")
    AddInputParam cmd, "@UserId", adInteger, 0, userId
    AddInputParam cmd, "@PatientId", adInteger, 0, patientId
    AddInputParam cmd, "@NoteText", adVarWChar, 4000, noteText
    AddOutputParam cmd, "@NoteId", adInteger, 0
    ExecuteNonQuery cmd
    Notes_Add = GetReturnValue(cmd)
    Set cmd = Nothing
End Function
```

- Parameters bind BY POSITION: append them in the procedure's order and keep the
  signature comment above `CreateSpCommand` up to date.
- Constants prefixed with the entity (`NOTE_COL_*`). A duplicate name breaks every page.
- New entity file: add its `#include` to `web/includes/app.asp`.

## 3. Controller - `web/<page>.asp`

```asp
<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' <page>.asp - <what it does> (controller).
' =====================================================================
RequireLogin

Dim idText, patientId, errorMessage
idText = Request.QueryString("id") & ""
If Not IsValidInteger(idText) Then
    EndWithMessage "400 Bad Request", "Invalid request", "The request is not valid."
End If
patientId = CLng(idText)

If IsPostRequest() Then
    ValidateCsrfToken
    ' read Request.Form, validate length/format, call the data function
    ' on success: RedirectTo a fixed URL (POST-redirect-GET)
    ' on code 1: EndWithMessage "404 Not Found", ... (same text as a missing record)
    ' on code 2: errorMessage = "..." and show the form again
End If
%>
<!--#include file="includes/views/<page>_view.asp"-->
<% CloseConnection %>
```

Rules: `RequireLogin` first; IDs through `IsValidInteger` before `CLng`; user ID only from
`CurrentUserId()`; dates through `ParseIsoDate`; sort/filter values through a whitelist
(`IsInList`); redirects only to fixed URLs, never to a request value; no SQL, no long HTML.

## 4. View - `web/includes/views/<page>_view.asp`

```asp
<%
' views/<page>_view.asp - Variables: <list>
WriteLayoutTop "<Title>", "patients"
%>
<div class="page-header"><div>
  <h1 class="page-header__title"><Title></h1>
</div></div>
<section class="card">
  <form method="post" action="/<page>.asp?id=<%= Html(patientId) %>" class="form">
    <%= CsrfField() %>
    ...
  </form>
</section>
<% WriteLayoutBottom %>
```

- Every variable through `Html()` (or `HtmlMultiline()` for text with line breaks),
  also numbers and IDs. Attributes always in double quotes.
- Only reuse classes from `web/assets/css/app.css` (card, field, input, btn, alert,
  table, badge, empty-state...). No `style=`, `<style>` or `<script>`: the CSP blocks them.
- Every POST form contains `<%= CsrfField() %>`.

## 5. Verify

- The PostToolUse hook runs `tests/asp-syntax-check.ps1` after each edit; fix any error it reports.
- Add checks for the new page to `tests/e2e-security.ps1` (happy path, another doctor's
  ID -> 404 with the same body, invalid ID -> 400, POST without CSRF token -> error.asp,
  XSS payload stored and shown encoded), then run it (see the `run-local` skill).
- Tell the user how to test it manually in the browser (CLAUDE.md requires it).
