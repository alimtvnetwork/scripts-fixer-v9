<#
.SYNOPSIS
    Common helpers shared by all os/* subcommand helpers.
#>

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ForwardArgs = @(),
        [PSObject]$LogMessages
    )
    $isAdmin = Test-IsAdministrator
    if ($isAdmin) { return $true }

    $msg = "Administrator elevation required. Re-launching ..."
    if ($LogMessages -and $LogMessages.messages.adminRequired) {
        $msg = $LogMessages.messages.adminRequired
    }
    Write-Log $msg -Level "warn"

    # Pick pwsh (PS 7+) or powershell (PS 5.1) -- whichever is hosting us
    $hostExe = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($hostExe)) {
        $hostExe = "powershell.exe"
    }

    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"")
    foreach ($a in $ForwardArgs) {
        $argList += "`"$a`""
    }

    try {
        Start-Process -FilePath $hostExe -ArgumentList $argList -Verb RunAs -ErrorAction Stop | Out-Null
    } catch {
        $failMsg = "Failed to re-launch elevated. Run from an Administrator PowerShell. Path: $ScriptPath. Error: $($_.Exception.Message)"
        if ($LogMessages -and $LogMessages.messages.adminRelaunchFailed) {
            $failMsg = "$($LogMessages.messages.adminRelaunchFailed) Path: $ScriptPath. Error: $($_.Exception.Message)"
        }
        Write-Log $failMsg -Level "fail"
    }
    return $false
}

function Confirm-Action {
    param(
        [string]$Prompt = "Proceed? [y/N]: ",
        [switch]$AutoYes
    )
    if ($AutoYes) { return $true }
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor Yellow -NoNewline
    $reply = Read-Host
    return ($reply -match '^(y|yes)$')
}

function Format-Bytes {
    param([long]$Bytes)
    $hasBytes = $Bytes -gt 0
    if (-not $hasBytes) { return "0" }
    $mb = [Math]::Round($Bytes / 1MB, 2)
    return "$mb"
}

function Format-Gb {
    param([long]$Bytes)
    if ($Bytes -le 0) { return "0" }
    return [Math]::Round($Bytes / 1GB, 2).ToString()
}
