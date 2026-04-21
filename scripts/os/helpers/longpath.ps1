<#
.SYNOPSIS
    os flp -- Enable Win32 long-path support via registry.

.PARAMETER Verbose
    Standard CommonParameter. When present, every registry read/write is
    appended to .logs/os-fix-long-path-registry-trace.log via
    scripts/shared/registry-trace.ps1. The host JSON log under .logs/ is
    unaffected.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$helpersDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptDir  = Split-Path -Parent $helpersDir
$sharedDir  = Join-Path (Split-Path -Parent $scriptDir) "shared"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")
. (Join-Path $sharedDir "registry-trace.ps1")
. (Join-Path $helpersDir "_common.ps1")

$config      = Import-JsonConfig (Join-Path $scriptDir "config.json")
$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")
$script:LogMessages = $logMessages

Initialize-Logging -ScriptName "Fix Long Path"

# Verbose is forwarded by run.ps1 via splat; honour both the bound parameter
# and the inherited $VerbosePreference so the trace works regardless of how
# the script is invoked.
$isVerbose = $PSBoundParameters.ContainsKey('Verbose') -or ($VerbosePreference -ne 'SilentlyContinue')
Initialize-RegistryTrace -ScriptName "os-fix-long-path" -VerboseEnabled $isVerbose

$isAdminOk = Assert-Admin -ScriptPath $MyInvocation.MyCommand.Definition -LogMessages $logMessages
if (-not $isAdminOk) {
    Close-RegistryTrace -Status "fail (not admin)"
    Save-LogFile -Status "fail"
    exit 1
}

$key  = $config.longPath.registryKey
$name = $config.longPath.valueName

try {
    $current = $null
    try {
        $current = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name
        Write-RegistryTrace -Op "GET" -Path $key -Name $name -NewValue $current -Status "OK"
    } catch {
        Write-RegistryTrace -Op "GET" -Path $key -Name $name -Status "FAIL" -Reason $_.Exception.Message
    }

    if ($current -eq 1) {
        Write-RegistryTrace -Op "READ-ONLY" -Path $key -Name $name -NewValue $current -Status "SKIP" -Reason "already enabled, no write performed"
        Write-Log $logMessages.longPath.alreadyEnabled -Level "success"
        Close-RegistryTrace -Status "ok (already enabled)"
        Save-LogFile -Status "ok"
        exit 0
    }

    try {
        Set-ItemProperty -Path $key -Name $name -Value 1 -Type DWord -ErrorAction Stop
        Write-RegistryTrace -Op "SET" -Path $key -Name $name -OldValue $current -NewValue 1 -Status "OK"
    } catch {
        Write-RegistryTrace -Op "SET" -Path $key -Name $name -OldValue $current -NewValue 1 -Status "FAIL" -Reason $_.Exception.Message
        throw
    }

    $verify = (Get-ItemProperty -Path $key -Name $name -ErrorAction Stop).$name
    Write-RegistryTrace -Op "GET" -Path $key -Name $name -NewValue $verify -Status "OK" -Reason "post-write verification"

    if ($verify -eq 1) {
        Write-Log $logMessages.longPath.enabled -Level "success"
        Close-RegistryTrace -Status "ok"
        Save-LogFile -Status "ok"
        exit 0
    } else {
        $msg = $logMessages.longPath.verifyFailed `
            -replace '\{path\}', $key `
            -replace '\{current\}', "$verify"
        Write-Log $msg -Level "fail"
        Write-RegistryTrace -Op "READ-ONLY" -Path $key -Name $name -NewValue $verify -Status "FAIL" -Reason "verification mismatch (expected 1)"
        Close-RegistryTrace -Status "fail (verify mismatch)"
        Save-LogFile -Status "fail"
        exit 1
    }
} catch {
    Write-Log "Failed to set $name at ${key}: $($_.Exception.Message)" -Level "fail"
    Close-RegistryTrace -Status "fail (exception)"
    Save-LogFile -Status "fail"
    exit 1
}
