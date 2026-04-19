<#
.SYNOPSIS
    OS subcommand dispatcher. Routes 'os <action>' to the right helper.

.DESCRIPTION
    Static actions: clean, temp-clean, hib-off/on, flp, add-user, help.
    Dynamic actions: every clean-<name> resolves to clean-categories\<name>.ps1
    (32 categories, see `os --help`).

.EXAMPLES
    .\run.ps1 os clean
    .\run.ps1 os clean --dry-run
    .\run.ps1 os clean --bucket D
    .\run.ps1 os clean --skip recycle,ms-search
    .\run.ps1 os clean-chrome
    .\run.ps1 os clean-recycle --yes
    .\run.ps1 os clean-obs-recordings --days 7 --dry-run
#>
param(
    [Parameter(Position = 0)]
    [string]$Action,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sharedDir = Join-Path (Split-Path -Parent $scriptDir) "shared"
$categoriesDir = Join-Path $scriptDir "helpers\clean-categories"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")

$logMessages = $null
$logMessagesPath = Join-Path $scriptDir "log-messages.json"
if (Test-Path $logMessagesPath) {
    $logMessages = Import-JsonConfig $logMessagesPath
}

# Catalog rendered in help (also the source of truth for valid clean-<name>)
$script:CleanCatalog = @(
    @{ B = "A"; Cat = "chkdsk";              Desc = "C:\found.*\*.chk fragments" },
    @{ B = "A"; Cat = "dns";                 Desc = "ipconfig /flushdns" },
    @{ B = "A"; Cat = "recycle";             Desc = "Empty Recycle Bin (DESTRUCTIVE -- consent)" },
    @{ B = "A"; Cat = "delivery-opt";        Desc = "WU Delivery Optimization cache" },
    @{ B = "A"; Cat = "error-reports";       Desc = "Windows Error Reports (WER)" },
    @{ B = "A"; Cat = "event-logs";          Desc = "All Windows event logs (wevtutil cl)" },
    @{ B = "A"; Cat = "etl";                 Desc = "ETW trace files (*.etl)" },
    @{ B = "A"; Cat = "windows-logs";        Desc = "CBS / DISM / WindowsUpdate logs" },
    @{ B = "B"; Cat = "notifications";       Desc = "Windows Notifications (wpndatabase)" },
    @{ B = "B"; Cat = "explorer-mru";        Desc = "Run/RecentDocs/TypedPaths registry" },
    @{ B = "B"; Cat = "recent-docs";         Desc = "Quick Access recent files" },
    @{ B = "B"; Cat = "jumplist";            Desc = "Taskbar jump-lists" },
    @{ B = "B"; Cat = "thumbnails";          Desc = "Thumbnail + icon cache" },
    @{ B = "B"; Cat = "ms-search";           Desc = "Windows Search index (DESTRUCTIVE -- consent)" },
    @{ B = "C"; Cat = "dx-shader";           Desc = "DirectX/NVIDIA/AMD shader caches" },
    @{ B = "C"; Cat = "web-cache";           Desc = "Legacy IE/Edge INetCache" },
    @{ B = "C"; Cat = "font-cache";          Desc = "Windows font cache" },
    @{ B = "D"; Cat = "chrome";              Desc = "Chrome cache (cookies/history SAFE)" },
    @{ B = "D"; Cat = "edge";                Desc = "Edge cache (cookies/history SAFE)" },
    @{ B = "D"; Cat = "firefox";             Desc = "Firefox cache (cookies/history SAFE)" },
    @{ B = "D"; Cat = "brave";               Desc = "Brave cache (cookies/history SAFE)" },
    @{ B = "E"; Cat = "clipchamp";           Desc = "Clipchamp cache (drafts SAFE)" },
    @{ B = "E"; Cat = "vlc";                 Desc = "VLC art + media library cache" },
    @{ B = "E"; Cat = "discord";             Desc = "Discord cache (login SAFE)" },
    @{ B = "E"; Cat = "spotify";             Desc = "Spotify cache (offline downloads SAFE)" },
    @{ B = "F"; Cat = "vscode-cache";        Desc = "VS Code cache + logs (workspaces SAFE)" },
    @{ B = "F"; Cat = "npm-cache";           Desc = "npm cache clean --force" },
    @{ B = "F"; Cat = "pip-cache";           Desc = "pip cache purge" },
    @{ B = "F"; Cat = "docker-dangling";     Desc = "docker system prune -f" },
    @{ B = "G"; Cat = "obs-recordings";      Desc = "~/Videos *.mkv|*.mp4 >N days (SUBCOMMAND ONLY -- never aggregate)" },
    @{ B = "G"; Cat = "steam-shader";        Desc = "Steam shader cache (all libraries)" },
    @{ B = "G"; Cat = "windows-update-old";  Desc = "DISM ResetBase (SUBCOMMAND ONLY -- never aggregate)" }
)

function Show-OsHelp {
    Write-Host ""
    Write-Host "  OS Subcommands" -ForegroundColor Cyan
    Write-Host "  ==============" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage: .\run.ps1 os <action> [args]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  PRIMARY ACTIONS" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    clean [flags]                                          Run all 32 cleanup categories" -ForegroundColor Green
    Write-Host "      --yes                Auto-consent destructive categories" -ForegroundColor DarkGray
    Write-Host "      --dry-run            Report only (no deletions, no consent file written)" -ForegroundColor DarkGray
    Write-Host "      --skip <a,b,c>       Skip listed categories" -ForegroundColor DarkGray
    Write-Host "      --only <a,b,c>       Run only listed categories" -ForegroundColor DarkGray
    Write-Host "      --bucket <A..G>      Run only one bucket (e.g. D = browsers)" -ForegroundColor DarkGray
    Write-Host "      --days <N>           Age threshold for media subcommands (default 30)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    temp-clean [flags]                                     Temp dirs only (legacy helper)" -ForegroundColor Green
    Write-Host "    hib-off | hib-on                                       Disable/enable hibernation" -ForegroundColor Green
    Write-Host "    flp                                                    Enable Win32 long-path support" -ForegroundColor Green
    Write-Host "    add-user <name> <pass> [pin] [email]                   Create local Windows user" -ForegroundColor Green
    Write-Host ""
    Write-Host "  CLEAN-* SUBCOMMANDS (each accepts --dry-run / --yes / --days N)" -ForegroundColor Cyan
    $currentBucket = ""
    $bucketLabels = @{
        "A" = "Bucket A -- System"
        "B" = "Bucket B -- User shell"
        "C" = "Bucket C -- Graphics / Web"
        "D" = "Bucket D -- Browsers (cache only -- cookies/history NEVER touched)"
        "E" = "Bucket E -- Apps (cache only)"
        "F" = "Bucket F -- Dev tools"
        "G" = "Bucket G -- Media (age-gated / DISM)"
    }
    foreach ($entry in $script:CleanCatalog) {
        if ($entry.B -ne $currentBucket) {
            Write-Host ""
            Write-Host "    $($bucketLabels[$entry.B])" -ForegroundColor Yellow
            $currentBucket = $entry.B
        }
        Write-Host ("      clean-{0,-21} {1}" -f $entry.Cat, $entry.Desc) -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  CONSENT" -ForegroundColor Cyan
    Write-Host "    Destructive categories (recycle, ms-search, obs-recordings, windows-update-old)" -ForegroundColor DarkGray
    Write-Host "    require typed 'yes' on first run. Persisted in .resolved/os-clean-consent.json." -ForegroundColor DarkGray
    Write-Host "    Use --yes to auto-consent, --dry-run to explore safely without consent." -ForegroundColor DarkGray
    Write-Host ""
}

$normalizedAction = ""
$hasAction = -not [string]::IsNullOrWhiteSpace($Action)
if ($hasAction) { $normalizedAction = $Action.Trim().ToLower() }

# ---- clean-<name> dynamic dispatch ----
if ($normalizedAction -match '^clean-(.+)$') {
    $cat = $Matches[1]
    $isKnown = ($script:CleanCatalog | Where-Object { $_.Cat -eq $cat }).Count -gt 0
    if (-not $isKnown) {
        Write-Host ""
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "Unknown clean category: '$cat'"
        Write-Host "          Run '.\run.ps1 os --help' for the full list." -ForegroundColor DarkGray
        exit 1
    }
    & (Join-Path $scriptDir "helpers\clean-runner.ps1") -Category $cat @Rest
    exit $LASTEXITCODE
}

switch ($normalizedAction) {
    "clean" {
        & (Join-Path $scriptDir "helpers\clean.ps1") @Rest
        exit $LASTEXITCODE
    }
    { $_ -in @("temp-clean", "tempclean", "temp") } {
        & (Join-Path $scriptDir "helpers\temp-clean.ps1") @Rest
        exit $LASTEXITCODE
    }
    { $_ -in @("hib-off", "hibernate-off") } {
        & (Join-Path $scriptDir "helpers\hibernate.ps1") -Off @Rest
        exit $LASTEXITCODE
    }
    { $_ -in @("hib-on", "hibernate-on") } {
        & (Join-Path $scriptDir "helpers\hibernate.ps1") -On @Rest
        exit $LASTEXITCODE
    }
    { $_ -in @("flp", "fix-long-path", "longpath", "long-path") } {
        & (Join-Path $scriptDir "helpers\longpath.ps1") @Rest
        exit $LASTEXITCODE
    }
    { $_ -in @("add-user", "adduser", "new-user") } {
        & (Join-Path $scriptDir "helpers\add-user.ps1") @Rest
        exit $LASTEXITCODE
    }
    { $_ -in @("help", "--help", "-h", "") } {
        Show-OsHelp
        exit 0
    }
    default {
        Write-Host ""
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "Unknown 'os' action: '$Action'"
        Show-OsHelp
        exit 1
    }
}
