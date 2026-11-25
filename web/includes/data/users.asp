<%
' =====================================================================
' data/users.asp - Users (doctors).
' =====================================================================

Const USER_NAME_MAX_LENGTH = 50
Const USER_PASSWORD_MAX_LENGTH = 128

' Returns the procedure's code: 0 = valid credentials (userId, fullName
' and role are filled), 1 = any failure (unknown user, wrong password,
' locked, inactive). The lockout is enforced inside the procedure.
Function Users_Login(ByVal username, ByVal password, ByRef userId, ByRef fullName, ByRef role)
    Dim cmd
    ' app.usp_User_Login @Username, @Password, @UserId OUT, @FullName OUT, @Role OUT
    Set cmd = CreateSpCommand("app.usp_User_Login")
    AddInputParam cmd, "@Username", adVarWChar, USER_NAME_MAX_LENGTH, username
    AddInputParam cmd, "@Password", adVarWChar, USER_PASSWORD_MAX_LENGTH, password
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
%>
