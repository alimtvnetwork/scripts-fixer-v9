<#
.SYNOPSIS
    Git-tools subcommand dispatcher.

.DESCRIPTION
    Routes 'git-tools <action>' (or shortcuts like 'gsa') to per-action helpers.

    Supported actions:
      safe-all (gsa)        -- add safe.directory='*' or scan a tree (default if no flag)
      list (--list)         -- audit current safe.directory entries
      remove (--remove)     -- unset a single safe.directory entry
      prune (--prune)       -- remove orphan entries (paths missing on disk)

.EXAMPLES
    .\run.ps1 gsa                                  # safe.directory='*' (wildcard)
    .\run.ps1 gsa --scan C:\Users\Alim\GitHub      # add each repo individually
    .\run.ps1 gsa --list                           # audit current entries
    .\run.ps1 gsa --remove C:\Users\Alim\old-repo  # unset one entry
    .\run.ps1 gsa --prune                          # delete orphans (live)
    .\run.ps1 gsa --prune --dry-run                # preview orphans only
    .\run.ps1 git-tools list
    .\run.ps1 git-tools help
#>
param(
    [Parameter(Position = 0)]
    [string]$Action,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Show-GitToolsHelp {
    Write-Host ""
    Write-Host "  Git Tools" -ForegroundColor Cyan
    Write-Host "  =========" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage: .\run.ps1 git-tools <action> [args]" -ForegroundColor Yellow
    Write-Host "         .\run.ps1 gsa [args]                     (shortcut for safe-all dispatcher)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ACTIONS" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    safe-all   (alias: gsa, git-safe-all)" -ForegroundColor Green
    Write-Host "      Adds safe.directory entries to global gitconfig. Two modes:" -ForegroundColor DarkGray
    Write-Host "        Default (no args)  -> safe.directory='*' (one wildcard, idempotent)" -ForegroundColor DarkGray
    Write-Host "        --scan <path>      -> walks <path> recursively, adds each .git repo" -ForegroundColor DarkGray
    Write-Host "                              parent path individually (idempotent)" -ForegroundColor DarkGray
    Write-Host "      Flags:  --scan <path>     repo-discovery root" -ForegroundColor DarkGray
    Write-Host "              --depth <n>       recursion depth (default 4)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    list       (alias: --list, audit, safe-list)" -ForegroundColor Green
    Write-Host "      READ-ONLY. Lists every safe.directory entry from global gitconfig," -ForegroundColor DarkGray
    Write-Host "      sorted, deduped, with wildcard vs per-repo breakdown + counts." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    remove <path>   (alias: --remove, unset, safe-remove)" -ForegroundColor Green
    Write-Host "      Idempotent. Unsets a single safe.directory entry. Reports before/after counts." -ForegroundColor DarkGray
    Write-Host "      Use --remove '*' to revoke the wildcard." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    prune      (alias: --prune, safe-prune)" -ForegroundColor Green
    Write-Host "      Removes orphan entries -- per-repo paths that no longer exist on disk." -ForegroundColor DarkGray
    Write-Host "      Wildcard '*' is NEVER pruned. Add --dry-run to preview without changes." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    help       (alias: --help, -h)" -ForegroundColor Green
    Write-Host "      Show this help." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  EXAMPLES" -ForegroundColor Yellow
    Write-Host "    .\run.ps1 gsa                                  # wildcard once" -ForegroundColor DarkGray
    Write-Host "    .\run.ps1 gsa --scan C:\Users\Alim\GitHub      # per-repo entries" -ForegroundColor DarkGray
    Write-Host "    .\run.ps1 gsa --scan D:\code --depth 6" -ForegroundColor DarkGray
    Write-Host "    .\run.ps1 gsa --list                           # audit" -ForegroundColor DarkGray
    Write-Host "    .\run.ps1 gsa --remove C:\Users\Alim\old-repo  # unset one" -ForegroundColor DarkGray
    Write-Host "    .\run.ps1 gsa --prune --dry-run                # preview orphans" -ForegroundColor DarkGray
    Write-Host "    .\run.ps1 gsa --prune                          # delete orphans" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  WHEN TO USE" -ForegroundColor Yellow
    Write-Host "    Use wildcard mode for personal dev machines (covers everything)." -ForegroundColor DarkGray
    Write-Host "    Use --scan mode in shared / locked-down environments where '*' is" -ForegroundColor DarkGray
    Write-Host "    too permissive but you still want every existing repo trusted." -ForegroundColor DarkGray
    Write-Host "    Use --list periodically to audit what's been trusted." -ForegroundColor DarkGray
    Write-Host "    Use --prune after cleaning up old repos to remove dead entries." -ForegroundColor DarkGray
    Write-Host ""
}

# -- Detect inline flags in $Rest (e.g. 'gsa --list', 'gsa --prune') --
# Returns the action keyword that was triggered, or "" if none.
function Test-InlineActionFlag {
    param([string[]]$Args)

    $hasArgs = $null -ne $Args -and $Args.Count -gt 0
    if (-not $hasArgs) { return "" }

    foreach ($a in $Args) {
        $low = "$a".Trim().ToLower()
        if ($low -eq "--list" -or $low -eq "-list")     { return "list" }
        if ($low -eq "--remove" -or $low -eq "-remove") { return "remove" }
        if ($low -eq "--prune" -or $low -eq "-prune")   { return "prune" }
    }
    return ""
}

# -- Parse --scan / --depth flags (for safe-all) ----------------------
function Resolve-SafeAllArgs {
    param([string[]]$Args)

    $scanValue = ""
    $depthValue = 4
    $i = 0
    $hasArgs = $null -ne $Args -and $Args.Count -gt 0
    if (-not $hasArgs) { return @{ Scan = $scanValue; Depth = $depthValue } }

    while ($i -lt $Args.Count) {
        $arg = $Args[$i]
        $argLower = "$arg".Trim().ToLower()

        $isScanFlag = $argLower -eq "--scan" -or $argLower -eq "-scan"
        if ($isScanFlag) {
            $hasNext = ($i + 1) -lt $Args.Count
            if ($hasNext) {
                $scanValue = $Args[$i + 1]
                $i += 2
                continue
            }
            $i++
            continue
        }

        $isScanEquals = $argLower.StartsWith("--scan=")
        if ($isScanEquals) {
            $scanValue = $arg.Substring($arg.IndexOf("=") + 1)
            $i++
            continue
        }

        $isDepthFlag = $argLower -eq "--depth" -or $argLower -eq "-depth"
        if ($isDepthFlag) {
            $hasNext = ($i + 1) -lt $Args.Count
            if ($hasNext) {
                [int]::TryParse($Args[$i + 1], [ref]$depthValue) | Out-Null
                $i += 2
                continue
            }
            $i++
            continue
        }

        $isDepthEquals = $argLower.StartsWith("--depth=")
        if ($isDepthEquals) {
            $val = $arg.Substring($arg.IndexOf("=") + 1)
            [int]::TryParse($val, [ref]$depthValue) | Out-Null
            $i++
            continue
        }

        $i++
    }
    return @{ Scan = $scanValue; Depth = $depthValue }
}

# -- Extract the path argument for --remove ---------------------------
# Accepts: 'gsa --remove C:\path', 'gsa --remove=C:\path', 'gsa remove C:\path'
function Resolve-RemovePath {
    param([string[]]$Args)

    $hasArgs = $null -ne $Args -and $Args.Count -gt 0
    if (-not $hasArgs) { return "" }

    $i = 0
    while ($i -lt $Args.Count) {
        $arg = $Args[$i]
        $low = "$arg".Trim().ToLower()

        $isRemoveFlag = $low -eq "--remove" -or $low -eq "-remove"
        if ($isRemoveFlag) {
            $hasNext = ($i + 1) -lt $Args.Count
            if ($hasNext) { return $Args[$i + 1] }
            return ""
        }
        $isRemoveEquals = $low.StartsWith("--remove=")
        if ($isRemoveEquals) {
            return $arg.Substring($arg.IndexOf("=") + 1)
        }
        $i++
    }

    # Fallback: first arg that isn't a known flag
    foreach ($a in $Args) {
        $low = "$a".Trim().ToLower()
        $isFlag = $low.StartsWith("--") -or $low.StartsWith("-")
        if (-not $isFlag) { return $a }
    }
    return ""
}

# -- Detect --dry-run anywhere in $Rest -------------------------------
function Test-DryRunFlag {
    param([string[]]$Args)
    $hasArgs = $null -ne $Args -and $Args.Count -gt 0
    if (-not $hasArgs) { return $false }
    foreach ($a in $Args) {
        $low = "$a".Trim().ToLower()
        if ($low -eq "--dry-run" -or $low -eq "-dryrun" -or $low -eq "--dryrun") { return $true }
    }
    return $false
}

$normalizedAction = ""
$hasAction = -not [string]::IsNullOrWhiteSpace($Action)
if ($hasAction) { $normalizedAction = $Action.Trim().ToLower() }

# If user invoked 'gsa --list' / 'gsa --remove ...' / 'gsa --prune',
# the action keyword landed in $Action OR in $Rest. Detect both.
$inlineFlag = ""
if ($normalizedAction -in @("safe-all", "safeall", "gsa", "git-safe-all")) {
    $inlineFlag = Test-InlineActionFlag -Args $Rest
}
elseif ($normalizedAction -in @("--list", "--remove", "--prune")) {
    # User skipped the 'gsa' part: '.\run.ps1 git-tools --list'
    $inlineFlag = $normalizedAction.TrimStart('-')
}

# Inline flag overrides the default safe-all routing
if ($inlineFlag -ne "") {
    $normalizedAction = $inlineFlag
}

switch ($normalizedAction) {
    { $_ -in @("safe-all", "safeall", "gsa", "git-safe-all") } {
        $parsed = Resolve-SafeAllArgs -Args $Rest
        & (Join-Path $scriptDir "helpers\safe-all.ps1") -Scan $parsed.Scan -Depth $parsed.Depth
        exit $LASTEXITCODE
    }
    { $_ -in @("list", "audit", "safe-list", "--list") } {
        & (Join-Path $scriptDir "helpers\list-safe.ps1")
        exit $LASTEXITCODE
    }
    { $_ -in @("remove", "unset", "safe-remove", "--remove") } {
        $removePath = Resolve-RemovePath -Args $Rest
        & (Join-Path $scriptDir "helpers\remove-safe.ps1") -Path $removePath
        exit $LASTEXITCODE
    }
    { $_ -in @("prune", "safe-prune", "--prune") } {
        $isDry = Test-DryRunFlag -Args $Rest
        if ($isDry) {
            & (Join-Path $scriptDir "helpers\prune-safe.ps1") -DryRun
        } else {
            & (Join-Path $scriptDir "helpers\prune-safe.ps1")
        }
        exit $LASTEXITCODE
    }
    { $_ -in @("help", "--help", "-h", "") } {
        Show-GitToolsHelp
        exit 0
    }
    default {
        Write-Host ""
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "Unknown 'git-tools' action: '$Action'"
        Show-GitToolsHelp
        exit 1
    }
}
