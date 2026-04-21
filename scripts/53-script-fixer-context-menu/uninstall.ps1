# --------------------------------------------------------------------------
#  Script 53 -- uninstall.ps1 wrapper
#
#  Thin alias for `.\run.ps1 uninstall`. Removes ONLY the registry keys this
#  script owns (the four "ScriptFixer" top-level keys plus their cascading
#  children). Any sibling key (e.g. a separately-installed "VSCode" or
#  "OpenWithCode") is untouched -- the underlying uninstall path is a strict
#  allow-list of the four keys declared in config.json.
# --------------------------------------------------------------------------
param(
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

& $runPs1 uninstall
