<#
.SYNOPSIS
    os clean -- Full Windows housekeeping sweep.

.DESCRIPTION
    Wipes:
      Step 1. C:\Windows\SoftwareDistribution\Download  (Windows Update cache)
      Step 2. CASCADES into `os temp-clean` (sweeps %TEMP%, C:\Windows\Temp,
              %LOCALAPPDATA%\Temp, all per-user Temp dirs, choco TEMP)
      Step 3. Chocolatey cache (lib-bad, lib-bkp, *.backup, *.nupkg cache,
              and runs choco-cleaner if installed). LIVE choco install untouched.
      Step 4. All Windows event logs (wevtutil cl)
      Step 5. PSReadLine command history file
      Step 6. Current session command history (Clear-History)

    Locked files are CAUGHT (not crashed on), accumulated, and reported in a
    dedicated [LOCKED FILES] section at the end with the OS reason.

    CODE RED: every file/path failure logs the exact path + reason.
#>
param(
    [switch]$Yes,
    [switch]$Force,
    [switch]$IncludeWindowsTemp,   # legacy: kept for back-compat. Now always-on via temp-clean cascade.
    [switch]$NoChoco,
    [switch]$NoTempCascade
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$helpersDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptDir  = Split-Path -Parent $helpersDir
$sharedDir  = Join-Path (Split-Path -Parent $scriptDir) "shared"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")
. (Join-Path $helpersDir "_common.ps1")
. (Join-Path $helpersDir "choco-clean.ps1")

$config      = Import-JsonConfig (Join-Path $scriptDir "config.json")
$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")
$script:LogMessages = $logMessages

Initialize-Logging -ScriptName "OS Clean"

$forwardArgs = @()
if ($Yes)                { $forwardArgs += "-Yes" }
if ($Force)              { $forwardArgs += "-Force" }
if ($IncludeWindowsTemp) { $forwardArgs += "-IncludeWindowsTemp" }
if ($NoChoco)            { $forwardArgs += "-NoChoco" }
if ($NoTempCascade)      { $forwardArgs += "-NoTempCascade" }

$isAdminOk = Assert-Admin -ScriptPath $MyInvocation.MyCommand.Definition `
                          -ForwardArgs $forwardArgs `
                          -LogMessages $logMessages
if (-not $isAdminOk) {
    Save-LogFile -Status "fail"
    exit 1
}

$autoYes = $Yes -or $Force
$confirmed = Confirm-Action -Prompt "This wipes Windows Update cache, ALL temp dirs (incl. per-user + choco temp), Chocolatey cache (lib-bad/lib-bkp/.nupkg), event logs, and PSReadLine history. Continue? [y/N]: " -AutoYes:$autoYes
if (-not $confirmed) {
    Write-Log $logMessages.messages.userCancelled -Level "warn"
    Save-LogFile -Status "skip"
    exit 0
}

$results   = @()
$allLocked = @()

function Get-DirSize {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) { return 0 }
        $sum = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [long]$sum
    } catch { return 0 }
}

function Get-LockReason {
    param([System.Exception]$Ex)
    if ($null -eq $Ex) { return "unknown error" }
    $msg = $Ex.Message
    if ($msg -match "being used by another process|in use") { return "in use by another process" }
    if ($msg -match "denied|UnauthorizedAccess")            { return "access denied (locked or protected)" }
    if ($msg -match "sharing violation")                    { return "sharing violation (open handle)" }
    return $msg.Split("`n")[0].Trim()
}

function Clear-FolderContents {
    param([string]$Path, [string]$Label, [int]$StepNum)

    $r = [ordered]@{
        Step = $StepNum; Label = $Label; Count = 0; Bytes = 0; Locked = 0;
        LockedDetails = @(); Status = "ok"
    }

    if (-not (Test-Path $Path)) {
        Write-Log "Step ${StepNum}: ${Label} -- path not present: ${Path}" -Level "skip"
        $r.Status = "skip"
        return $r
    }

    $sizeBefore = Get-DirSize -Path $Path
    $items      = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue

    foreach ($it in $items) {
        try {
            Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop
            $r.Count++
        } catch {
            $reason = Get-LockReason -Ex $_.Exception
            $r.Locked++
            $r.LockedDetails += @{ Path = $it.FullName; Reason = $reason }
            Write-Log "Step ${StepNum} locked at $($it.FullName): ${reason}" -Level "warn"
        }
    }

    $sizeAfter = Get-DirSize -Path $Path
    $r.Bytes = [long]([Math]::Max(0, $sizeBefore - $sizeAfter))
    if ($r.Locked -gt 0) { $r.Status = "warn" }

    $mb = Format-Bytes -Bytes $r.Bytes
    Write-Log "Step ${StepNum} done: ${Label} -- removed $($r.Count) item(s), freed ${mb} MB, locked $($r.Locked)" -Level $(if ($r.Locked -eq 0) { "success" } else { "warn" })
    return $r
}

# ==================== Step 1: Windows Update cache ====================
$results += Clear-FolderContents -Path $config.clean.softwareDistribution -Label "Windows Update cache" -StepNum 1

# ==================== Step 2: cascade os temp-clean ====================
if ($config.clean.tempCleanCascade -and -not $NoTempCascade) {
    $msg = ($logMessages.clean.cascadingTempClean -replace '\{n\}', '2')
    Write-Log $msg -Level "info"
    try {
        $tempResult = & (Join-Path $helpersDir "temp-clean.ps1") -Yes -ReturnResults -NoConfirm
        if ($tempResult -and $tempResult.Results) {
            # Re-number cascaded steps so they don't collide with our outer numbering
            $offset = 1
            foreach ($r in $tempResult.Results) {
                $r2 = [ordered]@{
                    Step = "2.$offset"; Label = "[temp-clean] $($r.Label)"; Count = $r.Count;
                    Bytes = $r.Bytes; Locked = $r.Locked; LockedDetails = $r.LockedDetails;
                    Status = $r.Status
                }
                $results += $r2
                $offset++
            }
            if ($tempResult.AllLocked) { $allLocked += $tempResult.AllLocked }
        }
    } catch {
        Write-Log "Step 2 cascade error (temp-clean): $($_.Exception.Message)" -Level "fail"
        $results += @{ Step = 2; Label = "Temp directories cascade"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "fail" }
    }
} else {
    Write-Log "Step 2: temp-clean cascade disabled -- skipping" -Level "skip"
}

# ==================== Step 3: Chocolatey cache ====================
if ($config.clean.clearChocoCache -and -not $NoChoco) {
    $chocoRes = Invoke-ChocoCacheClean -Config $config -LogMessages $logMessages -StepNum 3
    $results += $chocoRes
    if ($chocoRes.LockedDetails) { $allLocked += $chocoRes.LockedDetails }
} else {
    Write-Log "Step 3: Chocolatey cache cleanup -- skipped (NoChoco or disabled in config)" -Level "skip"
}

# ==================== Step 4: Event logs ====================
if ($config.clean.clearEventLogs) {
    $logCount = 0
    $logErrors = 0
    try {
        $logs = & wevtutil.exe el 2>$null
        foreach ($logName in $logs) {
            $trimmed = "$logName".Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            try {
                & wevtutil.exe cl "$trimmed" 2>$null
                $logCount++
            } catch {
                $logErrors++
            }
        }
        $status = if ($logErrors -eq 0) { "ok" } else { "warn" }
        Write-Log "Step 4 done: Cleared $logCount event log(s) (errors: $logErrors)" -Level $(if ($logErrors -eq 0) { "success" } else { "warn" })
        $results += @{ Step = 4; Label = "Windows event logs"; Count = $logCount; Bytes = 0; Locked = 0; LockedDetails = @(); Status = $status }
    } catch {
        Write-Log "Step 4 error: wevtutil failed: $($_.Exception.Message)" -Level "fail"
        $results += @{ Step = 4; Label = "Windows event logs"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "fail" }
    }
}

# ==================== Step 5: PSReadLine history ====================
if ($config.clean.clearPSReadLineHistory) {
    $historyPath = $null
    try {
        $opt = Get-PSReadLineOption -ErrorAction SilentlyContinue
        if ($opt) { $historyPath = $opt.HistorySavePath }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($historyPath)) {
        Write-Log "Step 5: PSReadLine history path not available -- skipped" -Level "skip"
        $results += @{ Step = 5; Label = "PSReadLine history"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "skip" }
    } else {
        $sizeBefore = if (Test-Path $historyPath) { (Get-Item $historyPath).Length } else { 0 }
        try {
            if (Test-Path $historyPath) {
                Remove-Item -LiteralPath $historyPath -Force -ErrorAction Stop
                Write-Log "Step 5 done: Removed PSReadLine history at $historyPath ($(Format-Bytes $sizeBefore) MB)" -Level "success"
                $results += @{ Step = 5; Label = "PSReadLine history"; Count = 1; Bytes = $sizeBefore; Locked = 0; LockedDetails = @(); Status = "ok" }
            } else {
                Write-Log "Step 5: PSReadLine history file not present at $historyPath" -Level "skip"
                $results += @{ Step = 5; Label = "PSReadLine history"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "skip" }
            }
        } catch {
            $reason = Get-LockReason -Ex $_.Exception
            Write-Log "Step 5 error at ${historyPath}: ${reason}" -Level "fail"
            $results += @{ Step = 5; Label = "PSReadLine history"; Count = 0; Bytes = 0; Locked = 1;
                           LockedDetails = @(@{ Path = $historyPath; Reason = $reason }); Status = "warn" }
            $allLocked += @{ Path = $historyPath; Reason = $reason }
        }
    }
}

# ==================== Step 6: Current session history ====================
if ($config.clean.clearCurrentSessionHistory) {
    try {
        Clear-History -ErrorAction SilentlyContinue
        Write-Log "Step 6 done: Cleared current session history" -Level "success"
    } catch {}
}

# ==================== Aggregate locked from outer steps ====================
foreach ($r in $results) {
    if ($r.LockedDetails -and $r.LockedDetails.Count -gt 0) {
        $allLocked += $r.LockedDetails
    }
}

# ==================== Summary ====================
Write-Host ""
Write-Host "  $($logMessages.clean.summaryHeader)" -ForegroundColor Cyan
Write-Host "  ================" -ForegroundColor DarkGray
$totalBytes  = 0
$totalCount  = 0
$totalLocked = 0
foreach ($r in $results) {
    $mb = Format-Bytes -Bytes $r.Bytes
    $statusColor = switch ($r.Status) {
        "ok"   { "Green" }
        "warn" { "Yellow" }
        "skip" { "DarkGray" }
        "fail" { "Red" }
        default { "Gray" }
    }
    Write-Host ("    Step {0,-5} {1,-46} items: {2,5}  freed: {3,8} MB  locked: {4,4}  [{5}]" `
        -f $r.Step, $r.Label, $r.Count, $mb, $r.Locked, $r.Status.ToUpper()) -ForegroundColor $statusColor
    $totalBytes  += $r.Bytes
    $totalCount  += $r.Count
    $totalLocked += $r.Locked
}
Write-Host ""
Write-Host ("    TOTAL freed: {0} MB ({1} GB)  items: {2}  locked: {3}" `
    -f (Format-Bytes $totalBytes), (Format-Gb $totalBytes), $totalCount, $totalLocked) -ForegroundColor Cyan

# ==================== Locked files section ====================
if ($allLocked.Count -gt 0) {
    # De-dup by path
    $unique = @{}
    foreach ($lk in $allLocked) {
        if (-not $unique.ContainsKey($lk.Path)) {
            $unique[$lk.Path] = $lk.Reason
        }
    }
    Write-Host ""
    Write-Host "  [ LOCKED FILES ] $($logMessages.clean.lockedHeader)" -ForegroundColor Yellow
    Write-Host "  -------------------------------------------------------------------------" -ForegroundColor DarkGray
    $limit = [int]$config.clean.lockedFilesMaxReport
    $shown = 0
    foreach ($k in $unique.Keys) {
        if ($shown -ge $limit) { break }
        Write-Host ("    {0}" -f $k) -ForegroundColor DarkYellow
        Write-Host ("        reason: {0}" -f $unique[$k]) -ForegroundColor DarkGray
        $shown++
    }
    if ($unique.Count -gt $limit) {
        $more = $unique.Count - $limit
        Write-Host ("    ... and {0} more locked file(s) not shown (limit: {1}). See log file for full list." -f $more, $limit) -ForegroundColor DarkGray
    }
}
Write-Host ""

$finalStatus = if ($totalLocked -eq 0) {
    if (($results | Where-Object { $_.Status -eq "fail" }).Count -gt 0) { "partial" } else { "ok" }
} else {
    "partial"
}
Save-LogFile -Status $finalStatus
exit 0
