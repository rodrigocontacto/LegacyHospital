<%
' =====================================================================
' data/patients.asp - Patients. Every procedure filters by the doctor
' passed in userId (always CurrentUserId(), never a request value).
' =====================================================================

Const PATIENT_SEARCH_MAX_LENGTH = 50
Const PATIENT_SEARCH_MAX_RESULTS = 100   ' TOP (100) in the procedure

' Column positions in the rows of Patients_Search and Patients_Get.
Const PATIENT_COL_ID = 0
Const PATIENT_COL_RECORD_NUMBER = 1
Const PATIENT_COL_FIRST_NAME = 2
Const PATIENT_COL_LAST_NAME = 3
Const PATIENT_COL_DATE_OF_BIRTH = 4

' Prefix search on last name, first name or record number.
' Returns a GetRows() array or Empty.
Function Patients_Search(ByVal userId, ByVal term)
    Dim cmd
    ' app.usp_Patient_Search @UserId, @SearchTerm, @SortColumn, @SortDirection
    Set cmd = CreateSpCommand("app.usp_Patient_Search")
    AddInputParam cmd, "@UserId", adInteger, 0, userId
    AddInputParam cmd, "@SearchTerm", adVarWChar, PATIENT_SEARCH_MAX_LENGTH, term
    AddInputParam cmd, "@SortColumn", adVarChar, 30, "LastName"
    AddInputParam cmd, "@SortDirection", adVarChar, 4, "ASC"
    Patients_Search = ReadAllRows(cmd)
    Set cmd = Nothing
End Function

' One patient, only if assigned to userId. Empty for "does not exist"
' and for "not yours" alike.
Function Patients_Get(ByVal userId, ByVal patientId)
    Dim cmd
    ' app.usp_Patient_Get @UserId, @PatientId
    Set cmd = CreateSpCommand("app.usp_Patient_Get")
    AddInputParam cmd, "@UserId", adInteger, 0, userId
    AddInputParam cmd, "@PatientId", adInteger, 0, patientId
    Patients_Get = ReadAllRows(cmd)
    Set cmd = Nothing
End Function
%>
