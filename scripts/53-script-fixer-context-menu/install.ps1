# --------------------------------------------------------------------------
#  Script 53 -- install.ps1 wrapper
#
#  Thin alias for `.\run.ps1 install`. Exists so the script can be handed
#  off / scheduled / linked from another tool with a self-explanatory file
#  name. All real logic lives in run.ps1 (single source of truth -- if you
#  change install behavior, change it there, NOT here).
# --------------------------------------------------------------------------
param(
    [switch]$Refresh,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$runPs1    = Join-Path $scriptDir "run.ps1"

$isRunMissing = -not (Test-Path -LiteralPath $runPs1)
if ($isRunMissing) {
    Write-Host "FATAL: dispatcher not found at $runPs1" -ForegroundColor Red
    exit 1
}

if ($Help) {
    & $runPs1 -Help
    return
}

$verb = if ($Refresh) { "refresh" } else { "install" }
& $runPs1 $verb
