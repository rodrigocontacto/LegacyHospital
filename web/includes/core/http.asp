<%
' =====================================================================
' core/http.asp - Response headers, cookies, redirects and short
' status pages.
' =====================================================================

' Sent on every page (called at the end of includes/app.asp).
Sub SendSecurityHeaders()
    ' No framing: prevents clickjacking.
    Response.AddHeader "X-Frame-Options", "DENY"
    ' The browser must trust Content-Type, never guess it.
    Response.AddHeader "X-Content-Type-Options", "nosniff"
    ' Only our own scripts, styles and images. No inline script or style.
    Response.AddHeader "Content-Security-Policy", _
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; " & _
        "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'"
    ' Patient IDs in URLs must not leak to other sites.
    Response.AddHeader "Referrer-Policy", "no-referrer"
    ' Patient data must not stay in the browser or proxy cache.
    Response.CacheControl = "no-store"
    ' F-03: once the browser has seen the site over HTTPS, it never uses
    ' HTTP for it again (web.config redirects plain HTTP to HTTPS).
    ' Browsers ignore this header over HTTP, so it is only sent on HTTPS.
    ' HSTS applies to the host on every port: on localhost a long max-age
    ' would force HTTPS on every other local project, so it stays short.
    If IsHttps() Then
        If LCase(Request.ServerVariables("SERVER_NAME") & "") = "localhost" Then
            Response.AddHeader "Strict-Transport-Security", "max-age=300"
        Else
            Response.AddHeader "Strict-Transport-Security", "max-age=31536000"
        End If
    End If
End Sub

Function IsHttps()
    IsHttps = (LCase(Request.ServerVariables("HTTPS") & "") = "on")
End Function

' The client's IP as seen by IIS (REMOTE_ADDR). X-Forwarded-For is never
' used: any client can send it. Behind a reverse proxy, configure IIS
' (or the proxy) so that REMOTE_ADDR is the real client.
Function ClientIpAddress()
    ClientIpAddress = Left(Request.ServerVariables("REMOTE_ADDR") & "", 45)
End Function

' Trimmed query string value, or defaultValue when the parameter is
' absent. The caller still has to validate the result.
Function QueryValueOrDefault(ByVal name, ByVal defaultValue)
    If Request.QueryString(name).Count > 0 Then
        QueryValueOrDefault = Trim(Request.QueryString(name) & "")
    Else
        QueryValueOrDefault = defaultValue
    End If
End Function

Function IsPostRequest()
    IsPostRequest = (Request.ServerVariables("REQUEST_METHOD") = "POST")
End Function

' Closes the connection and redirects. Ends the request.
' Only call with fixed URLs from the code, never with request values.
Sub RedirectTo(ByVal url)
    CloseConnection
    Response.Redirect url
End Sub

' Sends a short generic page with the given status and ends the request.
' Example: EndWithMessage "404 Not Found", "Patient not found", "..."
Sub EndWithMessage(ByVal statusLine, ByVal title, ByVal message)
    Response.Clear
    Response.Status = statusLine
    WriteMessagePage title, message
    CloseConnection
    Response.End
End Sub

' ---- Cookies ----------------------------------------------------------
' Response.Cookies cannot set HttpOnly or SameSite, so cookies are
' written as raw Set-Cookie headers. Secure is added under HTTPS.
Function CookieAttributes()
    CookieAttributes = "; Path=/; HttpOnly; SameSite=Strict"
    If IsHttps() Then CookieAttributes = CookieAttributes & "; Secure"
End Function

' Session cookie (no Expires). Only call with values we generated.
Sub SetCookie(ByVal name, ByVal value)
    Response.AddHeader "Set-Cookie", name & "=" & value & CookieAttributes()
End Sub

Sub DeleteCookie(ByVal name)
    Response.AddHeader "Set-Cookie", name & "=; Expires=Thu, 01 Jan 1970 00:00:00 GMT" & CookieAttributes()
End Sub

' Tells the browser to drop the ASP session cookie (its name is
' ASPSESSIONID + 8 letters), so the next request gets a new ID.
' ASP hides that cookie from Request.Cookies, so the raw Cookie header
' is parsed. Only names matching the exact pattern are written back.
Sub ExpireAspSessionCookies()
    Dim re, matches, match
    Set re = New RegExp
    re.Pattern = "(?:^|;\s*)(ASPSESSIONID[A-Z]{8})="
    re.Global = True
    re.IgnoreCase = False
    Set matches = re.Execute(Request.ServerVariables("HTTP_COOKIE") & "")
    For Each match In matches
        DeleteCookie match.SubMatches(0)
    Next
    Set re = Nothing
End Sub
%>
