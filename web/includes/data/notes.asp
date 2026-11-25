<%
' =====================================================================
' data/notes.asp - Clinical notes.
' =====================================================================

' Column positions in the rows of Notes_ListByPatient.
Const NOTE_COL_ID = 0
Const NOTE_COL_TEXT = 1
Const NOTE_COL_CREATED_AT = 2
Const NOTE_COL_AUTHOR = 3

' Notes of one patient, newest first, only if assigned to userId.
Function Notes_ListByPatient(ByVal userId, ByVal patientId)
    Dim cmd
    ' app.usp_PatientNote_List @UserId, @PatientId
    Set cmd = CreateSpCommand("app.usp_PatientNote_List")
    AddInputParam cmd, "@UserId", adInteger, 0, userId
    AddInputParam cmd, "@PatientId", adInteger, 0, patientId
    Notes_ListByPatient = ReadAllRows(cmd)
    Set cmd = Nothing
End Function
%>
