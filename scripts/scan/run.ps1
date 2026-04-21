# --------------------------------------------------------------------------
#  Scan -- VS Code Project Manager Sync
#
#  Walks a root directory, discovers project folders, and upserts them into
#  the VS Code Project Manager extension's projects.json file.
#
#  This command NEVER opens VS Code. It only syncs the JSON file.
# --------------------------------------------------------------------------
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sharedDir = Join-Path (Split-Path -Parent $scriptDir) "shared"

# -- Dot-source shared helpers ------------------------------------------------
. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "git-pull.ps1")

# -- Dot-source script helpers ------------------------------------------------
. (Join-Path $scriptDir "helpers\vscode-projects.ps1")
. (Join-Path $scriptDir "helpers\walker.ps1")

# -- Load config & log messages ----------------------------------------------
$config      = Import-JsonConfig (Join-Path $scriptDir "config.json")
$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
$argList = @()
if ($null -ne $Args) { $argList = @($Args) }

$rootPath       = ""
$customJsonPath = ""
$depth          = [int]$config.scan.defaultDepth
$isDryRun       = $false
$includeHidden  = [bool]$config.scan.includeHidden
$showHelp       = $false

$i = 0
while ($i -lt $argList.Count) {
    $a = $argList[$i]
    $low = "$a".Trim().ToLower()

    if ($low -in @("--help", "-help", "-h", "/?", "help")) {
        $showHelp = $true
        $i++; continue
    }
    if ($low -in @("--dry-run", "-dryrun", "--dryrun", "-dry-run")) {
        $isDryRun = $true
        $i++; continue
    }
    if ($low -in @("--include-hidden", "-include-hidden", "--includehidden")) {
        $includeHidden = $true
        $i++; continue
    }
    if ($low -eq "--depth" -or $low -eq "-depth") {
        if (($i + 1) -lt $argList.Count) {
            [int]::TryParse($argList[$i + 1], [ref]$depth) | Out-Null
            $i += 2; continue
        }
        $i++; continue
    }
    if ($low.StartsWith("--depth=")) {
        $val = $a.Substring($a.IndexOf("=") + 1)
        [int]::TryParse($val, [ref]$depth) | Out-Null
        $i++; continue
    }
    if ($low -eq "--json" -or $low -eq "-json") {
        if (($i + 1) -lt $argList.Count) {
            $customJsonPath = $argList[$i + 1]
            $i += 2; continue
        }
        $i++; continue
    }
    if ($low.StartsWith("--json=")) {
        $customJsonPath = $a.Substring($a.IndexOf("=") + 1)
        $i++; continue
    }

    # First non-flag positional = root path
    $isFlag = $low.StartsWith("-")
    if (-not $isFlag -and [string]::IsNullOrWhiteSpace($rootPath)) {
        $rootPath = $a
    }
    $i++
}

# --------------------------------------------------------------------------
# Help
# --------------------------------------------------------------------------
if ($showHelp) {
    Write-Host ""
    Write-Host "  $($logMessages.scriptName)" -ForegroundColor Cyan
    Write-Host "  $('=' * $logMessages.scriptName.Length)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $($logMessages.helpHeader)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  USAGE" -ForegroundColor Yellow
    foreach ($u in $logMessages.helpUsage) {
        Write-Host "    $u" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  FLAGS" -ForegroundColor Yellow
    Write-Host "    --depth N          Max recursion depth (default $($config.scan.defaultDepth))" -ForegroundColor DarkGray
    Write-Host "    --dry-run          Preview adds/updates; write nothing" -ForegroundColor DarkGray
    Write-Host "    --json <path>      Override target projects.json (testing)" -ForegroundColor DarkGray
    Write-Host "    --include-hidden   Walk into folders starting with '.'" -ForegroundColor DarkGray
    Write-Host "    --help             Show this help" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  NOTES" -ForegroundColor Yellow
    Write-Host "    - This command never opens VS Code." -ForegroundColor DarkGray
    Write-Host "    - Match key is rootPath (case-insensitive on Windows)." -ForegroundColor DarkGray
    Write-Host "    - Existing entries are preserved; new ones are appended." -ForegroundColor DarkGray
    Write-Host ""
    return
}

# --------------------------------------------------------------------------
# Banner + logging
# --------------------------------------------------------------------------
Write-Banner -Title $logMessages.scriptName
Initialize-Logging -ScriptName $logMessages.scriptName

try {

    # -- Git pull (skipped automatically when run from root dispatcher) --
    Invoke-GitPull

    # -- Resolve root path --
    $hasRoot = -not [string]::IsNullOrWhiteSpace($rootPath)
    if (-not $hasRoot) {
        $rootPath = (Get-Location).Path
    }
    try {
        $rootPath = (Resolve-Path -LiteralPath $rootPath -ErrorAction Stop).Path
    } catch {
        Write-Log ($logMessages.messages.rootMissing -replace '\{path\}', $rootPath) -Level "error"
        return
    }
    Write-Log ($logMessages.messages.rootResolved -replace '\{path\}', $rootPath) -Level "info"

    # -- Resolve target projects.json path --
    $targetPath = $customJsonPath
    $hasCustom = -not [string]::IsNullOrWhiteSpace($targetPath)
    if (-not $hasCustom) {
        $targetPath = Get-VSCodeProjectsJsonPath
    }
    Write-Log ($logMessages.messages.targetResolved -replace '\{path\}', $targetPath) -Level "info"

    # -- Ensure file exists (create [] if missing) --
    if (-not $isDryRun) {
        Initialize-VSCodeProjectsJson -Path $targetPath
    }

    # -- Load existing entries --
    $existing = @()
    $isTargetPresent = Test-Path -LiteralPath $targetPath
    if ($isTargetPresent) {
        try {
            $existing = Read-VSCodeProjects -Path $targetPath
        } catch {
            Write-Log ($logMessages.messages.targetReadFailed -replace '\{path\}', $targetPath -replace '\{error\}', $_) -Level "error"
            return
        }
    }
    $entries = New-Object System.Collections.ArrayList
    foreach ($e in $existing) { [void]$entries.Add($e) }
    $preservedCount = $entries.Count

    # -- Markers (PSCustomObject -> hashtable shape Test-IsProjectFolder expects) --
    $markers = @{
        files    = @($config.scan.markers.files)
        patterns = @($config.scan.markers.patterns)
        dirs     = @($config.scan.markers.dirs)
    }
    $skipDirs = @($config.scan.skipDirs)

    # -- Walk --
    Write-Host ""
    Write-Host "  Root        : $rootPath" -ForegroundColor Cyan
    Write-Host "  Target JSON : $targetPath" -ForegroundColor Cyan
    Write-Host "  Depth       : $depth" -ForegroundColor Cyan
    $modeLabel = if ($isDryRun) { "dry-run" } else { "write" }
    Write-Host "  Mode        : $modeLabel" -ForegroundColor Cyan
    Write-Host ""

    $discovered = Find-Projects `
        -Root $rootPath `
        -Markers $markers `
        -SkipDirs $skipDirs `
        -MaxDepth $depth `
        -IncludeHidden:$includeHidden

    $addedCount   = 0
    $updatedCount = 0
    $noopCount    = 0

    foreach ($projPath in $discovered) {
        $name = Split-Path $projPath -Leaf
        $status = Add-OrUpdateVSCodeProject -Entries $entries -RootPath $projPath -DefaultName $name
        switch ($status) {
            "added"   {
                $addedCount++
                Write-Log ($logMessages.messages.added -replace '\{name\}', $name -replace '\{path\}', $projPath) -Level "success"
            }
            "updated" {
                $updatedCount++
                Write-Log ($logMessages.messages.updated -replace '\{name\}', $name -replace '\{path\}', $projPath) -Level "info"
            }
            "noop"    {
                $noopCount++
                Write-Log ($logMessages.messages.noop -replace '\{name\}', $name -replace '\{path\}', $projPath) -Level "info"
            }
        }
    }

    # -- Write atomically (unless dry-run) --
    $hasChanges = ($addedCount + $updatedCount) -gt 0
    if ($isDryRun) {
        Write-Log $logMessages.messages.dryRun -Level "warn"
    } elseif ($hasChanges) {
        try {
            Save-VSCodeProjects -Path $targetPath -Entries $entries
            Write-Log ($logMessages.messages.targetWritten -replace '\{count\}', $entries.Count -replace '\{path\}', $targetPath) -Level "success"
        } catch {
            Write-Log ($logMessages.messages.targetWriteFailed -replace '\{path\}', $targetPath -replace '\{error\}', $_) -Level "error"
        }
    } else {
        Write-Log "No changes -- projects.json left untouched." -Level "info"
    }

    # -- Summary --
    Write-Host ""
    Write-Host "  $($logMessages.messages.summaryHeader)" -ForegroundColor Yellow
    Write-Host "  $('-' * $logMessages.messages.summaryHeader.Length)" -ForegroundColor DarkGray
    Write-Host ($logMessages.messages.summaryDiscovered -replace '\{count\}', @($discovered).Count.ToString().PadLeft(3))
    Write-Host ($logMessages.messages.summaryAdded      -replace '\{count\}', $addedCount.ToString().PadLeft(3))
    Write-Host ($logMessages.messages.summaryUpdated    -replace '\{count\}', $updatedCount.ToString().PadLeft(3))
    Write-Host ($logMessages.messages.summaryNoop       -replace '\{count\}', $noopCount.ToString().PadLeft(3))
    Write-Host ($logMessages.messages.summaryPreserved  -replace '\{count\}', $preservedCount.ToString().PadLeft(3))
    if (-not $isDryRun -and $hasChanges) {
        Write-Host ($logMessages.messages.summaryWritten -replace '\{path\}', $targetPath)
    }
    Write-Host ""
    Write-Log $logMessages.messages.scanComplete -Level "success"

} catch {
    Write-Log "Unhandled error: $_" -Level "error"
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level "error"
} finally {
    $hasAnyErrors = $script:_LogErrors.Count -gt 0
    Save-LogFile -Status $(if ($hasAnyErrors) { "fail" } else { "ok" })
}
