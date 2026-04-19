<#
.SYNOPSIS
    Lists all safe.directory entries from global gitconfig.

.DESCRIPTION
    Audit helper. Reads `git config --global --get-all safe.directory`,
    sorts and dedupes entries, and prints a breakdown:
      * wildcard ('*') presence
      * per-repo entries (sorted)
      * count of duplicates removed
      * grand total

    Useful for verifying what `gsa` / `gsa --scan` has trusted over time.
#>
param()

$ErrorActionPreference = "Stop"
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$gitToolsDir = Split-Path -Parent $scriptDir
$sharedDir   = Join-Path (Split-Path -Parent $gitToolsDir) "shared"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")

$logMessages = Import-JsonConfig (Join-Path $gitToolsDir "log-messages.json")
Initialize-Logging -ScriptName "git-safe-list"

# -- Pre-flight: git must be available --------------------------------
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$isGitMissing = $null -eq $gitCmd
if ($isGitMissing) {
    Write-Host "  $($logMessages.status.fail) " -ForegroundColor Red -NoNewline
    Write-Host $logMessages.messages.gitMissing
    Save-LogFile -Status "fail"
    exit 1
}

Write-Host ""
Write-Host "  $($logMessages.messages.listHeader)" -ForegroundColor Cyan
Write-Host "  =========================================" -ForegroundColor DarkGray
Write-Host ""

$raw = & git config --global --get-all safe.directory 2>$null
$hasOutput = $null -ne $raw -and @($raw).Count -gt 0

if (-not $hasOutput) {
    Write-Host "  $($logMessages.status.warn) " -ForegroundColor Yellow -NoNewline
    Write-Host $logMessages.messages.listEmpty
    Write-Host ""
    Save-LogFile -Status "ok"
    exit 0
}

$allEntries = @($raw)
$totalRaw   = $allEntries.Count

# Dedupe + sort
$uniqueEntries = $allEntries | Sort-Object -Unique
$uniqueCount   = @($uniqueEntries).Count
$duplicates    = $totalRaw - $uniqueCount

# Split wildcard vs per-repo
$wildcardEntries = @($uniqueEntries | Where-Object { $_ -eq '*' })
$repoEntries     = @($uniqueEntries | Where-Object { $_ -ne '*' })
$wildcardCount   = $wildcardEntries.Count
$repoCount       = $repoEntries.Count

$hasWildcard = $wildcardCount -gt 0
if ($hasWildcard) {
    Write-Host "  $($logMessages.status.ok) " -ForegroundColor Green -NoNewline
    Write-Host $logMessages.messages.listWildcard
} else {
    Write-Host "  $($logMessages.status.info) " -ForegroundColor DarkGray -NoNewline
    Write-Host $logMessages.messages.listNoWildcard
}
Write-Host ""

$hasRepoEntries = $repoCount -gt 0
if ($hasRepoEntries) {
    Write-Host "  Per-repo entries ($repoCount):" -ForegroundColor Cyan
    Write-Host "  -------------------------------" -ForegroundColor DarkGray
    $idx = 1
    foreach ($entry in $repoEntries) {
        $num = "{0,4}." -f $idx
        Write-Host "  $num " -ForegroundColor DarkGray -NoNewline
        Write-Host $entry -ForegroundColor White
        $idx++
    }
    Write-Host ""
}

$summary = $logMessages.messages.listSummary `
    -replace '\{total\}',      "$uniqueCount" `
    -replace '\{wildcard\}',   "$wildcardCount" `
    -replace '\{repos\}',      "$repoCount" `
    -replace '\{duplicates\}', "$duplicates"

Write-Host "  $($logMessages.status.ok) " -ForegroundColor Green -NoNewline
Write-Host $summary
Write-Host ""

Save-LogFile -Status "ok"
exit 0
