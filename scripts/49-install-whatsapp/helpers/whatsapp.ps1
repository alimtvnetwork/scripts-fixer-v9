# --------------------------------------------------------------------------
#  Helper: Install WhatsApp Desktop via Chocolatey
#  Skips Microsoft Store -- per user decision (locked in 2025-batch spec).
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

function Get-WhatsAppPath {
    <#
    .SYNOPSIS
        Searches for WhatsApp.exe in common install locations.
        Returns the path string or $null.
    #>
    $candidates = @(
        "$env:LOCALAPPDATA\WhatsApp\WhatsApp.exe",
        "$env:LOCALAPPDATA\Programs\WhatsApp\WhatsApp.exe",
        "$env:ProgramFiles\WhatsApp\WhatsApp.exe",
        "${env:ProgramFiles(x86)}\WhatsApp\WhatsApp.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Install-WhatsApp {
    <#
    .SYNOPSIS
        Installs WhatsApp Desktop via Chocolatey. Returns $true on success.
    #>
    param(
        [Parameter(Mandatory)] $WaConfig,
        [Parameter(Mandatory)] $LogMessages
    )

    $msgs = $LogMessages.messages

    $isDisabled = -not $WaConfig.enabled
    if ($isDisabled) {
        Write-Log "WhatsApp install disabled in config -- skipping" -Level "info"
        return $true
    }

    Write-Log $msgs.checking -Level "info"

    $existing = Get-WhatsAppPath
    if ($existing) {
        $version = "unknown"
        try { $version = (Get-Item $existing).VersionInfo.ProductVersion } catch { }
        $isAlreadyInstalled = Test-AlreadyInstalled -Name "whatsapp" -CurrentVersion $version
        if ($isAlreadyInstalled) {
            Write-Log ($msgs.alreadyInstalled -replace '\{path\}', $existing) -Level "success"
            return $true
        }
        Write-Log "WhatsApp.exe found at $existing but no tracking record -- recording" -Level "info"
        Save-InstalledRecord -Name "whatsapp" -Version $version -Method "chocolatey"
        return $true
    }

    Write-Log $msgs.notFound -Level "info"
    Write-Log $msgs.installing -Level "info"

    $isInstalled = Install-ChocoPackage -PackageName $WaConfig.chocoPackage
    if (-not $isInstalled) {
        Write-Log ($msgs.installFailed -replace '\{error\}', "choco install whatsapp returned failure") -Level "error"
        Save-InstalledError -Name "whatsapp" -ErrorMessage "choco install whatsapp failed"
        return $false
    }

    # -- Verify ---------------------------------------------------------------
    $installedPath = Get-WhatsAppPath
    if (-not $installedPath) {
        $checked = @(
            "$env:LOCALAPPDATA\WhatsApp\WhatsApp.exe",
            "$env:LOCALAPPDATA\Programs\WhatsApp\WhatsApp.exe",
            "$env:ProgramFiles\WhatsApp\WhatsApp.exe",
            "${env:ProgramFiles(x86)}\WhatsApp\WhatsApp.exe"
        ) -join ", "
        Write-FileError -FilePath $checked -Operation "verify" -Reason "WhatsApp.exe not found after choco install -- checked: $checked" -Module "Install-WhatsApp"
        Write-Log $msgs.verifyFailed -Level "error"
        Save-InstalledError -Name "whatsapp" -ErrorMessage "Verify failed: WhatsApp.exe not in expected locations after install"
        return $false
    }

    $version = "unknown"
    try { $version = (Get-Item $installedPath).VersionInfo.ProductVersion } catch { }

    Write-Log ($msgs.installSuccess -replace '\{path\}', $installedPath) -Level "success"
    Save-InstalledRecord -Name "whatsapp" -Version $version -Method "chocolatey"
    return $true
}

function Uninstall-WhatsApp {
    param($WaConfig, $LogMessages)

    Write-Log ($LogMessages.messages.uninstalling -replace '\{name\}', "WhatsApp") -Level "info"
    $isUninstalled = Uninstall-ChocoPackage -PackageName $WaConfig.chocoPackage
    if ($isUninstalled) {
        Write-Log ($LogMessages.messages.uninstallSuccess -replace '\{name\}', "WhatsApp") -Level "success"
    } else {
        Write-Log ($LogMessages.messages.uninstallFailed -replace '\{name\}', "WhatsApp") -Level "error"
    }

    Remove-InstalledRecord -Name "whatsapp"
    Remove-ResolvedData -ScriptFolder "49-install-whatsapp"

    Write-Log $LogMessages.messages.uninstallComplete -Level "success"
}
