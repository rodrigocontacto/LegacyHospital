<%
' =====================================================================
' core/validation.asp - Input validation. Values from Request are
' validated here before they reach the data layer.
' =====================================================================

' True only for a positive integer in the SQL INT range, written with
' digits only. Rejects "", Null, " 1", "1e3", "&H10", "1,000", "-1",
' "007" and repeated parameters ("1, 2").
Function IsValidInteger(ByVal value)
    Dim re, text
    IsValidInteger = False
    If IsNull(value) Or IsEmpty(value) Then Exit Function
    text = CStr(value)
    Set re = New RegExp
    re.Pattern = "^[1-9][0-9]{0,9}$"
    If re.Test(text) Then
        If CDbl(text) <= 2147483647 Then IsValidInteger = True
    End If
    Set re = Nothing
End Function

' Strict yyyy-mm-dd parser. Returns a Date, or Null if the text is not a
' real calendar date between 2000-01-01 and 2099-12-31.
' IsDate()/CDate() are not used: they depend on the server's regional
' settings and accept many formats ("1/2/3", "Jan 5", ...).
Function ParseIsoDate(ByVal text)
    Dim re, y, m, d, result
    ParseIsoDate = Null
    text = CStr(text & "")
    Set re = New RegExp
    re.Pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
    If re.Test(text) Then
        y = CInt(Mid(text, 1, 4))
        m = CInt(Mid(text, 6, 2))
        d = CInt(Mid(text, 9, 2))
        If y >= 2000 And y <= 2099 And m >= 1 And m <= 12 And d >= 1 And d <= 31 Then
            ' DateSerial(2026, 2, 31) silently becomes March 3: reject it.
            result = DateSerial(y, m, d)
            If Month(result) = m And Day(result) = d Then ParseIsoDate = result
        End If
    End If
    Set re = Nothing
End Function

' True for exactly 64 hex characters (the format of our random tokens).
Function IsHexToken(ByVal value)
    Dim re
    Set re = New RegExp
    re.Pattern = "^[0-9A-Fa-f]{64}$"
    IsHexToken = re.Test(CStr(value & ""))
    Set re = Nothing
End Function

' True for "", Null or text made only of spaces, tabs and line breaks.
Function IsBlank(ByVal value)
    Dim re
    Set re = New RegExp
    re.Pattern = "^\s*$"
    IsBlank = re.Test(CStr(value & ""))
    Set re = Nothing
End Function

' Browsers count a line break as one character (textarea maxlength) but
' submit CRLF. Normalizing to LF keeps both length checks in agreement.
Function NormalizeLineBreaks(ByVal value)
    NormalizeLineBreaks = Replace(Replace(CStr(value & ""), vbCrLf, vbLf), vbCr, vbLf)
End Function

' Exact, case-sensitive match against a whitelist array.
Function IsInList(ByVal value, ByVal allowedValues)
    Dim allowed
    IsInList = False
    For Each allowed In allowedValues
        If StrComp(value & "", allowed, vbBinaryCompare) = 0 Then IsInList = True
    Next
End Function
%>
