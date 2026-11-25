<%
' =====================================================================
' core/auth.asp - Session-based authentication.
'
' Every page except login.asp and error.asp calls RequireLogin() first.
'
' Session fixation: Classic ASP cannot regenerate the session ID, so a
' successful login takes two requests:
'   1. BeginAuthenticatedSession (POST, credentials OK): store a
'      one-time ticket (60 s) in Application, send it in an HttpOnly
'      cookie, Session.Abandon, expire the ASPSESSIONID cookie,
'      redirect to login.asp.
'   2. CompleteLoginFromTicket (GET without the old session cookie):
'      ASP starts a NEW session with a new ID. The ticket is consumed
'      and the user data is stored in the new session.
' The ticket store lives in one worker process: keep the app pool at a
' single worker (default).
' =====================================================================

Const LOGIN_PAGE_URL = "/login.asp"
Const HOME_PAGE_URL = "/search.asp"
Const LOGIN_TICKET_COOKIE = "LoginTicket"
Const LOGIN_TICKET_PREFIX = "LoginTicket:"
Const LOGIN_TICKET_SECONDS = 60

' F-12: besides the 20-minute idle timeout (global.asa), a session ends
' AUTH_SESSION_MAX_MINUTES after sign-in even if it is used all the
' time, and the user's IsActive flag is re-read from the database every
' AUTH_ACTIVE_CHECK_MINUTES: a deactivated doctor is out within minutes.
Const AUTH_SESSION_MAX_MINUTES = 480
Const AUTH_ACTIVE_CHECK_MINUTES = 5
Const AUTH_SESSION_ENDED_URL = "/login.asp?ended=1"

Function IsLoggedIn()
    IsLoggedIn = IsValidInteger(Session("UserId"))
End Function

' First call on every protected page. Ends the request if not logged in
' or if the session has ended (absolute limit, user deactivated).
Sub RequireLogin()
    Dim endReason
    If Not IsLoggedIn() Then
        Response.Clear
        RedirectTo LOGIN_PAGE_URL
    End If

    endReason = SessionEndReason()
    If Len(endReason) > 0 Then
        RecordSecurityEvent AUDIT_EVENT_SESSION, AUDIT_OUTCOME_BLOCKED, Null, endReason
        SignOut
        Response.Clear
        RedirectTo AUTH_SESSION_ENDED_URL
    End If
End Sub

' "" while the session is valid; otherwise the reason it ended.
' Session("LoginAt") is set at sign-in; a session without it (created
' before this check existed) is ended too.
Function SessionEndReason()
    Dim loginAt, checkedAt
    SessionEndReason = ""
    loginAt = Session("LoginAt")
    If VarType(loginAt) <> vbDate Then
        SessionEndReason = "MissingLoginTime"
    ElseIf DateDiff("n", loginAt, Now()) >= AUTH_SESSION_MAX_MINUTES Then
        SessionEndReason = "AbsoluteTimeout"
    Else
        checkedAt = Session("ActiveCheckedAt")
        If VarType(checkedAt) <> vbDate Then
            checkedAt = DateAdd("n", -AUTH_ACTIVE_CHECK_MINUTES, Now())
        End If
        If DateDiff("n", checkedAt, Now()) >= AUTH_ACTIVE_CHECK_MINUTES Then
            If Users_IsActive(CurrentUserId()) Then
                Session("ActiveCheckedAt") = Now()
            Else
                SessionEndReason = "UserInactive"
            End If
        End If
    End If
End Function

' Writes a security event for the current request (F-06): the signed-in
' user (if any) and the client IP are added here. resourceId may be Null.
Sub RecordSecurityEvent(ByVal eventType, ByVal outcome, ByVal resourceId, ByVal detail)
    Dim userId
    userId = Null
    If IsLoggedIn() Then userId = CurrentUserId()
    If Audit_Add(userId, ClientIpAddress(), eventType, outcome, resourceId, detail) <> 0 Then
        HandleFatalError "Audit_Add rejected event " & eventType & "/" & outcome
    End If
End Sub

' The logged-in doctor. Only call after RequireLogin().
Function CurrentUserId()
    CurrentUserId = CLng(Session("UserId"))
End Function

Function CurrentUserName()
    CurrentUserName = Session("FullName") & ""
End Function

Function CurrentUserRole()
    CurrentUserRole = Session("Role") & ""
End Function

' ---- Login step 1 (ends the request with a redirect) ------------------
Sub BeginAuthenticatedSession(ByVal userId, ByVal fullName, ByVal role)
    Dim ticket
    ticket = Tokens_Generate()
    StoreLoginTicket ticket, userId, fullName, role

    Session.Contents.RemoveAll
    Session.Abandon
    ExpireAspSessionCookies
    SetCookie LOGIN_TICKET_COOKIE, ticket
    RedirectTo LOGIN_PAGE_URL
End Sub

' ---- Login step 2 -----------------------------------------------------
' Returns "" when there is no ticket cookie and "expired" when the
' ticket is invalid, used or older than 60 s. On success it stores the
' user in the new session and redirects to the home page.
Function CompleteLoginFromTicket()
    Dim ticket, data
    CompleteLoginFromTicket = ""
    ticket = Request.Cookies(LOGIN_TICKET_COOKIE) & ""
    If Len(ticket) = 0 Then Exit Function

    DeleteCookie LOGIN_TICKET_COOKIE
    CompleteLoginFromTicket = "expired"
    If Not IsHexToken(ticket) Then Exit Function
    data = TakeLoginTicket(ticket)
    If Not IsArray(data) Then Exit Function

    Session("UserId") = CLng(data(0))
    Session("FullName") = data(1)
    Session("Role") = data(2)
    Session("LoginAt") = Now()
    Session("ActiveCheckedAt") = Now()
    RedirectTo HOME_PAGE_URL
End Function

' ---- Logout -----------------------------------------------------------
Sub SignOut()
    Session.Contents.RemoveAll
    Session.Abandon
    ExpireAspSessionCookies
End Sub

' ---- One-time login tickets (Application) -----------------------------
Sub StoreLoginTicket(ByVal ticket, ByVal userId, ByVal fullName, ByVal role)
    Application.Lock
    PurgeExpiredLoginTickets
    Application(LOGIN_TICKET_PREFIX & ticket) = _
        Array(userId, fullName, role, DateAdd("s", LOGIN_TICKET_SECONDS, Now()))
    Application.Unlock
End Sub

' Returns the ticket data and deletes it (one use only).
' Returns Empty if it does not exist or has expired.
Function TakeLoginTicket(ByVal ticket)
    Dim key, data
    TakeLoginTicket = Empty
    key = LOGIN_TICKET_PREFIX & ticket

    Application.Lock
    data = Application(key)
    Application.Contents.Remove key
    Application.Unlock

    If IsArray(data) Then
        If data(3) >= Now() Then TakeLoginTicket = data
    End If
End Function

' Call only while holding Application.Lock.
Sub PurgeExpiredLoginTickets()
    Dim key, data, expiredKeys, i
    expiredKeys = ""
    For Each key In Application.Contents
        If Left(key, Len(LOGIN_TICKET_PREFIX)) = LOGIN_TICKET_PREFIX Then
            data = Application(key)
            If IsArray(data) Then
                If data(3) < Now() Then expiredKeys = expiredKeys & key & vbTab
            End If
        End If
    Next
    If Len(expiredKeys) > 0 Then
        expiredKeys = Split(Left(expiredKeys, Len(expiredKeys) - 1), vbTab)
        For i = 0 To UBound(expiredKeys)
            Application.Contents.Remove expiredKeys(i)
        Next
    End If
End Sub
%>
