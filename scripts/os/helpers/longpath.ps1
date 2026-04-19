<#
.SYNOPSIS
    os flp -- Enable Win32 long-path support via registry.
#>
$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$helpersDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptDir  = Split-Path -Parent $helpersDir
$sharedDir  = Join-Path (Split-Path -Parent $scriptDir) "shared"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")
. (Join-Path $helpersDir "_common.ps1")

$config      = Import-JsonConfig (Join-Path $scriptDir "config.json")
$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")
$script:LogMessages = $logMessages

Initialize-Logging -ScriptName "Fix Long Path"

$isAdminOk = Assert-Admin -ScriptPath $MyInvocation.MyCommand.Definition -LogMessages $logMessages
if (-not $isAdminOk) {
    Save-LogFile -Status "fail"
    exit 1
}

$key  = $config.longPath.registryKey
$name = $config.longPath.valueName

try {
    $current = $null
    try {
        $current = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name
    } catch {}

    if ($current -eq 1) {
        Write-Log $logMessages.longPath.alreadyEnabled -Level "success"
        Save-LogFile -Status "ok"
        exit 0
    }

    Set-ItemProperty -Path $key -Name $name -Value 1 -Type DWord -ErrorAction Stop
    $verify = (Get-ItemProperty -Path $key -Name $name -ErrorAction Stop).$name

    if ($verify -eq 1) {
        Write-Log $logMessages.longPath.enabled -Level "success"
        Save-LogFile -Status "ok"
        exit 0
    } else {
        $msg = $logMessages.longPath.verifyFailed `
            -replace '\{path\}', $key `
            -replace '\{current\}', "$verify"
        Write-Log $msg -Level "fail"
        Save-LogFile -Status "fail"
        exit 1
    }
} catch {
    Write-Log "Failed to set $name at ${key}: $($_.Exception.Message)" -Level "fail"
    Save-LogFile -Status "fail"
    exit 1
}
