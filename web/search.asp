<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' search.asp - Search the logged-in doctor's patients (controller).
' GET form: a search changes nothing, so no CSRF token is needed.
' =====================================================================
RequireLogin

Dim searchTerm, hasSearched, errorMessage, results, resultCount, i
searchTerm = ""
hasSearched = False
errorMessage = ""
results = Empty
resultCount = 0

If Request.QueryString("q").Count > 0 Then
    hasSearched = True
    searchTerm = Trim(Request.QueryString("q") & "")
    If Len(searchTerm) > PATIENT_SEARCH_MAX_LENGTH Then
        errorMessage = "The search text can have at most 50 characters."
    Else
        results = Patients_Search(CurrentUserId(), searchTerm)
        resultCount = RowCount(results)
    End If
End If
%>
<!--#include file="includes/views/search_view.asp"-->
<% CloseConnection %>
