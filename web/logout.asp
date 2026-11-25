<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' logout.asp - Sign out (controller, no view).
' POST only, with CSRF token: a GET logout would let any site sign the
' user out with an <img src="/logout.asp">. The sign-out button lives in
' views/layout.asp.
' =====================================================================
RequireLogin

If Not IsPostRequest() Then RedirectTo HOME_PAGE_URL

ValidateCsrfToken
SignOut
RedirectTo LOGIN_PAGE_URL & "?signedout=1"
%>
