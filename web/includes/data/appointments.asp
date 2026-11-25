<%
' =====================================================================
' data/appointments.asp - Appointments.
' =====================================================================

Const APPOINTMENT_REPORT_MAX_DAYS = 90
Const APPOINTMENT_REPORT_MAX_ROWS = 500       ' TOP (500) in the procedure
Const APPOINTMENT_REPORT_DEFAULT_SORT = "ScheduledAt"

' Column positions in the rows of Appointments_Report.
Const APPOINTMENT_COL_ID = 0
Const APPOINTMENT_COL_SCHEDULED_AT = 1
Const APPOINTMENT_COL_STATUS = 2
Const APPOINTMENT_COL_REASON = 3
Const APPOINTMENT_COL_PATIENT_ID = 4
Const APPOINTMENT_COL_RECORD_NUMBER = 5
Const APPOINTMENT_COL_LAST_NAME = 6
Const APPOINTMENT_COL_FIRST_NAME = 7

' Sort whitelist: the SAME values app.usp_Appointment_Report accepts.
Function Appointments_SortColumns()
    Appointments_SortColumns = Array("ScheduledAt", "LastName", "Status")
End Function

Function Appointments_IsAllowedSort(ByVal value)
    Appointments_IsAllowedSort = IsInList(value, Appointments_SortColumns())
End Function

Function Appointments_SortLabel(ByVal value)
    Select Case value
        Case "ScheduledAt": Appointments_SortLabel = "Date and time"
        Case "LastName":    Appointments_SortLabel = "Patient last name"
        Case "Status":      Appointments_SortLabel = "Status"
    End Select
End Function

' Number of rows of an Appointments_Report result with the given status.
Function Appointments_CountByStatus(ByVal rows, ByVal status)
    Dim r
    Appointments_CountByStatus = 0
    For r = 0 To RowCount(rows) - 1
        If rows(APPOINTMENT_COL_STATUS, r) = status Then
            Appointments_CountByStatus = Appointments_CountByStatus + 1
        End If
    Next
End Function

' Appointments of userId's patients between two dates (already
' validated by the caller). A non-zero return code is a bug: the caller
' validated everything, so it ends with the generic error page.
Function Appointments_Report(ByVal userId, ByVal fromDate, ByVal toDate, ByVal sortColumn)
    Dim cmd
    ' app.usp_Appointment_Report @UserId, @FromDate, @ToDate, @SortColumn, @SortDirection
    Set cmd = CreateSpCommand("app.usp_Appointment_Report")
    AddInputParam cmd, "@UserId", adInteger, 0, userId
    AddInputParam cmd, "@FromDate", adDBDate, 0, fromDate
    AddInputParam cmd, "@ToDate", adDBDate, 0, toDate
    AddInputParam cmd, "@SortColumn", adVarChar, 30, sortColumn
    AddInputParam cmd, "@SortDirection", adVarChar, 4, "ASC"
    Appointments_Report = ReadAllRows(cmd)
    If GetReturnValue(cmd) <> 0 Then
        HandleFatalError "usp_Appointment_Report returned " & GetReturnValue(cmd)
    End If
    Set cmd = Nothing
End Function
%>
