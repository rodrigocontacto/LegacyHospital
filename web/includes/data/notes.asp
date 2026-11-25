<%
' =====================================================================
' data/notes.asp - Clinical notes.
' =====================================================================

Const NOTE_TEXT_MAX_LENGTH = 2000   ' PatientNotes.NoteText is NVARCHAR(2000)

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

' Adds a note written by userId. Returns the procedure's code:
' 0 = added, 1 = patient not found or not assigned to userId,
' 2 = empty or longer than 2000 characters.
' The ownership check and the INSERT are one statement in the procedure.
Function Notes_Add(ByVal userId, ByVal patientId, ByVal noteText)
    Dim cmd
    ' app.usp_PatientNote_Add @UserId, @PatientId, @NoteText, @NoteId OUT
    Set cmd = CreateSpCommand("app.usp_PatientNote_Add")
    AddInputParam cmd, "@UserId", adInteger, 0, userId
    AddInputParam cmd, "@PatientId", adInteger, 0, patientId
    AddInputParam cmd, "@NoteText", adVarWChar, 4000, noteText
    AddOutputParam cmd, "@NoteId", adInteger, 0
    ExecuteNonQuery cmd
    Notes_Add = GetReturnValue(cmd)
    Set cmd = Nothing
End Function
%>
