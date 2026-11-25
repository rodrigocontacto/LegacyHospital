<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' add_note.asp?id=N - Add a clinical note to a patient (controller).
'
'   GET:  form.
'   POST: CSRF check, validation, Notes_Add, then redirect to the
'         patient record (POST-redirect-GET: reloading does not repeat it).
'
' IDOR: the patient is loaded with CurrentUserId() before showing or
' saving anything; another doctor's patient and a missing one get the
' same 404 as patient.asp. The procedure checks ownership again.
' The note is stored as plain text and encoded when it is displayed.
' Audit (F-06): denied IDs and saved notes go to SecurityAudit. The GET
' form is not a record view (it shows only the patient's name).
' =====================================================================
RequireLogin

Dim idText, patientId, patient, noteText, errorMessage, resultCode
noteText = ""
errorMessage = ""

idText = Request.QueryString("id") & ""
If Not IsValidInteger(idText) Then
    EndWithMessage "400 Bad Request", "Invalid request", "The request is not valid."
End If
patientId = CLng(idText)

patient = Patients_Get(CurrentUserId(), patientId)
If Not IsArray(patient) Then EndPatientNotFound

If IsPostRequest() Then
    ValidateCsrfToken
    noteText = NormalizeLineBreaks(Request.Form("note_text"))

    If IsBlank(noteText) Then
        errorMessage = "Write the note before saving."
    ElseIf Len(noteText) > NOTE_TEXT_MAX_LENGTH Then
        errorMessage = "The note can have at most 2000 characters."
    Else
        resultCode = Notes_Add(CurrentUserId(), patientId, noteText)
        Select Case resultCode
            Case 0
                RecordSecurityEvent AUDIT_EVENT_NOTE_ADD, AUDIT_OUTCOME_SUCCESS, patientId, Null
                ' Fixed path + an ID already validated as an integer.
                RedirectTo "/patient.asp?id=" & patientId & "&added=1"
            Case 1
                EndPatientNotFound
            Case Else
                errorMessage = "The note could not be saved. Check its length and try again."
        End Select
    End If
End If

' Same status and text as patient.asp, so the response does not reveal
' whether the patient exists.
Sub EndPatientNotFound()
    RecordSecurityEvent AUDIT_EVENT_NOTE_ADD, AUDIT_OUTCOME_DENIED, patientId, "NotFoundOrNotAssigned"
    EndWithMessage "404 Not Found", "Patient not found", "The patient you requested was not found."
End Sub
%>
<!--#include file="includes/views/add_note_view.asp"-->
<% CloseConnection %>
