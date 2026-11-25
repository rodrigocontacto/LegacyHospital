<%@ Language="VBScript" CodePage="65001" %>
<% Option Explicit %>
<!--#include file="includes/app.asp"-->
<%
' =====================================================================
' report.asp - Appointments of the logged-in doctor's patients
' (controller). GET form (read-only, no CSRF token needed).
'   - from / to: strict yyyy-mm-dd, from <= to, at most 90 days apart.
'     Invalid input shows a message.
'   - sort: checked against the SAME whitelist the procedure uses before
'     it is sent. Anything else is tampering -> 400.
' =====================================================================
RequireLogin

Dim fromText, toText, sortColumn, fromDate, toDate, errorMessage
Dim rows, resultCount, scheduledCount, completedCount, cancelledCount, i, column

errorMessage = ""
rows = Empty
resultCount = 0
scheduledCount = 0
completedCount = 0
cancelledCount = 0

' Defaults on first visit: 30 days back to 30 days ahead.
fromText = QueryValueOrDefault("from", FormatIsoDate(DateAdd("d", -30, Date())))
toText = QueryValueOrDefault("to", FormatIsoDate(DateAdd("d", 30, Date())))
sortColumn = QueryValueOrDefault("sort", APPOINTMENT_REPORT_DEFAULT_SORT)

' The <select> only offers whitelisted values: anything else was typed
' into the URL on purpose.
If Not Appointments_IsAllowedSort(sortColumn) Then
    EndWithMessage "400 Bad Request", "Invalid request", "The request is not valid."
End If

fromDate = ParseIsoDate(fromText)
toDate = ParseIsoDate(toText)

If IsNull(fromDate) Or IsNull(toDate) Then
    errorMessage = "Enter valid dates in the format yyyy-mm-dd."
ElseIf fromDate > toDate Then
    errorMessage = "The start date must be on or before the end date."
ElseIf DateDiff("d", fromDate, toDate) > APPOINTMENT_REPORT_MAX_DAYS Then
    errorMessage = "The date range can be at most 90 days."
Else
    rows = Appointments_Report(CurrentUserId(), fromDate, toDate, sortColumn)
    resultCount = RowCount(rows)
    scheduledCount = Appointments_CountByStatus(rows, "Scheduled")
    completedCount = Appointments_CountByStatus(rows, "Completed")
    cancelledCount = Appointments_CountByStatus(rows, "Cancelled")
End If
%>
<!--#include file="includes/views/report_view.asp"-->
<% CloseConnection %>
