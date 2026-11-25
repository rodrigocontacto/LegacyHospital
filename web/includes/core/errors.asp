<%
' =====================================================================
' core/errors.asp - Error logging and the generic error page.
' Users never see technical details: they are logged, the user gets a
' generic message.
' =====================================================================

Const ERROR_PAGE_URL = "/error.asp"

Function CurrentPageName()
    CurrentPageName = Request.ServerVariables("SCRIPT_NAME") & ""
End Function

' Writes the error to dbo.AppErrorLog through app.usp_Error_Log.
' Never raises. If the database is unreachable, falls back to the IIS
' log. Does not use CreateSpCommand on purpose: a failure here must not
' call HandleFatalError again.
Sub LogError(ByVal pageName, ByVal detail)
    Dim conn, cmd, userId, logged, openError
    logged = False
    On Error Resume Next
    pageName = Left(CStr(pageName & ""), 200)
    detail = Left(CStr(detail & ""), 4000)
    userId = Null
    If VarType(Session("UserId")) = vbLong Then userId = Session("UserId")

    If Not (g_DbConn Is Nothing) Then
        Set conn = g_DbConn
    Else
        Set conn = TryOpenConnection(openError)
    End If

    If Not (conn Is Nothing) Then
        Err.Clear
        Set cmd = Server.CreateObject("ADODB.Command")
        Set cmd.ActiveConnection = conn
        cmd.CommandType = adCmdStoredProc
        cmd.CommandText = "app.usp_Error_Log"
        cmd.CommandTimeout = DB_COMMAND_TIMEOUT
        cmd.Parameters.Append cmd.CreateParameter("@PageName", adVarWChar, adParamInput, 200, pageName)
        cmd.Parameters.Append cmd.CreateParameter("@ErrorDetail", adVarWChar, adParamInput, 4000, detail)
        cmd.Parameters.Append cmd.CreateParameter("@UserId", adInteger, adParamInput, 0, userId)
        cmd.Execute , , adExecuteNoRecords
        logged = (Err.Number = 0)
        Set cmd = Nothing
        If Not (conn Is g_DbConn) Then conn.Close
        Set conn = Nothing
    End If

    If Not logged Then Response.AppendToLog SanitizeForIisLog(pageName & " " & detail)
    Err.Clear
    On Error GoTo 0
End Sub

' Response.AppendToLog accepts at most 80 characters and no commas.
Function SanitizeForIisLog(ByVal text)
    Dim re
    Set re = New RegExp
    re.Pattern = "[^A-Za-z0-9._:/\-]"
    re.Global = True
    SanitizeForIisLog = Left(re.Replace(CStr(text & ""), "_"), 80)
    Set re = Nothing
End Function

' Logs the detail, discards any output and sends the user to the
' generic error page. Ends the request.
Sub HandleFatalError(ByVal detail)
    LogError CurrentPageName(), detail
    CloseConnection
    Response.Clear
    Response.Redirect ERROR_PAGE_URL
End Sub
%>
