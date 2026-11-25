<%
' =====================================================================
' includes/app.asp - The shared include every page uses first.
' A page then includes only its own view (includes/views/*_view.asp).
'
' Layers (a page is a controller; it never builds SQL or long HTML):
'   core/   infrastructure: database, errors, HTTP, encoding,
'           validation, CSRF, authentication
'   data/   one file per entity, one function per stored procedure
'   views/  layout, components and one view per page
'
' Rules:
'   - Stored procedures are only called from data/ (CreateSpCommand).
'   - Views only print variables through Html() / HtmlMultiline().
'   - Constants are prefixed by file (PATIENT_COL_*, NOTE_COL_*, ...):
'     VBScript has no namespaces and a repeated name breaks every page.
'
' The whole includes/ folder is blocked for HTTP (web.config
' hiddenSegments).
' =====================================================================
%>
<!--#include file="core/db.asp"-->
<!--#include file="core/errors.asp"-->
<!--#include file="core/http.asp"-->
<!--#include file="core/encoding.asp"-->
<!--#include file="core/validation.asp"-->
<!--#include file="core/csrf.asp"-->
<!--#include file="core/auth.asp"-->
<!--#include file="data/tokens.asp"-->
<!--#include file="data/users.asp"-->
<!--#include file="data/patients.asp"-->
<!--#include file="data/notes.asp"-->
<!--#include file="data/appointments.asp"-->
<!--#include file="views/components.asp"-->
<!--#include file="views/layout.asp"-->
<%
Response.CodePage = 65001
Response.Charset = "utf-8"
SendSecurityHeaders
%>
