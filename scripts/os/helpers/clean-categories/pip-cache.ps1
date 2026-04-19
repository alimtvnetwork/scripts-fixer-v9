<# Bucket F: pip-cache -- pip cache purge #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "pip-cache" -Label "pip cache" -Bucket "F"

$pip = Get-Command pip -ErrorAction SilentlyContinue
if ($null -eq $pip) {
    $result.Notes += "pip not installed"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$cacheDir = $null
try { $cacheDir = (& pip cache dir 2>$null).Trim() } catch {}
$bytesBefore = 0
if ($cacheDir -and (Test-Path -LiteralPath $cacheDir)) { $bytesBefore = Get-DirSize -Path $cacheDir }

if ($DryRun) {
    $result.WouldCount = 1
    $result.WouldBytes = $bytesBefore
    $result.Notes += "DRY-RUN: would run 'pip cache purge' on $cacheDir"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

try {
    & pip cache purge 2>&1 | Out-Null
    $bytesAfter = if ($cacheDir -and (Test-Path -LiteralPath $cacheDir)) { Get-DirSize -Path $cacheDir } else { 0 }
    $result.Count = 1
    $result.Bytes = [long]([Math]::Max(0, $bytesBefore - $bytesAfter))
    $result.Notes += "pip cache purged: $cacheDir"
} catch {
    $result.Status = "fail"
    $result.Notes += "pip cache purge failed: $($_.Exception.Message)"
    Write-Log "pip cache purge failed at ${cacheDir}: $($_.Exception.Message)" -Level "fail"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
