<%
' =====================================================================
' views/layout.asp - Page shells.
'
'   WriteLayoutTop / WriteLayoutBottom          logged-in pages
'   WriteAuthLayoutTop / WriteAuthLayoutBottom  login and message pages
'   WriteMessagePage                            full generic page
'
' The message page uses the anonymous shell on purpose: it must render
' even when the database is down (no CSRF token needed).
' No inline <style> or style="": the CSP only allows /assets/css.
' =====================================================================

Sub WriteDocumentHead(ByVal pageTitle, ByVal bodyClass)
%><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><%= Html(pageTitle) %> &middot; LegacyHospital</title>
<link rel="icon" href="/assets/img/logo.svg" type="image/svg+xml">
<link rel="stylesheet" href="/assets/css/app.css">
</head>
<body class="<%= bodyClass %>">
<%
End Sub

Sub WriteLayoutTop(ByVal pageTitle, ByVal activeNav)
    WriteDocumentHead pageTitle, "app"
%><a class="skip-link" href="#main">Skip to content</a>
<header class="topbar">
  <div class="topbar__inner">
    <a class="brand" href="/search.asp">
      <span class="brand__mark"><%= Icon("logo") %></span>
      <span class="brand__name">LegacyHospital</span>
    </a>
    <nav class="nav" aria-label="Main">
      <a class="nav__link<%= ActiveClass(activeNav, "patients") %>" href="/search.asp"<%= AriaCurrent(activeNav, "patients") %>><%= Icon("users") %><span>Patients</span></a>
      <a class="nav__link<%= ActiveClass(activeNav, "appointments") %>" href="/report.asp"<%= AriaCurrent(activeNav, "appointments") %>><%= Icon("calendar") %><span>Appointments</span></a>
    </nav>
    <div class="user-menu">
      <%= Avatar(InitialsFromFullName(CurrentUserName()), "sm") %>
      <span class="user-menu__text">
        <span class="user-menu__name"><%= Html(CurrentUserName()) %></span>
        <span class="user-menu__role"><%= Html(CurrentUserRole()) %></span>
      </span>
      <form method="post" action="/logout.asp" class="user-menu__form">
        <%= CsrfField() %>
        <button type="submit" class="btn btn--ghost btn--sm"><%= Icon("logout") %><span>Sign out</span></button>
      </form>
    </div>
  </div>
</header>
<main class="page" id="main">
<%
End Sub

Sub WriteLayoutBottom()
%></main>
<footer class="footer">
  <div class="footer__inner">LegacyHospital &middot; Demo portal. All patient data is fictional.</div>
</footer>
</body>
</html>
<%
End Sub

Sub WriteAuthLayoutTop(ByVal pageTitle)
    WriteDocumentHead pageTitle, "auth"
%><main class="auth__main" id="main">
<%
End Sub

Sub WriteAuthLayoutBottom()
%></main>
</body>
</html>
<%
End Sub

Sub WriteMessagePage(ByVal title, ByVal message)
    WriteAuthLayoutTop title
%><div class="auth-card auth-card--message">
  <span class="message-icon"><%= Icon("alert") %></span>
  <h1 class="auth-card__title"><%= Html(title) %></h1>
  <p class="auth-card__subtitle"><%= Html(message) %></p>
<% If IsLoggedIn() Then %>
  <a class="btn btn--primary btn--block" href="/search.asp">Back to patients</a>
<% Else %>
  <a class="btn btn--primary btn--block" href="/login.asp">Go to sign in</a>
<% End If %>
</div>
<%
    WriteAuthLayoutBottom
End Sub
%>
