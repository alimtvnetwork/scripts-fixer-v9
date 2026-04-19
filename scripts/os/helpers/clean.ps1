<#
.SYNOPSIS
    os clean -- Aggregate orchestrator (v0.41.0).

.DESCRIPTION
    Runs all 32 clean-categories helpers in catalog order. Each helper returns
    the standard result hashtable; the orchestrator accumulates them, then
    prints a per-category summary table + grand total + deduped LOCKED FILES.

    Flags:
      --yes                  Auto-confirm all destructive consent gates this run.
      --dry-run              Report only. No deletions, no service stops.
      --skip <a,b,c>         Skip listed categories.
      --only <a,b,c>         Run only listed categories.
      --bucket <A|B|...|G>   Run only categories in given bucket.
      --days <N>             Override age threshold for media subcommands (default 30).

    Destructive categories (recycle, ms-search, obs-recordings, windows-update-old)
    require typed-yes consent on first run; subsequent runs read consent from
    .resolved/os-clean-consent.json.

    CODE RED: every file/path failure logs the exact path + reason.
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Argv = @()
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$helpersDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptDir    = Split-Path -Parent $helpersDir
$sharedDir    = Join-Path (Split-Path -Parent $scriptDir) "shared"
$categoriesDir = Join-Path $helpersDir "clean-categories"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")
. (Join-Path $helpersDir "_common.ps1")
. (Join-Path $categoriesDir "_sweep.ps1")

$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")
$script:LogMessages = $logMessages

Initialize-Logging -ScriptName "OS Clean"

# ---------- Parse argv ----------
$dryRun = Test-DryRunSwitch -Argv $Argv
$autoYes = Test-YesSwitch -Argv $Argv
$days = Get-DaysArg -Argv $Argv -Default 30

function Get-MultiArg {
    param([string[]]$Argv, [string]$Name)
    if ($null -eq $Argv) { return @() }
    for ($i = 0; $i -lt $Argv.Count; $i++) {
        $t = "$($Argv[$i])".ToLower()
        if ($t -eq "--$Name" -and ($i + 1) -lt $Argv.Count) {
            return @($Argv[$i + 1].Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
        }
        if ($t -match "^--$Name=(.+)$") {
            return @($Matches[1].Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
        }
    }
    return @()
}

$skipList   = Get-MultiArg -Argv $Argv -Name "skip"
$onlyList   = Get-MultiArg -Argv $Argv -Name "only"
$bucketList = (Get-MultiArg -Argv $Argv -Name "bucket") | ForEach-Object { $_.ToUpper() }

# ---------- Catalog (32 categories in execution order) ----------
$catalog = @(
    # Bucket A -- System
    @{ Cat = "chkdsk";              Bucket = "A"; Helper = "chkdsk.ps1" },
    @{ Cat = "dns";                 Bucket = "A"; Helper = "dns.ps1" },
    @{ Cat = "recycle";             Bucket = "A"; Helper = "recycle.ps1" },
    @{ Cat = "delivery-opt";        Bucket = "A"; Helper = "delivery-opt.ps1" },
    @{ Cat = "error-reports";       Bucket = "A"; Helper = "error-reports.ps1" },
    @{ Cat = "event-logs";          Bucket = "A"; Helper = "event-logs.ps1" },
    @{ Cat = "etl";                 Bucket = "A"; Helper = "etl.ps1" },
    @{ Cat = "windows-logs";        Bucket = "A"; Helper = "windows-logs.ps1" },
    # Bucket B -- User shell
    @{ Cat = "notifications";       Bucket = "B"; Helper = "notifications.ps1" },
    @{ Cat = "explorer-mru";        Bucket = "B"; Helper = "explorer-mru.ps1" },
    @{ Cat = "recent-docs";         Bucket = "B"; Helper = "recent-docs.ps1" },
    @{ Cat = "jumplist";            Bucket = "B"; Helper = "jumplist.ps1" },
    @{ Cat = "thumbnails";          Bucket = "B"; Helper = "thumbnails.ps1" },
    @{ Cat = "ms-search";           Bucket = "B"; Helper = "ms-search.ps1" },
    # Bucket C -- Graphics / Web
    @{ Cat = "dx-shader";           Bucket = "C"; Helper = "dx-shader.ps1" },
    @{ Cat = "web-cache";           Bucket = "C"; Helper = "web-cache.ps1" },
    @{ Cat = "font-cache";          Bucket = "C"; Helper = "font-cache.ps1" },
    # Bucket D -- Browsers
    @{ Cat = "chrome";              Bucket = "D"; Helper = "chrome.ps1" },
    @{ Cat = "edge";                Bucket = "D"; Helper = "edge.ps1" },
    @{ Cat = "firefox";             Bucket = "D"; Helper = "firefox.ps1" },
    @{ Cat = "brave";               Bucket = "D"; Helper = "brave.ps1" },
    # Bucket E -- Apps
    @{ Cat = "clipchamp";           Bucket = "E"; Helper = "clipchamp.ps1" },
    @{ Cat = "vlc";                 Bucket = "E"; Helper = "vlc.ps1" },
    @{ Cat = "discord";             Bucket = "E"; Helper = "discord.ps1" },
    @{ Cat = "spotify";             Bucket = "E"; Helper = "spotify.ps1" },
    # Bucket F -- Dev tools
    @{ Cat = "vscode-cache";        Bucket = "F"; Helper = "vscode-cache.ps1" },
    @{ Cat = "npm-cache";           Bucket = "F"; Helper = "npm-cache.ps1" },
    @{ Cat = "pip-cache";           Bucket = "F"; Helper = "pip-cache.ps1" },
    @{ Cat = "docker-dangling";     Bucket = "F"; Helper = "docker-dangling.ps1" },
    # Bucket G -- Media / DISM
    # NOTE: obs-recordings + windows-update-old are SUBCOMMAND-ONLY by policy.
    #       Too risky for aggregate even with consent (deletes user video files
    #       / removes Windows update rollback). Run explicitly via
    #       `os clean-obs-recordings` or `os clean-windows-update-old`.
    @{ Cat = "steam-shader";        Bucket = "G"; Helper = "steam-shader.ps1" }
)

# ---------- Filter ----------
$selected = $catalog
if ($onlyList.Count -gt 0) {
    $selected = $catalog | Where-Object { $onlyList -contains $_.Cat }
}
if ($skipList.Count -gt 0) {
    $selected = $selected | Where-Object { $skipList -notcontains $_.Cat }
}
if ($bucketList.Count -gt 0) {
    $selected = $selected | Where-Object { $bucketList -contains $_.Bucket }
}

if ($selected.Count -eq 0) {
    Write-Host ""
    Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
    Write-Host "No categories selected after applying filters."
    Save-LogFile -Status "fail"
    exit 1
}

# ---------- Admin check ----------
$forwardArgs = @()
foreach ($a in $Argv) { $forwardArgs += $a }
$isAdminOk = Assert-Admin -ScriptPath $MyInvocation.MyCommand.Definition `
                          -ForwardArgs $forwardArgs -LogMessages $logMessages
if (-not $isAdminOk) {
    Save-LogFile -Status "fail"
    exit 1
}

# ---------- Banner ----------
$mode = if ($dryRun) { "DRY-RUN" } else { "LIVE" }
Write-Host ""
Write-Host "  OS Clean -- $mode -- $($selected.Count)/$($catalog.Count) categories" -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor DarkGray
if ($dryRun) {
    Write-Host "  [ INFO ] " -ForegroundColor Cyan -NoNewline
    Write-Host "DRY-RUN -- no deletions, no service stops, no consent file written"
}
Write-Host ""

# ---------- Initial confirmation (unless --yes / --dry-run) ----------
if (-not $dryRun -and -not $autoYes) {
    Write-Host "  This will run $($selected.Count) cleanup categories. Some are destructive." -ForegroundColor Yellow
    Write-Host "  Continue? [y/N]: " -ForegroundColor Yellow -NoNewline
    $reply = Read-Host
    if ($reply -notmatch '^(y|yes)$') {
        Write-Log "Cancelled by user." -Level "warn"
        Save-LogFile -Status "skip"
        exit 0
    }
}

# ---------- Run each category ----------
$results = @()
foreach ($entry in $selected) {
    $helperPath = Join-Path $categoriesDir $entry.Helper
    if (-not (Test-Path -LiteralPath $helperPath)) {
        Write-Log "Category helper missing for '$($entry.Cat)' at ${helperPath}" -Level "fail"
        $results += [ordered]@{
            Category = $entry.Cat; Label = $entry.Cat; Bucket = $entry.Bucket
            Destructive = $false; Count = 0; WouldCount = 0; Bytes = 0; WouldBytes = 0
            Locked = 0; LockedDetails = @(); Status = "fail"; Notes = @("Helper file missing: $helperPath")
        }
        continue
    }

    Write-Host "  >> $($entry.Cat)" -ForegroundColor White
    try {
        $r = & $helperPath -DryRun:$dryRun -Yes:$autoYes -Days $days
        if ($null -eq $r) {
            Write-Log "Category '$($entry.Cat)' returned null result" -Level "warn"
            continue
        }
        # Helpers may return arrays (PS auto-array); take last hashtable.
        if ($r -is [array]) {
            $r = $r | Where-Object { $_ -is [hashtable] -or $_ -is [System.Collections.Specialized.OrderedDictionary] } | Select-Object -Last 1
        }
        $results += $r
    } catch {
        Write-Log "Category '$($entry.Cat)' threw at ${helperPath}: $($_.Exception.Message)" -Level "fail"
        $results += [ordered]@{
            Category = $entry.Cat; Label = $entry.Cat; Bucket = $entry.Bucket
            Destructive = $false; Count = 0; WouldCount = 0; Bytes = 0; WouldBytes = 0
            Locked = 0; LockedDetails = @(); Status = "fail"; Notes = @("Exception: $($_.Exception.Message)")
        }
    }
}

# ---------- Summary table ----------
Write-Host ""
Write-Host "  OS Clean Summary ($mode)" -ForegroundColor Cyan
Write-Host "  =========================" -ForegroundColor DarkGray
$totalBytes  = 0; $totalCount  = 0; $totalLocked = 0
$totalWouldBytes = 0; $totalWouldCount = 0
$allLocked   = @()
foreach ($r in $results) {
    $statusColor = switch ($r.Status) {
        "ok"      { "Green" }
        "warn"    { "Yellow" }
        "skip"    { "DarkGray" }
        "fail"    { "Red" }
        "dry-run" { "Cyan" }
        default   { "Gray" }
    }
    if ($dryRun) {
        $mb = [Math]::Round(($r.WouldBytes / 1MB), 2)
        Write-Host ("    [{0}] {1,-22} would-items: {2,5}  would-free: {3,8} MB  [{4}]" `
            -f $r.Bucket, $r.Category, $r.WouldCount, $mb, $r.Status.ToUpper()) -ForegroundColor $statusColor
        $totalWouldBytes += [long]$r.WouldBytes
        $totalWouldCount += [int]$r.WouldCount
    } else {
        $mb = [Math]::Round(($r.Bytes / 1MB), 2)
        Write-Host ("    [{0}] {1,-22} items: {2,5}  freed: {3,8} MB  locked: {4,4}  [{5}]" `
            -f $r.Bucket, $r.Category, $r.Count, $mb, $r.Locked, $r.Status.ToUpper()) -ForegroundColor $statusColor
        $totalBytes  += [long]$r.Bytes
        $totalCount  += [int]$r.Count
        $totalLocked += [int]$r.Locked
    }
    if ($r.LockedDetails -and $r.LockedDetails.Count -gt 0) {
        foreach ($lk in $r.LockedDetails) { $allLocked += $lk }
    }
}

Write-Host ""
if ($dryRun) {
    Write-Host ("    DRY-RUN TOTAL would-free: {0} MB ({1} GB)  would-items: {2}" `
        -f ([Math]::Round($totalWouldBytes/1MB,2)), ([Math]::Round($totalWouldBytes/1GB,2)), $totalWouldCount) -ForegroundColor Cyan
} else {
    Write-Host ("    TOTAL freed: {0} MB ({1} GB)  items: {2}  locked: {3}" `
        -f ([Math]::Round($totalBytes/1MB,2)), ([Math]::Round($totalBytes/1GB,2)), $totalCount, $totalLocked) -ForegroundColor Cyan
}

# ---------- Locked files (deduped) ----------
if ($allLocked.Count -gt 0) {
    $unique = @{}
    foreach ($lk in $allLocked) {
        if (-not $unique.ContainsKey($lk.Path)) { $unique[$lk.Path] = $lk.Reason }
    }
    Write-Host ""
    Write-Host "  [ LOCKED FILES ] $($logMessages.clean.lockedHeader)" -ForegroundColor Yellow
    Write-Host "  ----------------------------------------------------------------------" -ForegroundColor DarkGray
    $limit = 50
    $shown = 0
    foreach ($k in $unique.Keys) {
        if ($shown -ge $limit) { break }
        Write-Host ("    {0}" -f $k) -ForegroundColor DarkYellow
        Write-Host ("        reason: {0}" -f $unique[$k]) -ForegroundColor DarkGray
        $shown++
    }
    if ($unique.Count -gt $limit) {
        Write-Host ("    ... and {0} more locked file(s) -- see log" -f ($unique.Count - $limit)) -ForegroundColor DarkGray
    }
}

Write-Host ""

$finalStatus = "ok"
$failCount = ($results | Where-Object { $_.Status -eq "fail" }).Count
if ($failCount -gt 0) { $finalStatus = "partial" }
elseif ($totalLocked -gt 0) { $finalStatus = "partial" }
elseif ($dryRun) { $finalStatus = "ok" }

Save-LogFile -Status $finalStatus
exit 0
