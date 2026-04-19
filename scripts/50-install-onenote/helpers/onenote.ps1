# --------------------------------------------------------------------------
#  Helper: Install OneNote (choco -> direct download fallback)
#  + Remove OneNote tray icon (ONENOTEM.EXE + registry value)
#  + Disable OneDrive (process kill + scheduled tasks + autostart)
# --------------------------------------------------------------------------

# -- Bootstrap shared helpers (idempotent) ------------------------------------
$_sharedDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "shared"
$_loggingPath = Join-Path $_sharedDir "logging.ps1"
if ((Test-Path $_loggingPath) -and -not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . $_loggingPath
}
$_chocoUtilsPath = Join-Path $_sharedDir "choco-utils.ps1"
if ((Test-Path $_chocoUtilsPath) -and -not (Get-Command Install-ChocoPackage -ErrorAction SilentlyContinue)) {
    . $_chocoUtilsPath
}

function Get-OneNotePath {
    <#
    .SYNOPSIS
        Returns first found OneNote.exe path or $null.
    #>
    $candidates = @(
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\ONENOTE.EXE",
        "$env:ProgramFiles\Microsoft Office\root\Office16\ONENOTE.EXE",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ONENOTE.EXE",
        "$env:ProgramFiles\Microsoft Office\Office16\ONENOTE.EXE"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Install-OneNoteViaChoco {
    param([Parameter(Mandatory)] $OneConfig, [Parameter(Mandatory)] $LogMessages)
    $msgs = $LogMessages.messages
    Write-Log $msgs.installingChoco -Level "info"
    $ok = Install-ChocoPackage -PackageName $OneConfig.chocoPackage
    return $ok
}

function Install-OneNoteFallback {
    <#
    .SYNOPSIS
        Falls back to direct download of the Microsoft 365 OneNote desktop
        installer (Click-to-Run) from Microsoft. The previous Win10 standalone
        build (LinkID=2024522) is being sunset by Microsoft, so this URL now
        points to the current M365 OneNote variant.
    #>
    param([Parameter(Mandatory)] $OneConfig, [Parameter(Mandatory)] $LogMessages)
    $msgs = $LogMessages.messages
    $fb = $OneConfig.fallbackDownload

    if (-not $fb.enabled) {
        return $false
    }

    Write-Log ($msgs.fallbackDownload -replace '\{url\}', $fb.url) -Level "info"
    $tmpDir = Join-Path $env:TEMP "scripts-fixer-onenote"
    if (-not (Test-Path $tmpDir)) {
        New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
    }
    $installerPath = Join-Path $tmpDir $fb.fileName

    try {
        Invoke-WebRequest -Uri $fb.url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-FileError -FilePath $fb.url -Operation "download" -Reason "Failed to download OneNote installer to '$installerPath': $_" -Module "Install-OneNoteFallback"
        Write-Log ($msgs.fallbackDownloadFailed -replace '\{error\}', $_) -Level "error"
        return $false
    }

    if (-not (Test-Path $installerPath)) {
        Write-FileError -FilePath $installerPath -Operation "verify" -Reason "OneNote installer not present after download" -Module "Install-OneNoteFallback"
        return $false
    }

    Write-Log $msgs.fallbackInstalling -Level "info"
    try {
        Start-Process -FilePath $installerPath -ArgumentList $fb.silentArgs -Wait -PassThru | Out-Null
    } catch {
        Write-FileError -FilePath $installerPath -Operation "execute" -Reason "OneNote installer failed: $_" -Module "Install-OneNoteFallback"
        return $false
    }

    return $true
}

function Remove-OneNoteTray {
    param([Parameter(Mandatory)] $LogMessages)
    $msgs = $LogMessages.messages

    Write-Log $msgs.removingTray -Level "info"

    # Kill any running ONENOTEM process (the tray helper)
    $proc = Get-Process -Name "ONENOTEM" -ErrorAction SilentlyContinue
    if ($proc) {
        try {
            Stop-Process -Name "ONENOTEM" -Force -ErrorAction Stop
            Write-Log $msgs.trayRemoved -Level "success"
        } catch {
            Write-Log "Could not kill ONENOTEM process: $_" -Level "warn"
        }
    } else {
        Write-Log $msgs.trayNotPresent -Level "info"
    }

    # Remove autostart entry for the tray helper if present
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $valueNames = @("OneNote", "OneNoteTray", "ONENOTEM")
    foreach ($name in $valueNames) {
        try {
            $val = (Get-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue).$name
            if ($val) {
                Remove-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue
                Write-Log "Removed HKCU Run autostart: $name" -Level "info"
            }
        } catch { }
    }
}

function Disable-OneDrive {
    param([Parameter(Mandatory)] $LogMessages)
    $msgs = $LogMessages.messages

    Write-Log $msgs.disablingOneDrive -Level "info"

    # 1. Stop process
    $proc = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    if ($proc) {
        try {
            Stop-Process -Name "OneDrive" -Force -ErrorAction Stop
            Write-Log $msgs.oneDriveStopped -Level "success"
        } catch {
            Write-Log "Could not kill OneDrive process: $_" -Level "warn"
        }
    } else {
        Write-Log $msgs.oneDriveNotRunning -Level "info"
    }

    # 2. Disable scheduled tasks
    $disabledCount = 0
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "*OneDrive*" }
        foreach ($task in $tasks) {
            try {
                Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
                $disabledCount++
            } catch {
                Write-Log "Could not disable scheduled task '$($task.TaskName)': $_" -Level "warn"
            }
        }
    } catch {
        Write-Log "Scheduled task enumeration failed: $_" -Level "warn"
    }
    Write-Log ($msgs.oneDriveTasksDisabled -replace '\{count\}', $disabledCount) -Level "info"

    # 3. Remove autostart entry
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $val = (Get-ItemProperty -Path $runKey -Name "OneDrive" -ErrorAction SilentlyContinue).OneDrive
    if ($val) {
        try {
            Remove-ItemProperty -Path $runKey -Name "OneDrive" -ErrorAction Stop
            Write-Log $msgs.oneDriveAutostartRemoved -Level "success"
        } catch {
            Write-FileError -FilePath "$runKey\OneDrive" -Operation "delete" -Reason "Could not delete OneDrive autostart value: $_" -Module "Disable-OneDrive"
        }
    } else {
        Write-Log $msgs.oneDriveAutostartMissing -Level "info"
    }
}

function Install-OneNote {
    param(
        [Parameter(Mandatory)] $OneConfig,
        [Parameter(Mandatory)] $LogMessages
    )

    $msgs = $LogMessages.messages

    $isDisabled = -not $OneConfig.enabled
    if ($isDisabled) {
        Write-Log "OneNote install disabled in config -- skipping" -Level "info"
        return $true
    }

    Write-Log $msgs.checking -Level "info"

    $existing = Get-OneNotePath
    if ($existing) {
        $isAlreadyInstalled = Test-AlreadyInstalled -Name "onenote" -CurrentVersion "system"
        if ($isAlreadyInstalled) {
            Write-Log ($msgs.alreadyInstalled -replace '\{path\}', $existing) -Level "success"
        } else {
            Write-Log "OneNote.exe found at $existing but no tracking record -- recording" -Level "info"
            Save-InstalledRecord -Name "onenote" -Version "system" -Method "preinstalled"
        }
        # Tweaks still apply
    } else {
        Write-Log $msgs.notFound -Level "info"

        $chocoOk = Install-OneNoteViaChoco -OneConfig $OneConfig -LogMessages $LogMessages
        if (-not $chocoOk) {
            Write-Log ($msgs.chocoFailed -replace '\{error\}', "see above") -Level "warn"
            Write-Log "[NOTICE] choco onenote unreliable -- using fallback installer" -Level "warn"
            $fbOk = Install-OneNoteFallback -OneConfig $OneConfig -LogMessages $LogMessages
            if (-not $fbOk) {
                Write-Log $msgs.installFailed -Level "error"
                Save-InstalledError -Name "onenote" -ErrorMessage "Both choco and fallback installer failed"
                return $false
            }
        }

        Write-Log $msgs.installSuccess -Level "success"
        $finalPath = Get-OneNotePath
        $installMethod = if ($chocoOk) { "chocolatey" } else { "fallback-download" }
        Save-InstalledRecord -Name "onenote" -Version "system" -Method $installMethod
    }

    # -- Post-install tweaks ------------------------------------------------
    if ($OneConfig.tweaks.removeTrayIcon) {
        Remove-OneNoteTray -LogMessages $LogMessages
    }
    if ($OneConfig.tweaks.disableOneDrive) {
        Disable-OneDrive -LogMessages $LogMessages
    }

    return $true
}

function Uninstall-OneNote {
    param($OneConfig, $LogMessages)
    Write-Log ($LogMessages.messages.uninstalling -replace '\{name\}', "OneNote") -Level "info"
    $isUninstalled = Uninstall-ChocoPackage -PackageName $OneConfig.chocoPackage
    if ($isUninstalled) {
        Write-Log ($LogMessages.messages.uninstallSuccess -replace '\{name\}', "OneNote") -Level "success"
    } else {
        Write-Log ($LogMessages.messages.uninstallFailed -replace '\{name\}', "OneNote") -Level "error"
    }

    Remove-InstalledRecord -Name "onenote"
    Remove-ResolvedData -ScriptFolder "50-install-onenote"

    Write-Log $LogMessages.messages.uninstallComplete -Level "success"
}
