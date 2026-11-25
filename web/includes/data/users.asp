<%
' =====================================================================
' data/users.asp - Users (doctors).
' =====================================================================

Const USER_NAME_MAX_LENGTH = 50
Const USER_PASSWORD_MAX_LENGTH = 128

' Return codes of app.usp_User_Login.
Const USER_LOGIN_OK = 0
Const USER_LOGIN_FAILED = 1
Const USER_LOGIN_RATE_LIMITED = 3

' Returns the procedure's code: USER_LOGIN_OK (userId, fullName and role
' are filled), USER_LOGIN_FAILED (unknown user, wrong password, locked,
' inactive: all alike) or USER_LOGIN_RATE_LIMITED (too many failures
' from ipAddress). Limits, lockouts and the audit row are handled inside
' the procedure.
Function Users_Login(ByVal username, ByVal password, ByVal ipAddress, ByRef userId, ByRef fullName, ByRef role)
    Dim cmd
    ' app.usp_User_Login @Username, @Password, @IpAddress, @UserId OUT, @FullName OUT, @Role OUT
    Set cmd = CreateSpCommand("app.usp_User_Login")
    AddInputParam cmd, "@Username", adVarWChar, USER_NAME_MAX_LENGTH, username
    AddInputParam cmd, "@Password", adVarWChar, USER_PASSWORD_MAX_LENGTH, password
    AddInputParam cmd, "@IpAddress", adVarChar, 45, ipAddress
    AddOutputParam cmd, "@UserId", adInteger, 0
    AddOutputParam cmd, "@FullName", adVarWChar, 100
    AddOutputParam cmd, "@Role", adVarWChar, 20
    ExecuteNonQuery cmd

    Users_Login = GetReturnValue(cmd)
    userId = GetOutputValue(cmd, "@UserId")
    fullName = GetOutputValue(cmd, "@FullName")
    role = GetOutputValue(cmd, "@Role")
    Set cmd = Nothing
End Function

' True while the user exists and IsActive = 1 (F-12).
Function Users_IsActive(ByVal userId)
    Dim cmd
    ' app.usp_User_IsActive @UserId, @IsActive OUT
    Set cmd = CreateSpCommand("app.usp_User_IsActive")
    AddInputParam cmd, "@UserId", adInteger, 0, userId
    AddOutputParam cmd, "@IsActive", adBoolean, 0
    ExecuteNonQuery cmd
    Users_IsActive = (GetOutputValue(cmd, "@IsActive") = True)
    Set cmd = Nothing
End Function
%>
