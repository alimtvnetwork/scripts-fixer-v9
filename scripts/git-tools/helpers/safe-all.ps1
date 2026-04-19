<#
.SYNOPSIS
    Adds safe.directory entries to global gitconfig.

.DESCRIPTION
    Two modes:
      Default (wildcard): adds safe.directory='*' once (idempotent).
      -Scan <path>: walks <path> recursively (up to -Depth, default 4),
                    finds every .git directory, and adds the parent repo
                    path to global safe.directory entries (idempotent).

    Fixes "fatal: detected dubious ownership in repository" warnings on
    Windows when repos live on a different drive / NTFS owner mismatch.
#>
param(
    [string]$Scan,
    [int]$Depth = 4
)

$ErrorActionPreference = "Stop"
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$gitToolsDir = Split-Path -Parent $scriptDir
$sharedDir   = Join-Path (Split-Path -Parent $gitToolsDir) "shared"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")

$logMessages = Import-JsonConfig (Join-Path $gitToolsDir "log-messages.json")
Initialize-Logging -ScriptName "git-safe-all"

# -- Pre-flight: git must be available --------------------------------
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$isGitMissing = $null -eq $gitCmd
if ($isGitMissing) {
    Write-Host "  $($logMessages.status.fail) " -ForegroundColor Red -NoNewline
    Write-Host $logMessages.messages.gitMissing
    Save-LogFile -Status "fail"
    exit 1
}

# -- Helper: read existing safe.directory entries ---------------------
function Get-SafeDirectoryEntries {
    $raw = & git config --global --get-all safe.directory 2>$null
    $hasOutput = $null -ne $raw
    if (-not $hasOutput) { return @() }
    return @($raw)
}

$hasScanArg = -not [string]::IsNullOrWhiteSpace($Scan)

if (-not $hasScanArg) {
    # ── Wildcard mode ────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  Git safe.directory -- wildcard mode" -ForegroundColor Cyan
    Write-Host "  ===================================" -ForegroundColor DarkGray
    Write-Host ""

    $existing = Get-SafeDirectoryEntries
    $hasWildcard = $existing -contains '*'

    if ($hasWildcard) {
        Write-Host "  $($logMessages.status.skip) " -ForegroundColor Yellow -NoNewline
        Write-Host $logMessages.messages.wildcardAlready
    } else {
        & git config --global --add safe.directory '*'
        Write-Host "  $($logMessages.status.added) " -ForegroundColor Green -NoNewline
        Write-Host $logMessages.messages.wildcardAdded
    }
    Write-Host ""
    Save-LogFile -Status "ok"
    exit 0
}

# ── Scan mode ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Git safe.directory -- scan mode" -ForegroundColor Cyan
Write-Host "  ===============================" -ForegroundColor DarkGray
Write-Host ""

$isScanPathMissing = -not (Test-Path $Scan)
if ($isScanPathMissing) {
    $msg = $logMessages.messages.scanPathMissing -replace '\{path\}', $Scan
    Write-Host "  $($logMessages.status.fail) " -ForegroundColor Red -NoNewline
    Write-Host $msg
    Save-LogFile -Status "fail"
    exit 1
}

$startMsg = $logMessages.messages.scanStart -replace '\{path\}', $Scan -replace '\{depth\}', "$Depth"
Write-Host "  $($logMessages.status.scan) " -ForegroundColor Cyan -NoNewline
Write-Host $startMsg

$sw = [System.Diagnostics.Stopwatch]::StartNew()

$gitDirs = @(Get-ChildItem -Path $Scan -Filter ".git" -Directory -Recurse -Depth $Depth -Force -ErrorAction SilentlyContinue)
$totalFound = $gitDirs.Count

$hasNoRepos = $totalFound -eq 0
if ($hasNoRepos) {
    $msg = $logMessages.messages.scanNoRepos -replace '\{path\}', $Scan
    Write-Host "  $($logMessages.status.warn) " -ForegroundColor Yellow -NoNewline
    Write-Host $msg
    Save-LogFile -Status "ok"
    exit 0
}

# Snapshot existing entries ONCE -- avoids per-repo `git config` re-read
$existingEntries = Get-SafeDirectoryEntries
$existingSet = @{}
foreach ($e in $existingEntries) { $existingSet[$e] = $true }

$added   = 0
$skipped = 0

foreach ($gitDir in $gitDirs) {
    # Repo root is the parent of .git -- normalize to forward slashes for git.
    $repoPath = $gitDir.Parent.FullName -replace '\\', '/'

    $isAlreadyTrusted = $existingSet.ContainsKey($repoPath)
    if ($isAlreadyTrusted) {
        $skipped++
        continue
    }

    & git config --global --add safe.directory $repoPath
    $added++
    $existingSet[$repoPath] = $true
}

$sw.Stop()
$seconds = "{0:N1}" -f $sw.Elapsed.TotalSeconds

$summary = $logMessages.messages.scanSummary `
    -replace '\{added\}',   "$added" `
    -replace '\{skipped\}', "$skipped" `
    -replace '\{total\}',   "$totalFound" `
    -replace '\{seconds\}', $seconds

Write-Host ""
Write-Host "  $($logMessages.status.ok) " -ForegroundColor Green -NoNewline
Write-Host $summary
Write-Host ""

Save-LogFile -Status "ok"
exit 0
