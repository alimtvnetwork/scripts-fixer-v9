<#
.SYNOPSIS
    OS subcommand dispatcher.

.DESCRIPTION
    Routes 'os <action>' invocations to per-action helpers under
    scripts/os/helpers/. All helpers initialize their own logging and
    handle their own admin elevation.

.EXAMPLES
    .\run.ps1 os clean
    .\run.ps1 os clean -Yes
    .\run.ps1 os temp-clean
    .\run.ps1 os temp-clean -Yes
    .\run.ps1 os hib-off
    .\run.ps1 os flp
    .\run.ps1 os add-user alice MyP@ss123 1234 alice@outlook.com
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

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")

$logMessages = $null
$logMessagesPath = Join-Path $scriptDir "log-messages.json"
if (Test-Path $logMessagesPath) {
    $logMessages = Import-JsonConfig $logMessagesPath
}

function Show-OsHelp {
    Write-Host ""
    Write-Host "  OS Subcommands" -ForegroundColor Cyan
    Write-Host "  ==============" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage: .\run.ps1 os <action> [args]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ACTIONS" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    clean" -ForegroundColor Green
    Write-Host "      Full Windows housekeeping sweep. Wipes:" -ForegroundColor DarkGray
    Write-Host "        1. C:\Windows\SoftwareDistribution\Download   (Windows Update cache)" -ForegroundColor DarkGray
    Write-Host "        2. ALL temp directories (cascades into 'temp-clean'):" -ForegroundColor DarkGray
    Write-Host "             - %TEMP%   - C:\Windows\Temp   - %LOCALAPPDATA%\Temp" -ForegroundColor DarkGray
    Write-Host "             - C:\Users\<each>\AppData\Local\Temp     - %TEMP%\chocolatey" -ForegroundColor DarkGray
    Write-Host "        3. Chocolatey cache (lib-bad, lib-bkp, *.backup, *.nupkg cache)" -ForegroundColor DarkGray
    Write-Host "             + runs choco-cleaner if installed. LIVE choco install untouched." -ForegroundColor DarkGray
    Write-Host "        4. All Windows event logs (wevtutil cl)" -ForegroundColor DarkGray
    Write-Host "        5. PSReadLine command history file" -ForegroundColor DarkGray
    Write-Host "        6. Current session command history" -ForegroundColor DarkGray
    Write-Host "      Locked files (open by chrome.exe / OneDrive etc.) are SKIPPED, not crashed on." -ForegroundColor DarkGray
    Write-Host "      A [LOCKED FILES] section at the end lists every skipped file + the OS reason." -ForegroundColor DarkGray
    Write-Host "      Reports MB / GB freed per category and totals." -ForegroundColor DarkGray
    Write-Host "      Flags:  -Yes  skip prompt    -NoChoco  skip choco cache    -NoTempCascade  skip temp" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    temp-clean" -ForegroundColor Green
    Write-Host "      Subset of 'clean' -- temp directories ONLY (faster, no event logs / no choco / no WU)." -ForegroundColor DarkGray
    Write-Host "      Targets: %TEMP%, C:\Windows\Temp, %LOCALAPPDATA%\Temp, all per-user Temp," -ForegroundColor DarkGray
    Write-Host "               %TEMP%\chocolatey. Same locked-file reporting as 'clean'." -ForegroundColor DarkGray
    Write-Host "      Use this for a quick safe sweep when you don't want to clear event logs." -ForegroundColor DarkGray
    Write-Host "      Flags:  -Yes  skip prompt    -NoChoco  skip choco TEMP" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    hib-off    (alias: hibernate-off)" -ForegroundColor Green
    Write-Host "      Disables hibernation, deletes hiberfil.sys, reports freed bytes (often several GB)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    hib-on     (alias: hibernate-on)" -ForegroundColor Green
    Write-Host "      Re-enables hibernation." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    flp        (alias: fix-long-path, longpath)" -ForegroundColor Green
    Write-Host "      Enables Win32 long-path support (registry: LongPathsEnabled=1). Reboot recommended." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    add-user <name> <pass> [pin] [email]" -ForegroundColor Green
    Write-Host "      Creates a local Windows user. PIN/email are noted in the summary -- they require" -ForegroundColor DarkGray
    Write-Host "      interactive setup at first sign-in (Windows API limitation, not a bug)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    help       (alias: --help, -h)" -ForegroundColor Green
    Write-Host "      Show this help." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  NOTES" -ForegroundColor Yellow
    Write-Host "    - All actions require Administrator elevation; the helper re-launches if needed." -ForegroundColor DarkGray
    Write-Host "    - 'clean' internally cascades 'temp-clean' for single source of truth on temp logic." -ForegroundColor DarkGray
    Write-Host "    - 'add-user' password is passed as plain CLI arg (visible in shell history -- accepted risk)." -ForegroundColor DarkGray
    Write-Host ""
}

$normalizedAction = ""
$hasAction = -not [string]::IsNullOrWhiteSpace($Action)
if ($hasAction) { $normalizedAction = $Action.Trim().ToLower() }

switch ($normalizedAction) {
    { $_ -in @("clean") } {
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
