<#
.SYNOPSIS
    Git-tools subcommand dispatcher.

.DESCRIPTION
    Routes 'git-tools <action>' (or shortcuts like 'gsa') to per-action helpers.

.EXAMPLES
    .\run.ps1 gsa                                  # safe.directory='*' (wildcard)
    .\run.ps1 gsa --scan C:\Users\Alim\GitHub      # add each repo individually
    .\run.ps1 gsa --scan D:\code --depth 6         # custom recursion depth
    .\run.ps1 git-tools safe-all
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
    Write-Host "         .\run.ps1 gsa [args]                     (shortcut for safe-all)" -ForegroundColor Yellow
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
    Write-Host "    help       (alias: --help, -h)" -ForegroundColor Green
    Write-Host "      Show this help." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  EXAMPLES" -ForegroundColor Yellow
    Write-Host "    .\run.ps1 gsa                                  # wildcard once" -ForegroundColor DarkGray
    Write-Host "    .\run.ps1 gsa --scan C:\Users\Alim\GitHub      # per-repo entries" -ForegroundColor DarkGray
    Write-Host "    .\run.ps1 gsa --scan D:\code --depth 6" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  WHEN TO USE" -ForegroundColor Yellow
    Write-Host "    Use wildcard mode for personal dev machines (covers everything)." -ForegroundColor DarkGray
    Write-Host "    Use --scan mode in shared / locked-down environments where '*' is" -ForegroundColor DarkGray
    Write-Host "    too permissive but you still want every existing repo trusted." -ForegroundColor DarkGray
    Write-Host ""
}

# -- Parse --scan / --depth flags from $Rest --------------------------
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

$normalizedAction = ""
$hasAction = -not [string]::IsNullOrWhiteSpace($Action)
if ($hasAction) { $normalizedAction = $Action.Trim().ToLower() }

switch ($normalizedAction) {
    { $_ -in @("safe-all", "safeall", "gsa", "git-safe-all") } {
        $parsed = Resolve-SafeAllArgs -Args $Rest
        & (Join-Path $scriptDir "helpers\safe-all.ps1") -Scan $parsed.Scan -Depth $parsed.Depth
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
