<%
' =====================================================================
' core/encoding.asp - Output encoding and display formatting.
' Every value written to HTML goes through Html() or HtmlMultiline().
' Attributes always use double quotes: HTMLEncode does not encode '.
' =====================================================================

' Server.HTMLEncode that tolerates Null/Empty (database NULLs).
Function Html(ByVal value)
    Dim plain
    plain = value   ' evaluates the default property of ADO Fields
    If IsNull(plain) Or IsEmpty(plain) Then
        Html = ""
    Else
        Html = Server.HTMLEncode(CStr(plain))
    End If
End Function

' Html() that keeps line breaks: encodes first, then turns the (already
' safe) newlines into <br>.
Function HtmlMultiline(ByVal value)
    Dim encoded
    encoded = Html(value)
    encoded = Replace(encoded, vbCrLf, vbLf)
    encoded = Replace(encoded, vbCr, vbLf)
    HtmlMultiline = Replace(encoded, vbLf, "<br>" & vbCrLf)
End Function

' yyyy-mm-dd, independent of the server's regional settings.
' Returns "" for Null or anything that is not a date.
Function FormatIsoDate(ByVal value)
    If IsDate(value) Then
        FormatIsoDate = Year(value) & "-" & Right("0" & Month(value), 2) & "-" & Right("0" & Day(value), 2)
    Else
        FormatIsoDate = ""
    End If
End Function

' yyyy-mm-dd hh:nn
Function FormatIsoDateTime(ByVal value)
    If IsDate(value) Then
        FormatIsoDateTime = FormatIsoDate(value) & " " & FormatTime(value)
    Else
        FormatIsoDateTime = ""
    End If
End Function

' hh:nn (24 h)
Function FormatTime(ByVal value)
    If IsDate(value) Then
        FormatTime = Right("0" & Hour(value), 2) & ":" & Right("0" & Minute(value), 2)
    Else
        FormatTime = ""
    End If
End Function

' Full years between a date of birth and today. "" if not a date.
Function AgeInYears(ByVal dateOfBirth)
    Dim years
    AgeInYears = ""
    If Not IsDate(dateOfBirth) Then Exit Function
    years = DateDiff("yyyy", dateOfBirth, Date())
    If DateSerial(Year(Date()), Month(dateOfBirth), Day(dateOfBirth)) > Date() Then years = years - 1
    AgeInYears = years
End Function

' "1 patient", "4 patients".
Function Pluralize(ByVal count, ByVal singular, ByVal plural)
    If count = 1 Then
        Pluralize = count & " " & singular
    Else
        Pluralize = count & " " & plural
    End If
End Function

' Two uppercase letters for avatars ("Laura", "Martinez" -> "LM").
' The result still has to go through Html().
Function Initials(ByVal firstName, ByVal lastName)
    Initials = UCase(Left(firstName & "", 1) & Left(lastName & "", 1))
End Function

' "Ana Garcia" -> "AG": first letter of the first and last words.
Function InitialsFromFullName(ByVal fullName)
    Dim parts
    parts = Split(Trim(fullName & ""), " ")
    If UBound(parts) < 0 Then
        InitialsFromFullName = ""
    Else
        InitialsFromFullName = Initials(parts(0), parts(UBound(parts)))
    End If
End Function
%>
