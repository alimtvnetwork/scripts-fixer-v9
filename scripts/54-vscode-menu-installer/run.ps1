# --------------------------------------------------------------------------
#  Script 54 -- run.ps1 (router)
#
#  Routes to install.ps1 / uninstall.ps1 so the project's master -I 54
#  dispatcher can invoke this script with a verb.
# --------------------------------------------------------------------------
param(
    [Parameter(Position = 0)]
    [string]$Command = "install",

    [string]$Edition,
    [string]$VsCodePath,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

if ($Help) {
    & (Join-Path $scriptDir "install.ps1") -Help
    return
}

switch ($Command.ToLower()) {
    "uninstall" {
        & (Join-Path $scriptDir "uninstall.ps1") -Edition $Edition
    }
    default {
        & (Join-Path $scriptDir "install.ps1") -Edition $Edition -VsCodePath $VsCodePath
    }
}
