<%
' views/add_note_view.asp
' Variables: patient (one row), patientId, noteText, errorMessage
WriteLayoutTop "Add note", "patients"
%>
<nav class="breadcrumb" aria-label="Breadcrumb">
  <a href="/search.asp">Patients</a>
  <span class="breadcrumb__sep" aria-hidden="true"><%= Icon("chevron") %></span>
  <a href="/patient.asp?id=<%= Html(patientId) %>"><%= Html(patient(PATIENT_COL_LAST_NAME, 0)) %>, <%= Html(patient(PATIENT_COL_FIRST_NAME, 0)) %></a>
  <span class="breadcrumb__sep" aria-hidden="true"><%= Icon("chevron") %></span>
  <span aria-current="page">Add note</span>
</nav>

<div class="page-header">
  <div>
    <h1 class="page-header__title">Add clinical note</h1>
    <p class="page-header__subtitle"><%= Html(patient(PATIENT_COL_LAST_NAME, 0)) %>, <%= Html(patient(PATIENT_COL_FIRST_NAME, 0)) %> &middot; <span class="mono"><%= Html(patient(PATIENT_COL_RECORD_NUMBER, 0)) %></span></p>
  </div>
</div>

<% If Len(errorMessage) > 0 Then %>
<div class="alert alert--error" role="alert"><%= Icon("alert") %><span><%= Html(errorMessage) %></span></div>
<% End If %>

<section class="card">
  <form method="post" action="/add_note.asp?id=<%= Html(patientId) %>" class="form">
    <%= CsrfField() %>
    <div class="field">
      <label class="field__label" for="note_text">Note</label>
      <textarea class="input textarea" id="note_text" name="note_text" rows="8" maxlength="2000" required><%= Html(noteText) %></textarea>
      <p class="hint">Up to 2000 characters. The note is saved with your name and the current date and time.</p>
    </div>
    <div class="form__actions">
      <a class="btn btn--ghost" href="/patient.asp?id=<%= Html(patientId) %>">Cancel</a>
      <button type="submit" class="btn btn--primary">Save note</button>
    </div>
  </form>
</section>
<% WriteLayoutBottom %>
