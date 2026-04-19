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
    $col = 30
    Write-Host "    $("clean".PadRight($col))"           -NoNewline; Write-Host "Wipe SoftwareDistribution, TEMP, event logs, PSReadLine history" -ForegroundColor DarkGray
    Write-Host "    $("clean -Yes".PadRight($col))"      -NoNewline; Write-Host "Skip confirmation prompt" -ForegroundColor DarkGray
    Write-Host "    $("hib-off".PadRight($col))"         -NoNewline; Write-Host "Disable hibernation (frees hiberfil.sys)" -ForegroundColor DarkGray
    Write-Host "    $("hibernate-off".PadRight($col))"   -NoNewline; Write-Host "Alias for hib-off" -ForegroundColor DarkGray
    Write-Host "    $("hib-on".PadRight($col))"          -NoNewline; Write-Host "Re-enable hibernation" -ForegroundColor DarkGray
    Write-Host "    $("flp".PadRight($col))"             -NoNewline; Write-Host "Enable Win32 long-path support (registry)" -ForegroundColor DarkGray
    Write-Host "    $("fix-long-path".PadRight($col))"   -NoNewline; Write-Host "Alias for flp" -ForegroundColor DarkGray
    Write-Host "    $("add-user <name> <pass> [pin] [email]".PadRight($col))" -NoNewline; Write-Host "Create local user (PIN/email manual notice)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Notes:" -ForegroundColor Yellow
    Write-Host "    - All actions require Administrator elevation; the helper will re-launch if needed." -ForegroundColor DarkGray
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
