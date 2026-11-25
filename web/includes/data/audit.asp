<%
' =====================================================================
' data/audit.asp - Security events (dbo.SecurityAudit, F-06).
' Sign-in attempts are audited inside app.usp_User_Login; everything
' else goes through Audit_Add. Pages call RecordSecurityEvent
' (core/auth.asp), which fills in the user and the IP.
' =====================================================================

' Event types and outcomes accepted by app.usp_SecurityAudit_Add.
Const AUDIT_EVENT_LOGOUT = "Logout"
Const AUDIT_EVENT_CSRF = "CsrfCheck"
Const AUDIT_EVENT_PATIENT_VIEW = "PatientView"
Const AUDIT_EVENT_NOTE_ADD = "NoteAdd"
Const AUDIT_EVENT_SESSION = "Session"

Const AUDIT_OUTCOME_SUCCESS = "Success"
Const AUDIT_OUTCOME_FAILURE = "Failure"
Const AUDIT_OUTCOME_DENIED = "Denied"
Const AUDIT_OUTCOME_BLOCKED = "Blocked"

' userId and resourceId may be Null. Returns the procedure's code
' (0 = written, 2 = unknown event type or outcome).
Function Audit_Add(ByVal userId, ByVal ipAddress, ByVal eventType, ByVal outcome, ByVal resourceId, ByVal detail)
    Dim cmd
    ' app.usp_SecurityAudit_Add @UserId, @IpAddress, @EventType, @Outcome, @ResourceId, @Detail
    Set cmd = CreateSpCommand("app.usp_SecurityAudit_Add")
    AddInputParam cmd, "@UserId", adInteger, 0, userId
    AddInputParam cmd, "@IpAddress", adVarChar, 45, ipAddress
    AddInputParam cmd, "@EventType", adVarChar, 20, eventType
    AddInputParam cmd, "@Outcome", adVarChar, 10, outcome
    AddInputParam cmd, "@ResourceId", adInteger, 0, resourceId
    AddInputParam cmd, "@Detail", adVarChar, 50, detail
    ExecuteNonQuery cmd
    Audit_Add = GetReturnValue(cmd)
    Set cmd = Nothing
End Function
%>
