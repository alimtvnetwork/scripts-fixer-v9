<# Bucket F: npm-cache -- npm cache clean --force #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "npm-cache" -Label "npm cache" -Bucket "F"

$npm = Get-Command npm -ErrorAction SilentlyContinue
if ($null -eq $npm) {
    $result.Notes += "npm not installed"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Pre-measure cache dir for byte reporting
$cacheDir = $null
try { $cacheDir = (& npm config get cache 2>$null).Trim() } catch {}
$bytesBefore = 0
if ($cacheDir -and (Test-Path -LiteralPath $cacheDir)) { $bytesBefore = Get-DirSize -Path $cacheDir }

if ($DryRun) {
    $result.WouldCount = 1
    $result.WouldBytes = $bytesBefore
    $result.Notes += "DRY-RUN: would run 'npm cache clean --force' on $cacheDir"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

try {
    & npm cache clean --force 2>&1 | Out-Null
    $bytesAfter = if ($cacheDir -and (Test-Path -LiteralPath $cacheDir)) { Get-DirSize -Path $cacheDir } else { 0 }
    $result.Count = 1
    $result.Bytes = [long]([Math]::Max(0, $bytesBefore - $bytesAfter))
    $result.Notes += "npm cache cleaned: $cacheDir"
} catch {
    $result.Status = "fail"
    $result.Notes += "npm cache clean failed: $($_.Exception.Message)"
    Write-Log "npm cache clean failed at ${cacheDir}: $($_.Exception.Message)" -Level "fail"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
