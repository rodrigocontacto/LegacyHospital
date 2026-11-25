<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' search.asp - Search the logged-in doctor's patients (controller).
'
' F-11: the search term is patient data (a name, a record number), so it
' never travels in the URL, where it would be stored in the IIS log,
' browser history and proxies:
'   POST: CSRF check, validation, term saved in the session, redirect
'         back to /search.asp (POST-redirect-GET: Back and reload do not
'         ask to resend the form).
'   GET:  shows the results of the session's last search, if any.
' A "q" in the query string is ignored.
' =====================================================================
RequireLogin

Const SEARCH_SESSION_KEY = "PatientSearchTerm"

Dim searchTerm, hasSearched, errorMessage, results, resultCount, i
searchTerm = ""
hasSearched = False
errorMessage = ""
results = Empty
resultCount = 0

If IsPostRequest() Then
    ValidateCsrfToken
    searchTerm = Trim(Request.Form("q") & "")
    hasSearched = True
    If Len(searchTerm) > PATIENT_SEARCH_MAX_LENGTH Then
        errorMessage = "The search text can have at most 50 characters."
    Else
        Session(SEARCH_SESSION_KEY) = searchTerm
        RedirectTo "/search.asp"
    End If
ElseIf VarType(Session(SEARCH_SESSION_KEY)) = vbString Then
    hasSearched = True
    searchTerm = Session(SEARCH_SESSION_KEY)
    results = Patients_Search(CurrentUserId(), searchTerm)
    resultCount = RowCount(results)
End If
%>
<!--#include file="includes/views/search_view.asp"-->
<% CloseConnection %>
