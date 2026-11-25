<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' error.asp - Generic error page.
'
' Exception to the RequireLogin() rule (see CLAUDE.md): it shows a fixed
' message with no data and no actions, and it must work for anonymous
' users (an error in login.asp would otherwise cause a redirect loop).
' Technical details are logged, never shown. Uses the anonymous layout,
' which needs no database access.
' =====================================================================
LogLastAspError
WriteMessagePage "Something went wrong", "We could not complete your request. Please try again later."
CloseConnection

' When IIS runs this page as the custom handler for 500 errors,
' Server.GetLastError() holds the original error. When the user arrives
' through HandleFatalError (redirect), the error was already logged.
Sub LogLastAspError()
    Dim aspErr, detail
    On Error Resume Next
    Set aspErr = Server.GetLastError()
    If Not (aspErr Is Nothing) Then
        If aspErr.Number <> 0 Or Len(aspErr.ASPCode & "") > 0 Then
            detail = "ASP error " & Hex(aspErr.Number) & " " & aspErr.Category & " " & _
                     aspErr.ASPCode & " line " & aspErr.Line & ": " & _
                     aspErr.Description & " " & aspErr.ASPDescription
            LogError aspErr.File, detail
        End If
    End If
    Err.Clear
    On Error GoTo 0
End Sub
%>
