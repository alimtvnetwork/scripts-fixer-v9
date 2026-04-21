<#
.SYNOPSIS
    Helpers for the folder-only VS Code context menu repair (script 52).

.DESCRIPTION
    Reuses the registry conversion + VS Code path resolution helpers from
    script 10. Adds focused remove / ensure / verify operations that operate
    only on the targets listed in config.json (removeFromTargets,
    ensureOnTargets) plus an explorer.exe restart routine.
#>

# -- Bootstrap shared logging --------------------------------------------------
$_sharedDir   = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "shared"
$_loggingPath = Join-Path $_sharedDir "logging.ps1"
if ((Test-Path $_loggingPath) -and -not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . $_loggingPath
}

# -- Reuse helpers from script 10 ---------------------------------------------
$_script10Helpers = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "10-vscode-context-menu-fix\helpers\registry.ps1"
if (Test-Path $_script10Helpers) {
    . $_script10Helpers
} else {
    throw "Required helper not found: $_script10Helpers (script 10 must remain present)"
}

function ConvertTo-RegPathLocal {
    # Local alias for ConvertTo-RegPath in case caller needs it without dot-source order issues.
    param([string]$PsPath)
    return (ConvertTo-RegPath $PsPath)
}

function Remove-ContextMenuTarget {
    <#
    .SYNOPSIS
        Removes a single registry-based context menu entry and its \command subkey.
        Logs exact path + reason on every failure (CODE RED rule).
    #>
    param(
        [string]$TargetName,
        [string]$RegistryPath,
        [PSObject]$LogMsgs
    )

    $regPath = ConvertTo-RegPath $RegistryPath
    $isPresent = $false
    $null = reg.exe query $regPath 2>&1
    $isPresent = ($LASTEXITCODE -eq 0)

    if (-not $isPresent) {
        Write-Log (($LogMsgs.messages.targetMissing -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath) -Level "info"
        return $true
    }

    Write-Log (($LogMsgs.messages.removingTarget -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath) -Level "info"

    try {
        $null = reg.exe delete $regPath /f 2>&1
        $hasFailed = ($LASTEXITCODE -ne 0)
        if ($hasFailed) {
            $msg = ($LogMsgs.messages.removeFailed -replace '\{target\}', $TargetName) `
                                                   -replace '\{path\}',   $regPath `
                                                   -replace '\{error\}',  ("reg.exe exit " + $LASTEXITCODE)
            Write-Log $msg -Level "error"
            return $false
        }
        Write-Log (($LogMsgs.messages.removed -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath) -Level "success"
        return $true
    } catch {
        $msg = ($LogMsgs.messages.removeFailed -replace '\{target\}', $TargetName) `
                                               -replace '\{path\}',   $regPath `
                                               -replace '\{error\}',  $_
        Write-Log $msg -Level "error"
        return $false
    }
}

function Set-FolderContextMenuEntry {
    <#
    .SYNOPSIS
        Ensures the folder (Directory) context menu entry exists with correct
        label, icon and command pointing at the resolved VS Code executable.
    #>
    param(
        [string]$TargetName,
        [string]$RegistryPath,
        [string]$Label,
        [string]$VsCodeExe,
        [PSObject]$LogMsgs
    )

    $regPath  = ConvertTo-RegPath $RegistryPath
    $iconVal  = "`"$VsCodeExe`""
    $cmdArg   = "`"$VsCodeExe`" `"%V`""

    Write-Log (($LogMsgs.messages.ensuringTarget -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath) -Level "info"

    try {
        $subKeyPath = $RegistryPath -replace '^Registry::HKEY_CLASSES_ROOT\\', ''
        $hkcr = [Microsoft.Win32.Registry]::ClassesRoot

        $key = $hkcr.CreateSubKey($subKeyPath)
        $key.SetValue("",     $Label)
        $key.SetValue("Icon", $iconVal)
        $key.Close()

        $cmdKey = $hkcr.CreateSubKey("$subKeyPath\command")
        $cmdKey.SetValue("", $cmdArg)
        $cmdKey.Close()

        $msg = ($LogMsgs.messages.ensureSet -replace '\{target\}', $TargetName) `
                                            -replace '\{label\}',  $Label `
                                            -replace '\{path\}',   $regPath
        Write-Log $msg -Level "success"
        return $true
    } catch {
        $msg = ($LogMsgs.messages.ensureFailed -replace '\{target\}', $TargetName) `
                                               -replace '\{path\}',   $regPath `
                                               -replace '\{error\}',  $_
        Write-Log $msg -Level "error"
        return $false
    }
}

function Test-TargetState {
    <#
    .SYNOPSIS
        Verifies a target is in the expected state (present | absent).
    #>
    param(
        [string]$TargetName,
        [string]$RegistryPath,
        [ValidateSet("present","absent")][string]$Expected,
        [PSObject]$LogMsgs
    )

    $regPath = ConvertTo-RegPath $RegistryPath
    $null = reg.exe query $regPath 2>&1
    $isPresent = ($LASTEXITCODE -eq 0)

    if ($Expected -eq "absent") {
        if ($isPresent) {
            Write-Log (($LogMsgs.messages.unexpectedPresent -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath) -Level "error"
            return $false
        }
        Write-Log (($LogMsgs.messages.expectedAbsent -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath) -Level "success"
        return $true
    }

    if ($isPresent) {
        Write-Log (($LogMsgs.messages.expectedPresent -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath) -Level "success"
        return $true
    }
    Write-Log (($LogMsgs.messages.unexpectedAbsent -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath) -Level "error"
    return $false
}

function Restart-Explorer {
    <#
    .SYNOPSIS
        Stops and restarts explorer.exe so context menu changes take effect
        without requiring a full sign-out.
    #>
    param(
        [int]$WaitMs = 800,
        [PSObject]$LogMsgs
    )

    Write-Log $LogMsgs.messages.restartingExplorer -Level "info"
    try {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Kill() } catch { }
        }
        Write-Log $LogMsgs.messages.explorerStopped -Level "success"

        Start-Sleep -Milliseconds $WaitMs

        $isExplorerStillRunning = $null -ne (Get-Process -Name explorer -ErrorAction SilentlyContinue)
        if (-not $isExplorerStillRunning) {
            Start-Process -FilePath "explorer.exe" | Out-Null
        }
        Write-Log $LogMsgs.messages.explorerStarted -Level "success"
        return $true
    } catch {
        Write-Log ($LogMsgs.messages.explorerFailed -replace '\{error\}', $_) -Level "error"
        return $false
    }
}
