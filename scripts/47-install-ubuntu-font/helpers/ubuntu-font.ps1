# --------------------------------------------------------------------------
#  Helper: Install the Ubuntu font family via Chocolatey (ubuntu.font)
#  System-wide install -- no dev-dir prompt, fonts land in %WINDIR%\Fonts.
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

function Get-UbuntuFontCount {
    <#
    .SYNOPSIS
        Counts Ubuntu*.ttf files in %WINDIR%\Fonts.
    #>
    $fontsDir = Join-Path $env:WINDIR "Fonts"
    $isFontsDirMissing = -not (Test-Path $fontsDir)
    if ($isFontsDirMissing) {
        Write-FileError -FilePath $fontsDir -Operation "read" -Reason "%WINDIR%\Fonts does not exist -- this is unusual" -Module "Get-UbuntuFontCount"
        return 0
    }
    $files = Get-ChildItem -Path $fontsDir -Filter "Ubuntu*.ttf" -File -ErrorAction SilentlyContinue
    return @($files).Count
}

function Install-UbuntuFont {
    <#
    .SYNOPSIS
        Installs ubuntu.font via Chocolatey. Returns $true on success.
    #>
    param(
        [Parameter(Mandatory)] $FontConfig,
        [Parameter(Mandatory)] $LogMessages
    )

    $msgs = $LogMessages.messages

    $isDisabled = -not $FontConfig.enabled
    if ($isDisabled) {
        Write-Log "Ubuntu font install disabled in config -- skipping" -Level "info"
        return $true
    }

    Write-Log $msgs.checking -Level "info"
    $beforeCount = Get-UbuntuFontCount

    if ($beforeCount -gt 0) {
        $isAlreadyInstalled = Test-AlreadyInstalled -Name "ubuntu-font" -CurrentVersion "system"
        if ($isAlreadyInstalled) {
            Write-Log ($msgs.alreadyInstalled -replace '\{count\}', $beforeCount) -Level "success"
            return $true
        }
        # Found files but no install record -- record and continue
        Write-Log "Found $beforeCount Ubuntu font file(s) but no tracking record -- recording and skipping reinstall" -Level "info"
        Save-InstalledRecord -Name "ubuntu-font" -Version "system" -Method "chocolatey"
        return $true
    }

    Write-Log $msgs.notFound -Level "info"
    Write-Log $msgs.installing -Level "info"

    $isInstalled = Install-ChocoPackage -PackageName $FontConfig.chocoPackage
    $hasInstallFailed = -not $isInstalled
    if ($hasInstallFailed) {
        Write-Log ($msgs.installFailed -replace '\{error\}', "choco install ubuntu.font returned failure") -Level "error"
        Save-InstalledError -Name "ubuntu-font" -ErrorMessage "choco install ubuntu.font failed"
        return $false
    }

    # -- Verify install --
    $afterCount = Get-UbuntuFontCount
    $isVerifyFailed = $afterCount -eq 0
    if ($isVerifyFailed) {
        $fontsDir = Join-Path $env:WINDIR "Fonts"
        Write-FileError -FilePath $fontsDir -Operation "verify" -Reason "No Ubuntu*.ttf files found after choco install ubuntu.font -- package layout may have changed" -Module "Install-UbuntuFont"
        Write-Log $msgs.verifyFailed -Level "error"
        Save-InstalledError -Name "ubuntu-font" -ErrorMessage "Verify failed: no Ubuntu*.ttf in %WINDIR%\Fonts after install"
        return $false
    }

    Write-Log ($msgs.installSuccess -replace '\{count\}', $afterCount) -Level "success"
    Save-InstalledRecord -Name "ubuntu-font" -Version "system" -Method "chocolatey"
    return $true
}

function Uninstall-UbuntuFont {
    param(
        $FontConfig,
        $LogMessages
    )

    $packageName = $FontConfig.chocoPackage
    Write-Log ($LogMessages.messages.uninstalling -replace '\{name\}', "Ubuntu Font") -Level "info"
    $isUninstalled = Uninstall-ChocoPackage -PackageName $packageName
    if ($isUninstalled) {
        Write-Log ($LogMessages.messages.uninstallSuccess -replace '\{name\}', "Ubuntu Font") -Level "success"
    } else {
        Write-Log ($LogMessages.messages.uninstallFailed -replace '\{name\}', "Ubuntu Font") -Level "error"
    }

    Remove-InstalledRecord -Name "ubuntu-font"
    Remove-ResolvedData -ScriptFolder "47-install-ubuntu-font"

    Write-Log $LogMessages.messages.uninstallComplete -Level "success"
}
