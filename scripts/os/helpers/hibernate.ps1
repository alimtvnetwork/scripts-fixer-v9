<#
.SYNOPSIS
    os hib-off / hib-on -- toggle Windows hibernation.
#>
param(
    [switch]$Off,
    [switch]$On
)

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

# Default to -Off if neither switch given
if (-not $On -and -not $Off) { $Off = $true }

$label = if ($On) { "Hibernate ON" } else { "Hibernate OFF" }
Initialize-Logging -ScriptName $label

$forwardArgs = @()
if ($On)  { $forwardArgs += "-On" }
if ($Off) { $forwardArgs += "-Off" }

$isAdminOk = Assert-Admin -ScriptPath $MyInvocation.MyCommand.Definition -ForwardArgs $forwardArgs -LogMessages $logMessages
if (-not $isAdminOk) {
    Save-LogFile -Status "fail"
    exit 1
}

$hiberPath = $config.hibernate.hiberfilPath

if ($On) {
    $proc = Start-Process -FilePath "powercfg.exe" -ArgumentList "/hibernate", "on" -Wait -PassThru -NoNewWindow
    $code = $proc.ExitCode
    if ($code -ne 0) {
        $msg = $logMessages.hibernate.powercfgFailed `
            -replace '\{mode\}', 'on' `
            -replace '\{code\}', "$code"
        Write-Log $msg -Level "fail"
        Save-LogFile -Status "fail"
        exit $code
    }
    Write-Log $logMessages.hibernate.on -Level "success"
} else {
    $sizeBefore = 0
    if (Test-Path $hiberPath) {
        try { $sizeBefore = (Get-Item $hiberPath -Force).Length } catch { $sizeBefore = 0 }
    }

    $proc = Start-Process -FilePath "powercfg.exe" -ArgumentList "/hibernate", "off" -Wait -PassThru -NoNewWindow
    $code = $proc.ExitCode
    if ($code -ne 0) {
        $msg = $logMessages.hibernate.powercfgFailed `
            -replace '\{mode\}', 'off' `
            -replace '\{code\}', "$code"
        Write-Log $msg -Level "fail"
        Save-LogFile -Status "fail"
        exit $code
    }

    Start-Sleep -Seconds 2
    $sizeAfter = 0
    if (Test-Path $hiberPath) {
        try { $sizeAfter = (Get-Item $hiberPath -Force).Length } catch { $sizeAfter = 0 }
    }
    $freedBytes = [Math]::Max(0, $sizeBefore - $sizeAfter)

    if ($sizeBefore -eq 0) {
        Write-Log $logMessages.hibernate.offNoFile -Level "success"
    } else {
        $gb = Format-Gb -Bytes $freedBytes
        $msg = $logMessages.hibernate.off -replace '\{gb\}', $gb
        Write-Log $msg -Level "success"
    }
}

Save-LogFile -Status "ok"
exit 0
