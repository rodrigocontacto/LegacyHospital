<%
' views/search_view.asp
' Variables: searchTerm, hasSearched, errorMessage, results, resultCount, i
WriteLayoutTop "Patients", "patients"
%>
<div class="page-header">
  <div>
    <h1 class="page-header__title">Patients</h1>
    <p class="page-header__subtitle">Search your assigned patients by last name, first name or record number.</p>
  </div>
</div>

<section class="card">
  <form method="post" action="/search.asp" role="search" class="search-form">
    <%= CsrfField() %>
    <label class="visually-hidden" for="q">Last name</label>
    <div class="input-group">
      <span class="input-group__icon"><%= Icon("search") %></span>
      <input class="input input--with-icon" type="search" id="q" name="q" maxlength="50" placeholder="e.g. Martinez, Laura or MRN-0001" value="<%= Html(searchTerm) %>">
    </div>
    <button type="submit" class="btn btn--primary">Search</button>
  </form>
  <p class="hint">Leave the field empty to list all your patients.</p>
</section>

<% If Len(errorMessage) > 0 Then %>
<div class="alert alert--error" role="alert"><%= Icon("alert") %><span><%= Html(errorMessage) %></span></div>
<% ElseIf hasSearched Then %>
<section class="card card--flush">
  <div class="card__header">
<% If Len(searchTerm) > 0 Then %>
    <h2 class="card__title">Results for &ldquo;<%= Html(searchTerm) %>&rdquo;</h2>
<% Else %>
    <h2 class="card__title">All your patients</h2>
<% End If %>
    <span class="pill"><%= Html(Pluralize(resultCount, "patient", "patients")) %></span>
  </div>
<% If resultCount = 0 Then %>
  <div class="empty-state">
    <span class="empty-state__icon"><%= Icon("search") %></span>
    <p class="empty-state__title">No patients found.</p>
    <p class="empty-state__text">Check the spelling, or search by record number.</p>
  </div>
<% Else %>
<% If resultCount >= PATIENT_SEARCH_MAX_RESULTS Then %>
  <div class="alert alert--warning alert--inset"><%= Icon("info") %><span>Only the first <%= Html(PATIENT_SEARCH_MAX_RESULTS) %> results are shown. Refine your search.</span></div>
<% End If %>
  <div class="table-wrap">
    <table class="table">
      <thead>
        <tr>
          <th scope="col">Patient</th>
          <th scope="col">Record number</th>
          <th scope="col">Date of birth</th>
          <th scope="col">Age</th>
          <th scope="col"><span class="visually-hidden">Actions</span></th>
        </tr>
      </thead>
      <tbody>
<% For i = 0 To resultCount - 1 %>
        <tr>
          <td>
            <div class="person">
              <%= Avatar(Initials(results(PATIENT_COL_FIRST_NAME, i), results(PATIENT_COL_LAST_NAME, i)), "") %>
              <a class="person__name" href="/patient.asp?id=<%= Html(results(PATIENT_COL_ID, i)) %>"><%= Html(results(PATIENT_COL_LAST_NAME, i)) %>, <%= Html(results(PATIENT_COL_FIRST_NAME, i)) %></a>
            </div>
          </td>
          <td class="mono"><%= Html(results(PATIENT_COL_RECORD_NUMBER, i)) %></td>
          <td><%= Html(FormatIsoDate(results(PATIENT_COL_DATE_OF_BIRTH, i))) %></td>
          <td><%= Html(AgeInYears(results(PATIENT_COL_DATE_OF_BIRTH, i))) %></td>
          <td class="table__actions"><a class="btn btn--ghost btn--sm" href="/patient.asp?id=<%= Html(results(PATIENT_COL_ID, i)) %>">Open record<%= Icon("chevron") %></a></td>
        </tr>
<% Next %>
      </tbody>
    </table>
  </div>
<% End If %>
</section>
<% End If %>
<% WriteLayoutBottom %>
