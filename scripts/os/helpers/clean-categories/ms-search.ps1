<# Bucket B: ms-search -- Stop WSearch + delete Windows.edb + restart (DESTRUCTIVE, consent-gated) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "ms-search" -Label "Windows Search index (Windows.edb)" -Bucket "B" -Destructive

$consented = Confirm-DestructiveCategory -Category "ms-search" `
    -Warning "Wipes Windows Search index. Re-index can take HOURS during which Start menu / File Explorer search is degraded." `
    -AutoYes:$Yes -DryRun:$DryRun
if (-not $consented) {
    $result.Status = "skip"
    $result.Notes += "Consent declined"
    return $result
}

$edbDir = Join-Path (Get-ProgramDataPath) "Microsoft\Search\Data\Applications\Windows"
$edb    = Join-Path $edbDir "Windows.edb"

if (-not (Test-Path -LiteralPath $edb)) {
    $result.Notes += "Windows.edb not present at $edb"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$sz = Get-PathSize -Path $edb
if ($DryRun) {
    $result.WouldCount = 1; $result.WouldBytes = $sz
    $result.Notes += "DRY-RUN: would stop WSearch, delete $edb ($([Math]::Round($sz/1MB,2)) MB), restart WSearch"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$wasRunning = Stop-WindowsService -Name "WSearch" -Result $result
try {
    Remove-Item -LiteralPath $edb -Force -ErrorAction Stop
    $result.Count = 1; $result.Bytes = $sz
} catch {
    $reason = Get-LockReason -Ex $_.Exception
    $result.Locked++
    $result.LockedDetails += @{ Path = $edb; Reason = $reason }
    Write-Log "ms-search locked at ${edb}: ${reason}" -Level "warn"
}
if ($wasRunning) { Start-WindowsService -Name "WSearch" -Result $result }

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
