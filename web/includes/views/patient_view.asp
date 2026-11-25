<%
' views/patient_view.asp
' Variables: patient (one row), notes, noteCount, noteAdded, i
WriteLayoutTop "Patient record", "patients"
%>
<% If noteAdded Then %>
<div class="alert alert--success" role="status"><%= Icon("note") %><span>Note added.</span></div>
<% End If %>
<nav class="breadcrumb" aria-label="Breadcrumb">
  <a href="/search.asp">Patients</a>
  <span class="breadcrumb__sep" aria-hidden="true"><%= Icon("chevron") %></span>
  <span aria-current="page"><%= Html(patient(PATIENT_COL_LAST_NAME, 0)) %>, <%= Html(patient(PATIENT_COL_FIRST_NAME, 0)) %></span>
</nav>

<section class="card patient-header">
  <%= Avatar(Initials(patient(PATIENT_COL_FIRST_NAME, 0), patient(PATIENT_COL_LAST_NAME, 0)), "lg") %>
  <div class="patient-header__main">
    <h1 class="patient-header__name"><%= Html(patient(PATIENT_COL_LAST_NAME, 0)) %>, <%= Html(patient(PATIENT_COL_FIRST_NAME, 0)) %></h1>
    <dl class="meta">
      <div class="meta__item">
        <dt>Record number</dt>
        <dd class="mono"><%= Html(patient(PATIENT_COL_RECORD_NUMBER, 0)) %></dd>
      </div>
      <div class="meta__item">
        <dt>Date of birth</dt>
        <dd><%= Html(FormatIsoDate(patient(PATIENT_COL_DATE_OF_BIRTH, 0))) %></dd>
      </div>
      <div class="meta__item">
        <dt>Age</dt>
        <dd><%= Html(AgeInYears(patient(PATIENT_COL_DATE_OF_BIRTH, 0))) %> years</dd>
      </div>
    </dl>
  </div>
  <div class="patient-header__actions">
    <a class="btn btn--primary" href="/add_note.asp?id=<%= Html(patient(PATIENT_COL_ID, 0)) %>"><%= Icon("plus") %><span>Add note</span></a>
  </div>
</section>

<section class="card">
  <div class="card__header card__header--plain">
    <h2 class="card__title">Clinical notes</h2>
    <span class="pill"><%= Html(Pluralize(noteCount, "note", "notes")) %></span>
  </div>
<% If noteCount = 0 Then %>
  <div class="empty-state">
    <span class="empty-state__icon"><%= Icon("note") %></span>
    <p class="empty-state__title">No notes yet.</p>
    <p class="empty-state__text">Notes added for this patient will appear here.</p>
  </div>
<% Else %>
  <ol class="timeline">
<% For i = 0 To noteCount - 1 %>
    <li class="timeline__item">
      <div class="timeline__meta">
        <time><%= Html(FormatIsoDateTime(notes(NOTE_COL_CREATED_AT, i))) %> UTC</time>
        <span class="timeline__author"><%= Html(notes(NOTE_COL_AUTHOR, i)) %></span>
      </div>
      <div class="timeline__body"><%= HtmlMultiline(notes(NOTE_COL_TEXT, i)) %></div>
    </li>
<% Next %>
  </ol>
<% End If %>
</section>
<% WriteLayoutBottom %>
