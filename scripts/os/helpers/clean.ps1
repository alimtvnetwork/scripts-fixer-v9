<#
.SYNOPSIS
    os clean -- Windows housekeeping (SoftwareDistribution, TEMP, event logs, PSReadLine).
#>
param(
    [switch]$Yes,
    [switch]$Force,
    [switch]$IncludeWindowsTemp
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$helpersDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptDir  = Split-Path -Parent $helpersDir
$sharedDir  = Join-Path (Split-Path -Parent $scriptDir) "shared"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")
. (Join-Path $helpersDir "_common.ps1")

$config      = Import-JsonConfig (Join-Path $scriptDir "config.json")
$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")
$script:LogMessages = $logMessages

Initialize-Logging -ScriptName "OS Clean"

# Forward original switches if we have to re-launch elevated
$forwardArgs = @()
if ($Yes)                { $forwardArgs += "-Yes" }
if ($Force)              { $forwardArgs += "-Force" }
if ($IncludeWindowsTemp) { $forwardArgs += "-IncludeWindowsTemp" }

$isAdminOk = Assert-Admin -ScriptPath $MyInvocation.MyCommand.Definition `
                          -ForwardArgs $forwardArgs `
                          -LogMessages $logMessages
if (-not $isAdminOk) {
    Save-LogFile -Status "fail"
    exit 1
}

$autoYes = $Yes -or $Force
$confirmed = Confirm-Action -Prompt "This will wipe SoftwareDistribution\Download, %TEMP%, event logs, and PSReadLine history. Continue? [y/N]: " -AutoYes:$autoYes
if (-not $confirmed) {
    Write-Log $logMessages.messages.userCancelled -Level "warn"
    Save-LogFile -Status "skip"
    exit 0
}

$results = @()

function Get-DirSize {
    param([string]$Path)
    try {
        $isPathPresent = Test-Path $Path
        if (-not $isPathPresent) { return 0 }
        $sum = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [long]$sum
    } catch {
        return 0
    }
}

function Clear-FolderContents {
    param([string]$Path, [string]$Label, [int]$StepNum)

    $isPathMissing = -not (Test-Path $Path)
    if ($isPathMissing) {
        Write-Log "Step ${StepNum}: $Label -- path not present: $Path" -Level "skip"
        return @{ Step = $StepNum; Label = $Label; Count = 0; Bytes = 0; Status = "skip"; Errors = 0 }
    }

    $sizeBefore = Get-DirSize -Path $Path
    $items      = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue
    $beforeCount = ($items | Measure-Object).Count
    $errCount = 0

    foreach ($it in $items) {
        try {
            Remove-Item -Path $it.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            $errCount++
            Write-Log "Step ${StepNum} error at $($it.FullName): $($_.Exception.Message)" -Level "warn"
        }
    }

    $sizeAfter = Get-DirSize -Path $Path
    $freed = [long]([Math]::Max(0, $sizeBefore - $sizeAfter))
    $afterCount = (Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    $removed = [Math]::Max(0, $beforeCount - $afterCount)

    $status = if ($errCount -eq 0) { "ok" } else { "warn" }
    $mb = Format-Bytes -Bytes $freed
    Write-Log "Step ${StepNum} done: $Label -- removed $removed item(s), freed $mb MB (errors: $errCount)" -Level $(if ($errCount -eq 0) { "success" } else { "warn" })
    return @{ Step = $StepNum; Label = $Label; Count = $removed; Bytes = $freed; Status = $status; Errors = $errCount }
}

# Step 1: SoftwareDistribution\Download
$results += Clear-FolderContents -Path $config.clean.softwareDistribution -Label "Windows Update cache" -StepNum 1

# Step 2: $env:TEMP
$tempPath = [Environment]::GetEnvironmentVariable($config.clean.tempEnvVar)
if ([string]::IsNullOrWhiteSpace($tempPath)) { $tempPath = $env:TEMP }
$results += Clear-FolderContents -Path $tempPath -Label "User TEMP folder" -StepNum 2

# Step 2b (optional): C:\Windows\Temp
if ($IncludeWindowsTemp) {
    $results += Clear-FolderContents -Path $config.clean.windowsTemp -Label "Windows TEMP folder" -StepNum 3
} else {
    Write-Log "Step 3: Windows TEMP -- skipped (use -IncludeWindowsTemp to enable)" -Level "skip"
    $results += @{ Step = 3; Label = "Windows TEMP folder"; Count = 0; Bytes = 0; Status = "skip"; Errors = 0 }
}

# Step 4: Event logs
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
        $results += @{ Step = 4; Label = "Windows event logs"; Count = $logCount; Bytes = 0; Status = $status; Errors = $logErrors }
    } catch {
        Write-Log "Step 4 error: wevtutil failed: $($_.Exception.Message)" -Level "fail"
        $results += @{ Step = 4; Label = "Windows event logs"; Count = 0; Bytes = 0; Status = "fail"; Errors = 1 }
    }
}

# Step 5: PSReadLine history
if ($config.clean.clearPSReadLineHistory) {
    $historyPath = $null
    try {
        $opt = Get-PSReadLineOption -ErrorAction SilentlyContinue
        if ($opt) { $historyPath = $opt.HistorySavePath }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($historyPath)) {
        Write-Log "Step 5: PSReadLine history path not available -- skipped" -Level "skip"
        $results += @{ Step = 5; Label = "PSReadLine history"; Count = 0; Bytes = 0; Status = "skip"; Errors = 0 }
    } else {
        $sizeBefore = if (Test-Path $historyPath) { (Get-Item $historyPath).Length } else { 0 }
        try {
            if (Test-Path $historyPath) {
                Remove-Item -Path $historyPath -Force -ErrorAction Stop
                Write-Log "Step 5 done: Removed PSReadLine history at $historyPath ($(Format-Bytes $sizeBefore) MB)" -Level "success"
                $results += @{ Step = 5; Label = "PSReadLine history"; Count = 1; Bytes = $sizeBefore; Status = "ok"; Errors = 0 }
            } else {
                Write-Log "Step 5: PSReadLine history file not present at $historyPath" -Level "skip"
                $results += @{ Step = 5; Label = "PSReadLine history"; Count = 0; Bytes = 0; Status = "skip"; Errors = 0 }
            }
        } catch {
            Write-Log "Step 5 error at ${historyPath}: $($_.Exception.Message)" -Level "fail"
            $results += @{ Step = 5; Label = "PSReadLine history"; Count = 0; Bytes = 0; Status = "fail"; Errors = 1 }
        }
    }
}

if ($config.clean.clearCurrentSessionHistory) {
    try {
        Clear-History -ErrorAction SilentlyContinue
        Write-Log "Step 6 done: Cleared current session history" -Level "success"
    } catch {}
}

# Summary
Write-Host ""
Write-Host "  OS Clean Summary" -ForegroundColor Cyan
Write-Host "  ================" -ForegroundColor DarkGray
$totalBytes = 0
$totalErrors = 0
foreach ($r in $results) {
    $mb = Format-Bytes -Bytes $r.Bytes
    $statusColor = switch ($r.Status) {
        "ok"   { "Green" }
        "warn" { "Yellow" }
        "skip" { "DarkGray" }
        "fail" { "Red" }
        default { "Gray" }
    }
    Write-Host ("    Step {0,-2} {1,-30} items: {2,5}  freed: {3,8} MB  [{4}]" -f $r.Step, $r.Label, $r.Count, $mb, $r.Status.ToUpper()) -ForegroundColor $statusColor
    $totalBytes  += $r.Bytes
    $totalErrors += $r.Errors
}
Write-Host ""
Write-Host ("    TOTAL freed: {0} MB ({1} GB)  errors: {2}" -f (Format-Bytes $totalBytes), (Format-Gb $totalBytes), $totalErrors) -ForegroundColor Cyan
Write-Host ""

$finalStatus = if ($totalErrors -eq 0) { "ok" } else { "partial" }
Save-LogFile -Status $finalStatus
exit 0
