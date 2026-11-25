<#
.SYNOPSIS
    Compile-only syntax check of every Classic ASP page in web/ (nothing runs).

.DESCRIPTION
    For each web/*.asp page: inlines its #include files, keeps only the
    server-side VBScript (<%= x %> becomes Response.Write) and compiles it with
    cscript after "WScript.Quit". Compile errors and duplicate names
    ("Name redefined", e.g. a constant declared in two includes) are reported
    without executing any code. global.asa is checked too.

    Not detected: runtime errors, including undeclared variables under
    Option Explicit. Run tests/e2e-security.ps1 against the running site for those.

.PARAMETER Hook
    Claude Code PostToolUse mode. Reads the hook JSON from stdin and only runs
    when the edited file is a .asp/.asa under web/. On errors it writes them to
    stderr and exits 2, so Claude sees them right after the edit.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\asp-syntax-check.ps1
#>
param([switch]$Hook)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$webRoot = Join-Path $repoRoot 'web'

if ($Hook) {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $file = $payload.tool_input.file_path
    if (-not $file) { exit 0 }
    $full = [IO.Path]::GetFullPath($file)
    if (-not $full.StartsWith($webRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { exit 0 }
    if ($full -notmatch '\.(asp|asa)$') { exit 0 }
}

function Expand-Includes([string]$path) {
    $text = [IO.File]::ReadAllText($path)
    $dir = Split-Path $path -Parent
    return [regex]::Replace($text, '<!--#include file="([^"]+)"-->', {
        param($m) Expand-Includes (Join-Path $dir $m.Groups[1].Value)
    })
}

function Convert-ToVbs([string]$text) {
    $text = [regex]::Replace($text, '<%@.*?%>', '')
    $sb = New-Object Text.StringBuilder
    $pos = 0
    foreach ($m in [regex]::Matches($text, '<%([\s\S]*?)%>')) {
        # Keep line count so error line numbers stay roughly meaningful.
        $html = $text.Substring($pos, $m.Index - $pos)
        [void]$sb.Append("`r`n" * ([regex]::Matches($html, "`n").Count))
        $code = $m.Groups[1].Value
        if ($code.StartsWith('=')) { [void]$sb.Append("Response.Write (" + $code.Substring(1) + ")`r`n") }
        else { [void]$sb.Append($code + "`r`n") }
        $pos = $m.Index + $m.Length
    }
    $body = [regex]::Replace($sb.ToString(), '(?im)^\s*Option Explicit\s*$', '')
    return "Option Explicit : WScript.Quit`r`n" + $body
}

function Test-Vbs([string]$name, [string]$code, [string]$outDir) {
    $vbs = Join-Path $outDir (($name -replace '[^A-Za-z0-9_.-]', '_') + '.vbs')
    [IO.File]::WriteAllText($vbs, $code, [Text.Encoding]::ASCII)
    # cmd merges stderr into stdout: in Windows PowerShell 5.1 a native
    # command writing to stderr would raise a terminating error here.
    $out = (cmd /c "cscript //nologo `"$vbs`" 2>&1") -join ' '
    if ($LASTEXITCODE -eq 0 -and -not $out.Trim()) { return $null }
    return $out.Trim()
}

$outDir = Join-Path $env:TEMP 'legacyhospital-asp-check'
New-Item -ItemType Directory -Force $outDir | Out-Null

$errors = @()
$results = @()
foreach ($page in Get-ChildItem $webRoot -Filter *.asp) {
    $err = Test-Vbs $page.Name (Convert-ToVbs (Expand-Includes $page.FullName)) $outDir
    if ($err) { $errors += "$($page.Name): $err" }
    $results += "{0,-14} {1}" -f $page.Name, $(if ($err) { "ERROR  $err" } else { 'OK' })
}
$asaPath = Join-Path $webRoot 'global.asa'
if (Test-Path $asaPath) {
    $asa = [IO.File]::ReadAllText($asaPath)
    $asaCode = [regex]::Match($asa, '(?is)<SCRIPT[^>]*>(.*)</SCRIPT>').Groups[1].Value
    # Option Explicit must be its first statement (CLAUDE.md, F-21). The
    # wrapper below already starts with one, so the file's own is removed.
    if ($asaCode -notmatch '\A\s*Option Explicit[ \t]*\r?\n') { $errors += 'global.asa: Option Explicit must be the first statement' }
    $asaCode = [regex]::Replace($asaCode, '(?im)^[ \t]*Option Explicit[ \t]*\r?$', '')
    $err = Test-Vbs 'global.asa' ("Option Explicit : WScript.Quit`r`n" + $asaCode) $outDir
    if ($err) { $errors += "global.asa: $err" }
    $results += "{0,-14} {1}" -f 'global.asa', $(if ($err) { "ERROR  $err" } else { 'OK' })
}

if ($Hook) {
    if ($errors.Count -gt 0) {
        [Console]::Error.WriteLine("ASP syntax check failed (tests/asp-syntax-check.ps1):")
        $errors | ForEach-Object { [Console]::Error.WriteLine("  $_") }
        exit 2
    }
    exit 0
}

$results
if ($errors.Count -gt 0) { exit 1 }
exit 0
