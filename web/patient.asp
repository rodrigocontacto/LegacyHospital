<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' patient.asp?id=N - Patient record and clinical notes (controller).
'
' IDOR protection:
'   - id must be a positive integer (IsValidInteger), else 400.
'   - The data layer filters by PatientId AND CurrentUserId() (never a
'     request value). Another doctor's patient returns no rows, exactly
'     like a patient that does not exist.
'   - Both cases answer the same 404 page.
' Audit (F-06): every view and every denied ID is written to
' SecurityAudit (who viewed which patient; IDOR probing shows up as a
' run of Denied rows).
' =====================================================================
RequireLogin

Dim idText, patientId, patient, notes, noteCount, noteAdded, i

idText = Request.QueryString("id") & ""
If Not IsValidInteger(idText) Then
    EndWithMessage "400 Bad Request", "Invalid request", "The request is not valid."
End If
patientId = CLng(idText)

patient = Patients_Get(CurrentUserId(), patientId)
If Not IsArray(patient) Then
    RecordSecurityEvent AUDIT_EVENT_PATIENT_VIEW, AUDIT_OUTCOME_DENIED, patientId, "NotFoundOrNotAssigned"
    EndWithMessage "404 Not Found", "Patient not found", "The patient you requested was not found."
End If
RecordSecurityEvent AUDIT_EVENT_PATIENT_VIEW, AUDIT_OUTCOME_SUCCESS, patientId, Null

notes = Notes_ListByPatient(CurrentUserId(), patientId)
noteCount = RowCount(notes)

' Set by add_note.asp after saving (POST-redirect-GET). Fixed message only.
noteAdded = (Request.QueryString("added") = "1")
%>
<!--#include file="includes/views/patient_view.asp"-->
<% CloseConnection %>
