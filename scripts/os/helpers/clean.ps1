<#
.SYNOPSIS
    os clean -- Full Windows housekeeping sweep (Option B: independent of temp-clean).

.DESCRIPTION
    Wipes (each step is its own try/catch with locked-file accumulation):
      Step 1. C:\Windows\SoftwareDistribution\Download  (Windows Update cache)
      Step 2. $env:TEMP                                 (current user temp)
      Step 3. C:\Windows\Temp                           (system temp)
      Step 4. $env:LOCALAPPDATA\Temp                    (skipped if same as Step 2)
      Step 5. Per-user Temp dirs under C:\Users\*\AppData\Local\Temp
              (excludes Public/Default/Default User/All Users/WDAGUtilityAccount + current user)
      Step 6. Chocolatey cache (lib-bad, lib-bkp, *.backup, *.nupkg cache,
              %TEMP%\chocolatey, runs choco-cleaner if installed).
              LIVE choco install (bin/, lib/<pkg>/tools, config, logs) is untouched.
      Step 7. All Windows event logs (wevtutil cl)
      Step 8. PSReadLine command history file
      Step 9. Current session command history (Clear-History)

    NOTE: This is INDEPENDENT of `os temp-clean` -- both helpers contain their
    own temp-sweep logic so each can be run / maintained / debugged in isolation.
    Drift risk is accepted in exchange for no internal coupling.

    Locked files are CAUGHT (not crashed on), accumulated, and reported in a
    dedicated [ LOCKED FILES ] section at the end with the OS reason.

    CODE RED: every file/path failure logs the exact path + reason.
#>
param(
    [switch]$Yes,
    [switch]$Force,
    [switch]$IncludeWindowsTemp,   # legacy: kept for back-compat (always-on now).
    [switch]$NoChoco,
    [switch]$NoTemp                # NEW: opt-out of temp dirs entirely (use `os temp-clean` instead).
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
if ($NoTemp)             { $forwardArgs += "-NoTemp" }

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

# ---------- Local helpers (independent copy -- Option B) ----------
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
    if ($msg -match "Could not find")                       { return "vanished mid-sweep (already gone)" }
    return $msg.Split("`n")[0].Trim()
}

# Top-level contents wipe (used by Step 1 -- SoftwareDistribution).
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

# Recursive depth-first sweep (used by temp dir steps).
function Invoke-DeepTempSweep {
    param([string]$Path, [string]$Label, [int]$StepNum)

    $r = [ordered]@{
        Step = $StepNum; Label = $Label; Path = $Path; Count = 0; Bytes = 0;
        Locked = 0; LockedDetails = @(); Status = "ok"
    }

    if (-not (Test-Path $Path)) {
        Write-Log "Step ${StepNum}: ${Label} -- path not present: ${Path}" -Level "skip"
        $r.Status = "skip"
        return $r
    }

    $sizeBefore = Get-DirSize -Path $Path

    $allItems = @()
    try {
        $allItems = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Step ${StepNum} enumerate failed at ${Path}: $($_.Exception.Message)" -Level "warn"
    }

    $files = $allItems | Where-Object { -not $_.PSIsContainer }
    $dirs  = $allItems | Where-Object {  $_.PSIsContainer } | Sort-Object { $_.FullName.Length } -Descending

    $removed = 0
    foreach ($f in $files) {
        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $removed++
        } catch {
            $reason = Get-LockReason -Ex $_.Exception
            $r.Locked++
            $r.LockedDetails += @{ Path = $f.FullName; Reason = $reason }
            Write-Log "Step ${StepNum} locked at $($f.FullName): ${reason}" -Level "warn"
        }
    }
    foreach ($d in $dirs) {
        try {
            if (Test-Path $d.FullName) {
                Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop
                $removed++
            }
        } catch {
            $reason = Get-LockReason -Ex $_.Exception
            $r.Locked++
            $r.LockedDetails += @{ Path = $d.FullName; Reason = $reason }
            Write-Log "Step ${StepNum} locked dir at $($d.FullName): ${reason}" -Level "warn"
        }
    }

    $sizeAfter = Get-DirSize -Path $Path
    $r.Bytes = [long]([Math]::Max(0, $sizeBefore - $sizeAfter))
    $r.Count = $removed
    if ($r.Locked -gt 0) { $r.Status = "warn" }

    $mb = Format-Bytes -Bytes $r.Bytes
    Write-Log "Step ${StepNum} done: ${Label} -- removed ${removed} item(s), freed ${mb} MB, locked $($r.Locked)" -Level $(if ($r.Locked -eq 0) { "success" } else { "warn" })
    return $r
}

# ==================== Step 1: Windows Update cache ====================
$results += Clear-FolderContents -Path $config.clean.softwareDistribution -Label "Windows Update cache" -StepNum 1

# ==================== Steps 2-5: temp dirs (inline, independent of temp-clean) ====================
if ($NoTemp) {
    Write-Log "Steps 2-5: temp directory sweep -- skipped (-NoTemp). Use 'os temp-clean' separately if needed." -Level "skip"
} else {
    # Step 2: $env:TEMP
    $tempPath = [Environment]::GetEnvironmentVariable($config.clean.tempEnvVar)
    if ([string]::IsNullOrWhiteSpace($tempPath)) { $tempPath = $env:TEMP }
    $results += Invoke-DeepTempSweep -Path $tempPath -Label "User TEMP ($tempPath)" -StepNum 2

    # Step 3: C:\Windows\Temp
    $results += Invoke-DeepTempSweep -Path $config.clean.windowsTemp -Label "Windows TEMP" -StepNum 3

    # Step 4: $env:LOCALAPPDATA\Temp (only if different from Step 2)
    $localTemp = $null
    $lad = [Environment]::GetEnvironmentVariable("LOCALAPPDATA")
    if (-not [string]::IsNullOrWhiteSpace($lad)) {
        $localTemp = Join-Path $lad "Temp"
    }
    if ($localTemp -and ($localTemp.ToLower() -ne $tempPath.ToLower())) {
        $results += Invoke-DeepTempSweep -Path $localTemp -Label "LocalAppData\Temp" -StepNum 4
    } else {
        Write-Log "Step 4: LocalAppData\Temp -- same path as user TEMP, skipped to avoid double-sweep" -Level "skip"
        $results += @{ Step = 4; Label = "LocalAppData\Temp (same as user TEMP)"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "skip" }
    }

    # Step 5: per-user Temp sweep
    $perUserRoot = "C:\Users"
    if (Test-Path $perUserRoot) {
        $userDirs = @()
        try {
            $userDirs = Get-ChildItem -Path $perUserRoot -Directory -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notin @("Public", "Default", "Default User", "All Users", "WDAGUtilityAccount") -and $_.Name -ine $env:USERNAME }
        } catch {}

        $sub = 1
        foreach ($u in $userDirs) {
            $perTemp = Join-Path $u.FullName "AppData\Local\Temp"
            if (-not (Test-Path $perTemp)) { continue }
            $stepLabel = "5.$sub"
            $r = Invoke-DeepTempSweep -Path $perTemp -Label "Per-user Temp: $($u.Name)" -StepNum $stepLabel
            $results += $r
            $sub++
        }
        if ($sub -eq 1) {
            Write-Log "Step 5: per-user Temp sweep -- no other user profiles found under ${perUserRoot}" -Level "skip"
            $results += @{ Step = 5; Label = "Per-user Temp (none found)"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "skip" }
        }
    }
}

# ==================== Step 6: Chocolatey cache ====================
if ($config.clean.clearChocoCache -and -not $NoChoco) {
    $chocoRes = Invoke-ChocoCacheClean -Config $config -LogMessages $logMessages -StepNum 6
    $results += $chocoRes
} else {
    Write-Log "Step 6: Chocolatey cache cleanup -- skipped (-NoChoco or disabled in config)" -Level "skip"
    $results += @{ Step = 6; Label = "Chocolatey cache (skipped)"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "skip" }
}

# ==================== Step 7: Event logs ====================
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
        Write-Log "Step 7 done: Cleared $logCount event log(s) (errors: $logErrors)" -Level $(if ($logErrors -eq 0) { "success" } else { "warn" })
        $results += @{ Step = 7; Label = "Windows event logs"; Count = $logCount; Bytes = 0; Locked = 0; LockedDetails = @(); Status = $status }
    } catch {
        Write-Log "Step 7 error: wevtutil failed: $($_.Exception.Message)" -Level "fail"
        $results += @{ Step = 7; Label = "Windows event logs"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "fail" }
    }
}

# ==================== Step 8: PSReadLine history ====================
if ($config.clean.clearPSReadLineHistory) {
    $historyPath = $null
    try {
        $opt = Get-PSReadLineOption -ErrorAction SilentlyContinue
        if ($opt) { $historyPath = $opt.HistorySavePath }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($historyPath)) {
        Write-Log "Step 8: PSReadLine history path not available -- skipped" -Level "skip"
        $results += @{ Step = 8; Label = "PSReadLine history"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "skip" }
    } else {
        $sizeBefore = if (Test-Path $historyPath) { (Get-Item $historyPath).Length } else { 0 }
        try {
            if (Test-Path $historyPath) {
                Remove-Item -LiteralPath $historyPath -Force -ErrorAction Stop
                Write-Log "Step 8 done: Removed PSReadLine history at $historyPath ($(Format-Bytes $sizeBefore) MB)" -Level "success"
                $results += @{ Step = 8; Label = "PSReadLine history"; Count = 1; Bytes = $sizeBefore; Locked = 0; LockedDetails = @(); Status = "ok" }
            } else {
                Write-Log "Step 8: PSReadLine history file not present at $historyPath" -Level "skip"
                $results += @{ Step = 8; Label = "PSReadLine history"; Count = 0; Bytes = 0; Locked = 0; LockedDetails = @(); Status = "skip" }
            }
        } catch {
            $reason = Get-LockReason -Ex $_.Exception
            Write-Log "Step 8 error at ${historyPath}: ${reason}" -Level "fail"
            $results += @{ Step = 8; Label = "PSReadLine history"; Count = 0; Bytes = 0; Locked = 1;
                           LockedDetails = @(@{ Path = $historyPath; Reason = $reason }); Status = "warn" }
        }
    }
}

# ==================== Step 9: Current session history ====================
if ($config.clean.clearCurrentSessionHistory) {
    try {
        Clear-History -ErrorAction SilentlyContinue
        Write-Log "Step 9 done: Cleared current session history" -Level "success"
    } catch {}
}

# ==================== Aggregate locked from all steps ====================
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
