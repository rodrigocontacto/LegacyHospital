<%
' =====================================================================
' data/tokens.asp - Random tokens from SQL Server CRYPT_GEN_RANDOM.
' =====================================================================

' 32 random bytes from app.usp_Token_Generate, as 64 hex characters.
Function Tokens_Generate()
    Dim cmd, token
    ' app.usp_Token_Generate @Token CHAR(64) OUTPUT
    Set cmd = CreateSpCommand("app.usp_Token_Generate")
    AddOutputParam cmd, "@Token", adVarChar, 64
    ExecuteNonQuery cmd
    token = GetOutputValue(cmd, "@Token") & ""
    Set cmd = Nothing

    If Not IsHexToken(token) Then HandleFatalError "usp_Token_Generate returned an invalid token"
    Tokens_Generate = token
End Function
%>
