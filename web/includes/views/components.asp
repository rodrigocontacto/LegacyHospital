<%
' =====================================================================
' views/components.asp - Small reusable view pieces.
' Functions here return HTML built only from fixed strings and values
' that already went through Html().
' =====================================================================

' Inline SVG icons (no external files, allowed by the CSP).
Function Icon(ByVal name)
    Dim paths
    Select Case name
        Case "logo"
            Icon = "<svg class=""icon icon--logo"" viewBox=""0 0 24 24"" aria-hidden=""true"" focusable=""false"">" & _
                   "<rect x=""1"" y=""1"" width=""22"" height=""22"" rx=""6"" fill=""currentColor""/>" & _
                   "<path d=""M10 5.5h4v4.5h4.5v4H14v4.5h-4V14H5.5v-4H10z"" fill=""#ffffff""/></svg>"
            Exit Function
        Case "search":   paths = "<circle cx=""11"" cy=""11"" r=""7""/><path d=""M20 20l-3.5-3.5""/>"
        Case "users":    paths = "<path d=""M16 20v-1.5a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4V20""/><circle cx=""9"" cy=""7"" r=""4""/><path d=""M22 20v-1.5a4 4 0 0 0-3-3.85""/><path d=""M16 3.15a4 4 0 0 1 0 7.7""/>"
        Case "calendar": paths = "<rect x=""3"" y=""4.5"" width=""18"" height=""17"" rx=""2""/><path d=""M16 2.5v4M8 2.5v4M3 10h18""/>"
        Case "logout":   paths = "<path d=""M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4""/><path d=""M16 17l5-5-5-5""/><path d=""M21 12H9""/>"
        Case "plus":     paths = "<path d=""M12 5v14M5 12h14""/>"
        Case "alert":    paths = "<circle cx=""12"" cy=""12"" r=""10""/><path d=""M12 7.5v5""/><path d=""M12 16.5h.01""/>"
        Case "info":     paths = "<circle cx=""12"" cy=""12"" r=""10""/><path d=""M12 16v-4.5""/><path d=""M12 8h.01""/>"
        Case "note":     paths = "<path d=""M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z""/><path d=""M14 2v6h6""/><path d=""M8 13h8M8 17h5""/>"
        Case "chevron":  paths = "<path d=""M9 18l6-6-6-6""/>"
        Case Else:       paths = ""
    End Select
    Icon = "<svg class=""icon"" viewBox=""0 0 24 24"" fill=""none"" stroke=""currentColor"" stroke-width=""2"" " & _
           "stroke-linecap=""round"" stroke-linejoin=""round"" aria-hidden=""true"" focusable=""false"">" & paths & "</svg>"
End Function

' Navigation helpers: fixed strings only.
Function ActiveClass(ByVal activeNav, ByVal item)
    If activeNav = item Then ActiveClass = " is-active" Else ActiveClass = ""
End Function

Function AriaCurrent(ByVal activeNav, ByVal item)
    If activeNav = item Then AriaCurrent = " aria-current=""page""" Else AriaCurrent = ""
End Function

' Status badge. The CSS modifier comes from a fixed map, never from
' the data; the text is encoded.
Function StatusBadge(ByVal status)
    Dim modifier
    Select Case status & ""
        Case "Scheduled": modifier = "info"
        Case "Completed": modifier = "success"
        Case "Cancelled": modifier = "muted"
        Case Else:        modifier = "muted"
    End Select
    StatusBadge = "<span class=""badge badge--" & modifier & """>" & Html(status) & "</span>"
End Function

' Avatar with initials (already encoded inside).
Function Avatar(ByVal initialsText, ByVal sizeModifier)
    Dim cssClass
    cssClass = "avatar"
    If Len(sizeModifier) > 0 Then cssClass = cssClass & " avatar--" & sizeModifier
    Avatar = "<span class=""" & cssClass & """ aria-hidden=""true"">" & Html(initialsText) & "</span>"
End Function
%>
