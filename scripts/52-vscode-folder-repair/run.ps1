# --------------------------------------------------------------------------
#  Script 52 -- VS Code Folder-Only Context Menu Repair
#  Removes file + background entries, keeps only the folder entry, then
#  restarts explorer.exe so the menu refreshes immediately.
# --------------------------------------------------------------------------
param(
    [Parameter(Position = 0)]
    [string]$Command = "all",

    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sharedDir = Join-Path (Split-Path -Parent $scriptDir) "shared"

# -- Dot-source shared helpers ------------------------------------------------
. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "resolved.ps1")
. (Join-Path $sharedDir "git-pull.ps1")
. (Join-Path $sharedDir "help.ps1")
. (Join-Path $sharedDir "installed.ps1")

# -- Dot-source script helpers (also brings in script 10's registry helpers) -
. (Join-Path $scriptDir "helpers\repair.ps1")

# -- Load config & log messages -----------------------------------------------
$config      = Import-JsonConfig (Join-Path $scriptDir "config.json")
$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")

# -- Help ---------------------------------------------------------------------
if ($Help -or $Command -eq "--help") {
    Show-ScriptHelp -LogMessages $logMessages
    return
}

# -- Banner -------------------------------------------------------------------
Write-Banner -Title $logMessages.scriptName

# -- Initialize logging -------------------------------------------------------
Initialize-Logging -ScriptName $logMessages.scriptName

try {

    # -- Git pull -------------------------------------------------------------
    Invoke-GitPull

    # -- Disabled check -------------------------------------------------------
    $isDisabled = -not $config.enabled
    if ($isDisabled) {
        Write-Log $logMessages.messages.scriptDisabled -Level "warn"
        return
    }

    # -- Assert admin ---------------------------------------------------------
    Write-Log $logMessages.messages.checkingAdmin -Level "info"
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $hasAdminRights = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Log ($logMessages.messages.currentUser -replace '\{name\}', $identity.Name) -Level "info"
    Write-Log ($logMessages.messages.isAdministrator -replace '\{value\}', $hasAdminRights) -Level $(if ($hasAdminRights) { "success" } else { "error" })

    $isNotAdmin = -not $hasAdminRights
    if ($isNotAdmin) {
        Write-Log $logMessages.messages.notAdmin -Level "error"
        return
    }

    # -- Per-edition processing ----------------------------------------------
    $installType     = $config.installationType
    $enabledEditions = $config.enabledEditions
    $removeTargets   = @($config.removeFromTargets)
    $ensureTargets   = @($config.ensureOnTargets)
    $isAllSuccessful = $true

    Write-Log ($logMessages.messages.installTypePref -replace '\{type\}', $installType) -Level "info"
    Write-Log ($logMessages.messages.enabledEditions -replace '\{editions\}', ($enabledEditions -join ', ')) -Level "info"

    foreach ($editionName in $enabledEditions) {
        $edition = $config.editions.$editionName

        $isEditionMissing = -not $edition
        if ($isEditionMissing) {
            Write-Log ($logMessages.messages.unknownEdition -replace '\{name\}', $editionName) -Level "warn"
            $isAllSuccessful = $false
            continue
        }

        Write-Host ""
        Write-Host $logMessages.messages.editionBorderLine -ForegroundColor DarkCyan
        Write-Host ($logMessages.messages.editionLabel -replace '\{label\}', $edition.contextMenuLabel) -ForegroundColor Cyan
        Write-Host $logMessages.messages.editionBorderLine -ForegroundColor DarkCyan

        # Resolve VS Code exe (only required if we have ensureTargets)
        Write-Log $logMessages.messages.detectInstall -Level "info"
        $vsCodeExe = Resolve-VsCodePath `
            -PathConfig    $edition.vscodePath `
            -PreferredType $installType `
            -ScriptDir     $scriptDir `
            -EditionName   $editionName

        $hasEnsureWork = $ensureTargets.Count -gt 0
        $isExeMissing  = -not $vsCodeExe
        if ($hasEnsureWork -and $isExeMissing) {
            Write-Log ($logMessages.messages.exeNotFound -replace '\{label\}', $edition.contextMenuLabel) -Level "warn"
            # Still proceed with removal -- removal does not need the exe.
        } elseif ($vsCodeExe) {
            Write-Log ($logMessages.messages.usingExe -replace '\{path\}', $vsCodeExe) -Level "success"
        }

        # 1. Remove unwanted targets
        foreach ($target in $removeTargets) {
            $regPath = $edition.registryPaths.$target
            $hasPath = -not [string]::IsNullOrWhiteSpace($regPath)
            if (-not $hasPath) { continue }
            $ok = Remove-ContextMenuTarget -TargetName $target -RegistryPath $regPath -LogMsgs $logMessages
            if (-not $ok) { $isAllSuccessful = $false }
        }

        # 2. Ensure desired targets (folder)
        foreach ($target in $ensureTargets) {
            $regPath = $edition.registryPaths.$target
            $hasPath = -not [string]::IsNullOrWhiteSpace($regPath)
            if (-not $hasPath) { continue }
            if ($isExeMissing) {
                Write-Log ("Cannot ensure target '$target' -- VS Code executable missing for edition '$editionName' (path: $regPath)") -Level "error"
                $isAllSuccessful = $false
                continue
            }
            $ok = Set-FolderContextMenuEntry `
                -TargetName   $target `
                -RegistryPath $regPath `
                -Label        $edition.contextMenuLabel `
                -VsCodeExe    $vsCodeExe `
                -LogMsgs      $logMessages
            if (-not $ok) { $isAllSuccessful = $false }
        }

        # 3. Verify
        Write-Log $logMessages.messages.verify -Level "info"
        foreach ($target in $removeTargets) {
            $regPath = $edition.registryPaths.$target
            if ([string]::IsNullOrWhiteSpace($regPath)) { continue }
            $ok = Test-TargetState -TargetName $target -RegistryPath $regPath -Expected "absent" -LogMsgs $logMessages
            if (-not $ok) { $isAllSuccessful = $false }
        }
        foreach ($target in $ensureTargets) {
            $regPath = $edition.registryPaths.$target
            if ([string]::IsNullOrWhiteSpace($regPath)) { continue }
            $ok = Test-TargetState -TargetName $target -RegistryPath $regPath -Expected "present" -LogMsgs $logMessages
            if (-not $ok) { $isAllSuccessful = $false }
        }
    }

    # -- Restart Explorer -----------------------------------------------------
    $isNoRestartCommand = $Command.ToLower() -eq "no-restart"
    $shouldRestart      = $config.restartExplorer -and -not $isNoRestartCommand
    if ($shouldRestart) {
        $waitMs = if ($config.PSObject.Properties.Match('restartExplorerWaitMs').Count) { [int]$config.restartExplorerWaitMs } else { 800 }
        $null = Restart-Explorer -WaitMs $waitMs -LogMsgs $logMessages
    } else {
        Write-Log $logMessages.messages.explorerSkipped -Level "info"
    }

    # -- Summary --------------------------------------------------------------
    if ($isAllSuccessful) {
        Write-Log $logMessages.messages.done -Level "success"
    } else {
        Write-Log $logMessages.messages.completedWithWarnings -Level "warn"
    }

    # -- Save resolved state --------------------------------------------------
    Save-ResolvedData -ScriptFolder "52-vscode-folder-repair" -Data @{
        editions        = ($enabledEditions -join ',')
        removeTargets   = ($removeTargets   -join ',')
        ensureTargets   = ($ensureTargets   -join ',')
        restartExplorer = [bool]$shouldRestart
        timestamp       = (Get-Date -Format "o")
    }

} catch {
    Write-Log "Unhandled error: $_" -Level "error"
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level "error"
} finally {
    $hasAnyErrors = $script:_LogErrors.Count -gt 0
    Save-LogFile -Status $(if ($hasAnyErrors) { "fail" } else { "ok" })
}
