<# Bucket A: event-logs -- wevtutil cl <each> #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "event-logs" -Label "Windows event logs (wevtutil)" -Bucket "A"

$logs = @()
try { $logs = & wevtutil.exe el 2>$null } catch {}

if ($DryRun) {
    $result.WouldCount = $logs.Count
    $result.Notes += "DRY-RUN: would clear $($logs.Count) event log(s)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$errors = 0
foreach ($l in $logs) {
    $name = "$l".Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    try {
        & wevtutil.exe cl "$name" 2>$null
        if ($LASTEXITCODE -eq 0) { $result.Count++ } else { $errors++ }
    } catch { $errors++ }
}
if ($errors -gt 0) {
    $result.Status = "warn"
    $result.Notes += "$errors log(s) failed to clear (often by-design protected)"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
