<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' login.asp - Sign in (controller). The only page without
' RequireLogin(). Session-fixation handling: see core/auth.asp.
' Rate limits and lockouts (per IP, per IP + username, per account) and
' the audit of every attempt live in app.usp_User_Login. Every
' credential failure shows the same message; too many failures from one
' IP get 429 (F-04).
' =====================================================================
Const GENERIC_LOGIN_ERROR = "Invalid username or password."

Dim errorMessage, infoMessage, usernameValue
errorMessage = ""
infoMessage = ""
usernameValue = ""

If IsLoggedIn() Then RedirectTo HOME_PAGE_URL

If IsPostRequest() Then
    HandleLoginPost
ElseIf CompleteLoginFromTicket() = "expired" Then
    infoMessage = "Your sign-in expired. Please try again."
ElseIf Request.QueryString("signedout") = "1" Then
    infoMessage = "You have been signed out."
ElseIf Request.QueryString("ended") = "1" Then
    infoMessage = "Your session has ended. Please sign in again."
End If

Sub HandleLoginPost()
    Dim username, password, resultCode, userId, fullName, role

    ValidateCsrfToken

    username = Trim(Request.Form("username") & "")
    password = Request.Form("password") & ""
    usernameValue = username

    If Len(username) = 0 Or Len(username) > USER_NAME_MAX_LENGTH _
       Or Len(password) = 0 Or Len(password) > USER_PASSWORD_MAX_LENGTH Then
        errorMessage = GENERIC_LOGIN_ERROR
        Exit Sub
    End If

    resultCode = Users_Login(username, password, ClientIpAddress(), userId, fullName, role)
    password = ""

    If resultCode = USER_LOGIN_RATE_LIMITED Then
        Response.AddHeader "Retry-After", "60"
        EndWithMessage "429 Too Many Requests", "Too many attempts", _
            "Too many failed sign-in attempts from your network. Wait a minute and try again."
    ElseIf resultCode = USER_LOGIN_OK And IsValidInteger(userId) Then
        BeginAuthenticatedSession CLng(userId), fullName, role   ' redirects
    Else
        errorMessage = GENERIC_LOGIN_ERROR
    End If
End Sub
%>
<!--#include file="includes/views/login_view.asp"-->
<% CloseConnection %>
