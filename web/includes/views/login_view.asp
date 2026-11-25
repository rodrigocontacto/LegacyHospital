<%
' views/login_view.asp - Variables: errorMessage, infoMessage, usernameValue
WriteAuthLayoutTop "Sign in"
%>
<div class="auth-card">
  <div class="auth-card__brand">
    <span class="brand__mark brand__mark--lg"><%= Icon("logo") %></span>
    <h1 class="auth-card__title">Welcome back</h1>
    <p class="auth-card__subtitle">Sign in to the LegacyHospital patient portal</p>
  </div>
<% If Len(infoMessage) > 0 Then %>
  <div class="alert alert--info" role="status"><%= Icon("info") %><span><%= Html(infoMessage) %></span></div>
<% End If %>
<% If Len(errorMessage) > 0 Then %>
  <div class="alert alert--error" role="alert"><%= Icon("alert") %><span><%= Html(errorMessage) %></span></div>
<% End If %>
  <form method="post" action="/login.asp" class="form">
    <%= CsrfField() %>
    <div class="field">
      <label class="field__label" for="username">Username</label>
      <input class="input" type="text" id="username" name="username" maxlength="50" required autocomplete="username" autofocus value="<%= Html(usernameValue) %>">
    </div>
    <div class="field">
      <label class="field__label" for="password">Password</label>
      <input class="input" type="password" id="password" name="password" maxlength="128" required autocomplete="current-password">
    </div>
    <button type="submit" class="btn btn--primary btn--block">Sign in</button>
  </form>
</div>
<p class="auth__note">Demo portal &middot; All patient data is fictional</p>
<% WriteAuthLayoutBottom %>
