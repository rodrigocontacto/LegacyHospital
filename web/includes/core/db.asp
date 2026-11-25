<%
' =====================================================================
' core/db.asp - Database access (ADO).
'
' Every query is a stored procedure in schema app, called through
' CreateSpCommand with typed parameters. No SQL text is built here.
' Only files in includes/data/ call these functions.
'
' The connection string lives in <project root>\config\hospital.udl,
' outside the web root. The app connects as hospital_web, which can
' only EXECUTE stored procedures in schema app.
' =====================================================================

' ---- ADO constants used by the app (subset of adovbs.inc) -----------
Const adCmdStoredProc = 4
Const adExecuteNoRecords = 128
Const adParamInput = 1
Const adParamOutput = 2
Const adParamReturnValue = 4
Const adInteger = 3
Const adBoolean = 11
Const adDBDate = 133
Const adDBTimeStamp = 135
Const adVarChar = 200
Const adVarWChar = 202
Const adStateOpen = 1

Const DB_UDL_RELATIVE_PATH = "config\hospital.udl"
Const DB_COMMAND_TIMEOUT = 30

' One connection per request, opened on first use.
Dim g_DbConn
Set g_DbConn = Nothing

' Full path of the .udl file: parent folder of the web root + config.
Function GetUdlPath()
    Dim fso
    Set fso = Server.CreateObject("Scripting.FileSystemObject")
    GetUdlPath = fso.BuildPath(fso.GetParentFolderName(Server.MapPath("/")), DB_UDL_RELATIVE_PATH)
    Set fso = Nothing
End Function

' Opens a new connection. Never raises: returns Nothing on failure and
' puts the technical detail in errorDetail.
Function TryOpenConnection(ByRef errorDetail)
    Dim conn
    errorDetail = ""
    On Error Resume Next
    Set conn = Server.CreateObject("ADODB.Connection")
    conn.Open "File Name=" & GetUdlPath() & ";"
    If Err.Number <> 0 Then
        errorDetail = "Connection failed: " & Err.Number & " " & Err.Description
        Err.Clear
        Set conn = Nothing
    End If
    On Error GoTo 0
    Set TryOpenConnection = conn
End Function

' Returns the request's open connection. On failure: log + error page.
Function GetConnection()
    Dim errorDetail
    If g_DbConn Is Nothing Then
        Set g_DbConn = TryOpenConnection(errorDetail)
        If g_DbConn Is Nothing Then HandleFatalError errorDetail
    End If
    Set GetConnection = g_DbConn
End Function

' Call at the end of every page (safe to call more than once).
Sub CloseConnection()
    On Error Resume Next
    If Not (g_DbConn Is Nothing) Then
        If g_DbConn.State = adStateOpen Then g_DbConn.Close
    End If
    Set g_DbConn = Nothing
    Err.Clear
    On Error GoTo 0
End Sub

' Only stored procedures in schema app can be called from the web.
Function IsAllowedProcName(ByVal procName)
    Dim re
    Set re = New RegExp
    re.Pattern = "^app\.usp_[A-Za-z]+(_[A-Za-z]+)*$"
    re.IgnoreCase = False
    IsAllowedProcName = re.Test(CStr(procName & ""))
    Set re = Nothing
End Function

' Returns an ADODB.Command ready to run a stored procedure.
' The first parameter is always @RETURN_VALUE (read it with
' GetReturnValue). Parameters bind BY POSITION: append them in the same
' order as the procedure declares them.
Function CreateSpCommand(ByVal procName)
    Dim cmd
    If Not IsAllowedProcName(procName) Then
        HandleFatalError "CreateSpCommand rejected procedure name: " & procName
    End If
    Set cmd = Server.CreateObject("ADODB.Command")
    Set cmd.ActiveConnection = GetConnection()
    cmd.CommandType = adCmdStoredProc
    cmd.CommandText = procName
    cmd.CommandTimeout = DB_COMMAND_TIMEOUT
    cmd.Parameters.Append cmd.CreateParameter("@RETURN_VALUE", adInteger, adParamReturnValue)
    Set CreateSpCommand = cmd
End Function

Sub AddInputParam(ByVal cmd, ByVal name, ByVal adoType, ByVal size, ByVal value)
    cmd.Parameters.Append cmd.CreateParameter(name, adoType, adParamInput, size, value)
End Sub

Sub AddOutputParam(ByVal cmd, ByVal name, ByVal adoType, ByVal size)
    cmd.Parameters.Append cmd.CreateParameter(name, adoType, adParamOutput, size)
End Sub

Function GetReturnValue(ByVal cmd)
    GetReturnValue = cmd.Parameters("@RETURN_VALUE").Value
End Function

Function GetOutputValue(ByVal cmd, ByVal name)
    GetOutputValue = cmd.Parameters(name).Value
End Function

' Runs a procedure that returns rows. Prefer ReadAllRows.
Function ExecuteReader(ByVal cmd)
    Dim rs, errorDetail
    On Error Resume Next
    Set rs = cmd.Execute()
    If Err.Number <> 0 Then
        errorDetail = "Execute " & cmd.CommandText & " failed: " & Err.Number & " " & Err.Description
        Err.Clear
        On Error GoTo 0
        HandleFatalError errorDetail
    End If
    On Error GoTo 0
    Set ExecuteReader = rs
End Function

' Runs a procedure and returns all rows as a GetRows() array
' (columns x rows), or Empty when there are no rows. The recordset is
' closed before returning, so the return value can be read afterwards.
' A procedure that RETURNs before its SELECT gives a closed recordset.
Function ReadAllRows(ByVal cmd)
    Dim rs
    ReadAllRows = Empty
    Set rs = ExecuteReader(cmd)
    If rs.State = adStateOpen Then
        If Not rs.EOF Then ReadAllRows = rs.GetRows()
        rs.Close
    End If
    Set rs = Nothing
End Function

' Number of rows in a ReadAllRows() result.
Function RowCount(ByVal rows)
    RowCount = 0
    If IsArray(rows) Then RowCount = UBound(rows, 2) + 1
End Function

' Runs a procedure that returns no rows.
Sub ExecuteNonQuery(ByVal cmd)
    Dim errorDetail
    On Error Resume Next
    cmd.Execute , , adExecuteNoRecords
    If Err.Number <> 0 Then
        errorDetail = "Execute " & cmd.CommandText & " failed: " & Err.Number & " " & Err.Description
        Err.Clear
        On Error GoTo 0
        HandleFatalError errorDetail
    End If
    On Error GoTo 0
End Sub
%>
