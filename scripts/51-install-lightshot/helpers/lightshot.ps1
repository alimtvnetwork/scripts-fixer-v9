# --------------------------------------------------------------------------
#  Helper: Install Lightshot via Chocolatey + apply registry tweaks
#  Tweaks (verified for Lightshot 5.5.x at HKCU:\Software\Skillbrains\Lightshot):
#    ShowNotifications = 0     (no toast on capture / upload)
#    ShowUploadDialog  = 0     (no "upload to prntscr.com?" prompt)
#    JpegQuality       = 100   (highest quality)
#    DefaultAction     = 0     (copy to clipboard)
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

function Get-LightshotPath {
    $candidates = @(
        "$env:ProgramFiles\Skillbrains\Lightshot\Lightshot.exe",
        "${env:ProgramFiles(x86)}\Skillbrains\Lightshot\Lightshot.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Set-LightshotTweaks {
    <#
    .SYNOPSIS
        Writes the configured tweak values to HKCU:\Software\Skillbrains\Lightshot.
        Creates the key if absent.
    #>
    param(
        [Parameter(Mandatory)] $LsConfig,
        [Parameter(Mandatory)] $LogMessages
    )

    $msgs = $LogMessages.messages
    $key = $LsConfig.registryKey

    Write-Log ($msgs.applyingTweaks -replace '\{key\}', $key) -Level "info"

    if (-not (Test-Path $key)) {
        try {
            New-Item -Path $key -Force | Out-Null
        } catch {
            Write-FileError -FilePath $key -Operation "create" -Reason "Could not create Lightshot registry key: $_" -Module "Set-LightshotTweaks"
            return 0
        }
    }

    $tweaks = $LsConfig.tweaks
    $appliedCount = 0
    foreach ($name in $tweaks.PSObject.Properties.Name) {
        $value = $tweaks.$name
        try {
            Set-ItemProperty -Path $key -Name $name -Value $value -Type DWord -Force -ErrorAction Stop
            $verify = (Get-ItemProperty -Path $key -Name $name -ErrorAction Stop).$name
            if ($verify -eq $value) {
                Write-Log (($msgs.tweakApplied -replace '\{name\}', $name) -replace '\{value\}', $value) -Level "success"
                $appliedCount++
            } else {
                Write-Log "Tweak verification mismatch for $name -- expected $value, got $verify" -Level "warn"
            }
        } catch {
            Write-FileError -FilePath "$key\$name" -Operation "write" -Reason "Failed to set Lightshot tweak '$name'='$value': $_" -Module "Set-LightshotTweaks"
            Write-Log (($msgs.tweakFailed -replace '\{name\}', $name) -replace '\{error\}', $_) -Level "error"
        }
    }

    Write-Log ($msgs.tweaksComplete -replace '\{count\}', $appliedCount) -Level "success"
    return $appliedCount
}

function Install-Lightshot {
    param(
        [Parameter(Mandatory)] $LsConfig,
        [Parameter(Mandatory)] $LogMessages
    )

    $msgs = $LogMessages.messages

    $isDisabled = -not $LsConfig.enabled
    if ($isDisabled) {
        Write-Log "Lightshot install disabled in config -- skipping" -Level "info"
        return $true
    }

    Write-Log $msgs.checking -Level "info"

    $existing = Get-LightshotPath
    if ($existing) {
        $version = "unknown"
        try { $version = (Get-Item $existing).VersionInfo.ProductVersion } catch { }
        $isAlreadyInstalled = Test-AlreadyInstalled -Name "lightshot" -CurrentVersion $version
        if ($isAlreadyInstalled) {
            Write-Log ($msgs.alreadyInstalled -replace '\{path\}', $existing) -Level "success"
        } else {
            Write-Log "Lightshot.exe found at $existing but no tracking record -- recording" -Level "info"
            Save-InstalledRecord -Name "lightshot" -Version $version -Method "chocolatey"
        }
    } else {
        Write-Log $msgs.notFound -Level "info"
        Write-Log $msgs.installing -Level "info"

        $isInstalled = Install-ChocoPackage -PackageName $LsConfig.chocoPackage
        if (-not $isInstalled) {
            Write-Log ($msgs.installFailed -replace '\{error\}', "choco install lightshot returned failure") -Level "error"
            Save-InstalledError -Name "lightshot" -ErrorMessage "choco install lightshot failed"
            return $false
        }

        $installedPath = Get-LightshotPath
        if (-not $installedPath) {
            $checked = @(
                "$env:ProgramFiles\Skillbrains\Lightshot\Lightshot.exe",
                "${env:ProgramFiles(x86)}\Skillbrains\Lightshot\Lightshot.exe"
            ) -join ", "
            Write-FileError -FilePath $checked -Operation "verify" -Reason "Lightshot.exe not found after choco install -- checked: $checked" -Module "Install-Lightshot"
            Write-Log $msgs.verifyFailed -Level "error"
            Save-InstalledError -Name "lightshot" -ErrorMessage "Verify failed: Lightshot.exe missing after install"
            return $false
        }

        $version = "unknown"
        try { $version = (Get-Item $installedPath).VersionInfo.ProductVersion } catch { }

        Write-Log ($msgs.installSuccess -replace '\{path\}', $installedPath) -Level "success"
        Save-InstalledRecord -Name "lightshot" -Version $version -Method "chocolatey"
    }

    # -- Apply registry tweaks (always, even if pre-installed) --------------
    Set-LightshotTweaks -LsConfig $LsConfig -LogMessages $LogMessages | Out-Null

    return $true
}

function Uninstall-Lightshot {
    param($LsConfig, $LogMessages)
    Write-Log ($LogMessages.messages.uninstalling -replace '\{name\}', "Lightshot") -Level "info"
    $isUninstalled = Uninstall-ChocoPackage -PackageName $LsConfig.chocoPackage
    if ($isUninstalled) {
        Write-Log ($LogMessages.messages.uninstallSuccess -replace '\{name\}', "Lightshot") -Level "success"
    } else {
        Write-Log ($LogMessages.messages.uninstallFailed -replace '\{name\}', "Lightshot") -Level "error"
    }

    Remove-InstalledRecord -Name "lightshot"
    Remove-ResolvedData -ScriptFolder "51-install-lightshot"

    Write-Log $LogMessages.messages.uninstallComplete -Level "success"
}
