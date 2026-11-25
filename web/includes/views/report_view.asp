<%
' views/report_view.asp
' Variables: fromText, toText, sortColumn, fromDate, toDate, errorMessage,
'            rows, resultCount, scheduledCount, completedCount,
'            cancelledCount, i, column
WriteLayoutTop "Appointments", "appointments"
%>
<div class="page-header">
  <div>
    <h1 class="page-header__title">Appointments</h1>
    <p class="page-header__subtitle">Appointments of your patients for a period of up to 90 days. Times are clinic local time.</p>
  </div>
</div>

<section class="card">
  <form method="get" action="/report.asp" class="filters">
    <div class="field">
      <label class="field__label" for="from">From</label>
      <input class="input" type="date" id="from" name="from" required value="<%= Html(fromText) %>">
    </div>
    <div class="field">
      <label class="field__label" for="to">To</label>
      <input class="input" type="date" id="to" name="to" required value="<%= Html(toText) %>">
    </div>
    <div class="field">
      <label class="field__label" for="sort">Sort by</label>
      <select class="input" id="sort" name="sort">
<% For Each column In Appointments_SortColumns() %>
        <option value="<%= Html(column) %>"<% If column = sortColumn Then %> selected<% End If %>><%= Html(Appointments_SortLabel(column)) %></option>
<% Next %>
      </select>
    </div>
    <div class="filters__actions">
      <button type="submit" class="btn btn--primary">Apply</button>
    </div>
  </form>
</section>

<% If Len(errorMessage) > 0 Then %>
<div class="alert alert--error" role="alert"><%= Icon("alert") %><span><%= Html(errorMessage) %></span></div>
<% Else %>
<div class="stats">
  <div class="stat">
    <span class="stat__label">Total</span>
    <span class="stat__value"><%= Html(resultCount) %></span>
  </div>
  <div class="stat stat--info">
    <span class="stat__label">Scheduled</span>
    <span class="stat__value"><%= Html(scheduledCount) %></span>
  </div>
  <div class="stat stat--success">
    <span class="stat__label">Completed</span>
    <span class="stat__value"><%= Html(completedCount) %></span>
  </div>
  <div class="stat stat--muted">
    <span class="stat__label">Cancelled</span>
    <span class="stat__value"><%= Html(cancelledCount) %></span>
  </div>
</div>

<section class="card card--flush">
  <div class="card__header">
    <h2 class="card__title"><%= Html(FormatIsoDate(fromDate)) %> &ndash; <%= Html(FormatIsoDate(toDate)) %></h2>
    <span class="pill"><%= Html(Pluralize(resultCount, "appointment", "appointments")) %></span>
  </div>
<% If resultCount = 0 Then %>
  <div class="empty-state">
    <span class="empty-state__icon"><%= Icon("calendar") %></span>
    <p class="empty-state__title">No appointments in this period.</p>
    <p class="empty-state__text">Try a different date range.</p>
  </div>
<% Else %>
<% If resultCount >= APPOINTMENT_REPORT_MAX_ROWS Then %>
  <div class="alert alert--warning alert--inset"><%= Icon("info") %><span>Only the first <%= Html(APPOINTMENT_REPORT_MAX_ROWS) %> appointments are shown. Use a shorter period.</span></div>
<% End If %>
  <div class="table-wrap">
    <table class="table">
      <thead>
        <tr>
          <th scope="col">Date</th>
          <th scope="col">Time</th>
          <th scope="col">Patient</th>
          <th scope="col">Record number</th>
          <th scope="col">Reason</th>
          <th scope="col">Status</th>
        </tr>
      </thead>
      <tbody>
<% For i = 0 To resultCount - 1 %>
        <tr>
          <td class="nowrap"><%= Html(FormatIsoDate(rows(APPOINTMENT_COL_SCHEDULED_AT, i))) %></td>
          <td class="mono"><%= Html(FormatTime(rows(APPOINTMENT_COL_SCHEDULED_AT, i))) %></td>
          <td><a class="person__name" href="/patient.asp?id=<%= Html(rows(APPOINTMENT_COL_PATIENT_ID, i)) %>"><%= Html(rows(APPOINTMENT_COL_LAST_NAME, i)) %>, <%= Html(rows(APPOINTMENT_COL_FIRST_NAME, i)) %></a></td>
          <td class="mono"><%= Html(rows(APPOINTMENT_COL_RECORD_NUMBER, i)) %></td>
          <td><%= Html(rows(APPOINTMENT_COL_REASON, i)) %></td>
          <td><%= StatusBadge(rows(APPOINTMENT_COL_STATUS, i)) %></td>
        </tr>
<% Next %>
      </tbody>
    </table>
  </div>
<% End If %>
</section>
<% End If %>
<% WriteLayoutBottom %>
