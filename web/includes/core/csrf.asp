<%
' =====================================================================
' core/csrf.asp - Anti-CSRF tokens (synchronizer token per session).
' Every POST form includes CsrfField(); every POST handler calls
' ValidateCsrfToken first.
' =====================================================================

Const CSRF_FIELD_NAME = "csrf_token"
Const CSRF_SESSION_KEY = "CsrfToken"
Const CSRF_TOKEN_LENGTH = 64   ' 32 random bytes as hex

' One token per session, created on first use from SQL Server
' CRYPT_GEN_RANDOM (never Rnd()).
Function GenerateCsrfToken()
    If Len(Session(CSRF_SESSION_KEY) & "") <> CSRF_TOKEN_LENGTH Then
        Session(CSRF_SESSION_KEY) = Tokens_Generate()
    End If
    GenerateCsrfToken = Session(CSRF_SESSION_KEY)
End Function

' Hidden field to put inside every POST form.
Function CsrfField()
    CsrfField = "<input type=""hidden"" name=""" & CSRF_FIELD_NAME & _
                """ value=""" & Html(GenerateCsrfToken()) & """>"
End Function

' Ends the request if the method is not POST or the token does not match.
' F-14: a failure is a security event, not a technical error. It goes to
' dbo.SecurityAudit (capped per IP, and counted by the login rate limit),
' not to AppErrorLog, so anonymous POSTs without a token cannot flood the
' error log. The user gets the same generic error page as before.
Sub ValidateCsrfToken()
    Dim expected, received
    expected = Session(CSRF_SESSION_KEY) & ""
    received = Request.Form(CSRF_FIELD_NAME) & ""
    If Not IsPostRequest() _
       Or Len(expected) <> CSRF_TOKEN_LENGTH _
       Or Not ConstantTimeEquals(expected, received) Then
        RecordSecurityEvent AUDIT_EVENT_CSRF, AUDIT_OUTCOME_FAILURE, Null, Left(CurrentPageName(), 50)
        CloseConnection
        Response.Clear
        Response.Redirect ERROR_PAGE_URL
    End If
End Sub

' Compares every character, so the time taken does not reveal how many
' leading characters matched.
Function ConstantTimeEquals(ByVal a, ByVal b)
    Dim i, diff
    If Len(a) <> Len(b) Then
        ConstantTimeEquals = False
        Exit Function
    End If
    diff = 0
    For i = 1 To Len(a)
        diff = diff Or (AscW(Mid(a, i, 1)) Xor AscW(Mid(b, i, 1)))
    Next
    ConstantTimeEquals = (diff = 0)
End Function
%>
