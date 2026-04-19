# --------------------------------------------------------------------------
#  Git, Git LFS, and GitHub CLI helper functions
# --------------------------------------------------------------------------

# -- Bootstrap shared helpers --------------------------------------------------
$_sharedDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "shared"
$_loggingPath = Join-Path $_sharedDir "logging.ps1"
if ((Test-Path $_loggingPath) -and -not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . $_loggingPath
}


function Install-Git {
    param(
        $Config,
        $LogMessages
    )

    $packageName = $Config.chocoPackageName

    $existing = Get-Command git -ErrorAction SilentlyContinue
    if ($existing) {
        $currentVersion = try { & git --version 2>$null } catch { $null }
        $hasVersion = -not [string]::IsNullOrWhiteSpace($currentVersion)

        # Check .installed/ tracking -- skip if version matches
        if ($hasVersion) {
            $isAlreadyTracked = Test-AlreadyInstalled -Name "git" -CurrentVersion $currentVersion
            if ($isAlreadyTracked) {
                Write-Log ($LogMessages.messages.gitAlreadyInstalled -replace '\{version\}', $currentVersion) -Level "info"
                return
            }
        }

        Write-Log ($LogMessages.messages.gitAlreadyInstalled -replace '\{version\}', $currentVersion) -Level "info"

        if ($Config.alwaysUpgradeToLatest) {
            try {
                Upgrade-ChocoPackage -PackageName $packageName
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                $newVersion = try { & git --version 2>$null } catch { $null }
                $isVersionEmpty = [string]::IsNullOrWhiteSpace($newVersion)
                if ($isVersionEmpty) { $newVersion = "(version pending)" }
                Write-Log ($LogMessages.messages.gitUpgradeSuccess -replace '\{version\}', $newVersion) -Level "success"
                Save-InstalledRecord -Name "git" -Version "$newVersion".Trim()
            } catch {
                Write-Log "Git upgrade failed: $_" -Level "error"
                Save-InstalledError -Name "git" -ErrorMessage "$_"
            }
        }
    }
    else {
        Write-Log $LogMessages.messages.gitNotFound -Level "info"
        try {
            Install-ChocoPackage -PackageName $packageName

            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            $installedVersion = & git --version 2>$null
            Write-Log ($LogMessages.messages.gitInstallSuccess -replace '\{version\}', $installedVersion) -Level "success"
            Save-InstalledRecord -Name "git" -Version $installedVersion
        } catch {
            Write-Log "Git install failed: $_" -Level "error"
            Save-InstalledError -Name "git" -ErrorMessage "$_"
        }
    }
}

function Install-GitLfs {
    param(
        $Config,
        $LogMessages
    )

    $lfsConfig = $Config.gitLfs
    $isLfsDisabled = -not $lfsConfig.enabled
    if ($isLfsDisabled) { return }

    $packageName = $lfsConfig.chocoPackageName

    $existing = Get-Command git-lfs -ErrorAction SilentlyContinue
    if ($existing) {
        $currentVersion = try { & git lfs version 2>$null } catch { $null }
        $hasVersion = -not [string]::IsNullOrWhiteSpace($currentVersion)

        # Check .installed/ tracking
        if ($hasVersion) {
            $isAlreadyTracked = Test-AlreadyInstalled -Name "git-lfs" -CurrentVersion $currentVersion
            if ($isAlreadyTracked) {
                Write-Log ($LogMessages.messages.lfsAlreadyInstalled -replace '\{version\}', $currentVersion) -Level "info"
                return
            }
        }

        Write-Log ($LogMessages.messages.lfsAlreadyInstalled -replace '\{version\}', $currentVersion) -Level "info"

        if ($lfsConfig.alwaysUpgradeToLatest) {
            try {
                Upgrade-ChocoPackage -PackageName $packageName
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                $newVersion = try { & git lfs version 2>$null } catch { $null }
                $isVersionEmpty = [string]::IsNullOrWhiteSpace($newVersion)
                if ($isVersionEmpty) { $newVersion = "(version pending)" }
                Write-Log ($LogMessages.messages.lfsUpgradeSuccess -replace '\{version\}', $newVersion) -Level "success"
                Save-InstalledRecord -Name "git-lfs" -Version "$newVersion".Trim()
            } catch {
                Write-Log "Git LFS upgrade failed: $_" -Level "error"
                Save-InstalledError -Name "git-lfs" -ErrorMessage "$_"
            }
        }
    }
    else {
        Write-Log $LogMessages.messages.lfsNotFound -Level "info"
        try {
            Install-ChocoPackage -PackageName $packageName

            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            $installedVersion = & git lfs version 2>$null
            Write-Log ($LogMessages.messages.lfsInstallSuccess -replace '\{version\}', $installedVersion) -Level "success"
            Save-InstalledRecord -Name "git-lfs" -Version $installedVersion
        } catch {
            Write-Log "Git LFS install failed: $_" -Level "error"
            Save-InstalledError -Name "git-lfs" -ErrorMessage "$_"
        }
    }

    # Initialize LFS in the global git config
    & git lfs install 2>$null
    Write-Log $LogMessages.messages.lfsInitSuccess -Level "success"
}

function Install-GitHubCli {
    param(
        $Config,
        $LogMessages
    )

    $ghConfig = $Config.githubCli
    $isGhDisabled = -not $ghConfig.enabled
    if ($isGhDisabled) { return }

    $packageName = $ghConfig.chocoPackageName

    $existing = Get-Command gh -ErrorAction SilentlyContinue
    if ($existing) {
        $currentVersion = try { & gh --version 2>$null | Select-Object -First 1 } catch { $null }
        $hasVersion = -not [string]::IsNullOrWhiteSpace($currentVersion)

        # Check .installed/ tracking
        if ($hasVersion) {
            $isAlreadyTracked = Test-AlreadyInstalled -Name "github-cli" -CurrentVersion $currentVersion
            if ($isAlreadyTracked) {
                Write-Log ($LogMessages.messages.ghAlreadyInstalled -replace '\{version\}', $currentVersion) -Level "info"
                return
            }
        }

        Write-Log ($LogMessages.messages.ghAlreadyInstalled -replace '\{version\}', $currentVersion) -Level "info"

        if ($ghConfig.alwaysUpgradeToLatest) {
            try {
                Write-Log $LogMessages.messages.ghUpgrading -Level "info"
                Upgrade-ChocoPackage -PackageName $packageName
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                $newVersion = try { & gh --version 2>$null | Select-Object -First 1 } catch { $null }
                $isVersionEmpty = [string]::IsNullOrWhiteSpace($newVersion)
                if ($isVersionEmpty) { $newVersion = "(version pending)" }
                Write-Log ($LogMessages.messages.ghUpgradeSuccess -replace '\{version\}', $newVersion) -Level "success"
                Save-InstalledRecord -Name "github-cli" -Version "$newVersion".Trim()
            } catch {
                Write-Log "GitHub CLI upgrade failed: $_" -Level "error"
                Save-InstalledError -Name "github-cli" -ErrorMessage "$_"
            }
        }
    }
    else {
        Write-Log $LogMessages.messages.ghNotFound -Level "info"
        try {
            Install-ChocoPackage -PackageName $packageName

            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            $installedVersion = & gh --version 2>$null | Select-Object -First 1
            Write-Log ($LogMessages.messages.ghInstallSuccess -replace '\{version\}', $installedVersion) -Level "success"
            Save-InstalledRecord -Name "github-cli" -Version $installedVersion
        } catch {
            Write-Log "GitHub CLI install failed: $_" -Level "error"
            Save-InstalledError -Name "github-cli" -ErrorMessage "$_"
        }
    }

    # Prompt for login if configured
    if ($ghConfig.promptLogin) {
        $authStatus = & gh auth status 2>&1
        $isAuthenticated = $LASTEXITCODE -eq 0
        if ($isAuthenticated) {
            $ghUser = & gh api user --jq '.login' 2>$null
            Write-Log ($LogMessages.messages.ghAlreadyAuthenticated -replace '\{user\}', $ghUser) -Level "info"
        }
        else {
            Write-Log $LogMessages.messages.ghLoginStart -Level "info"
            & gh auth login
        }
    }
}

function Configure-GitGlobal {
    param(
        $Config,
        $LogMessages
    )

    $gc = $Config.gitConfig
    Write-Log $LogMessages.messages.configuringGit -Level "info"

    # -- user.name ---------------------------------------------------------------
    $nameConfig = $gc.userName
    $currentName = & git config --global user.name 2>$null

    if ($currentName) {
        Write-Log ($LogMessages.messages.userNameAlreadySet -replace '\{value\}', $currentName) -Level "info"
    }
    else {
        $name = $nameConfig.value
        $hasNoName = -not $name
        $hasGitNameEnv = -not [string]::IsNullOrWhiteSpace($env:GIT_USER_NAME)
        if ($hasNoName -and $hasGitNameEnv) {
            $name = $env:GIT_USER_NAME
        }
        $hasOrchestratorEnv = -not [string]::IsNullOrWhiteSpace($env:SCRIPTS_ROOT_RUN)
        if ($hasNoName -and -not $hasGitNameEnv -and $nameConfig.promptOnFirstRun -and -not $hasOrchestratorEnv) {
            $name = Read-Host $LogMessages.messages.promptUserName
        }
        if ($name) {
            & git config --global user.name $name
            Write-Log ($LogMessages.messages.settingUserName -replace '\{value\}', $name) -Level "success"
        }
    }

    # -- user.email --------------------------------------------------------------
    $emailConfig = $gc.userEmail
    $currentEmail = & git config --global user.email 2>$null

    if ($currentEmail) {
        Write-Log ($LogMessages.messages.userEmailAlreadySet -replace '\{value\}', $currentEmail) -Level "info"
    }
    else {
        $email = $emailConfig.value
        $hasNoEmail = -not $email
        $hasGitEmailEnv = -not [string]::IsNullOrWhiteSpace($env:GIT_USER_EMAIL)
        if ($hasNoEmail -and $hasGitEmailEnv) {
            $email = $env:GIT_USER_EMAIL
        }
        $hasOrchestratorEnv = -not [string]::IsNullOrWhiteSpace($env:SCRIPTS_ROOT_RUN)
        if ($hasNoEmail -and -not $hasGitEmailEnv -and $emailConfig.promptOnFirstRun -and -not $hasOrchestratorEnv) {
            $email = Read-Host $LogMessages.messages.promptUserEmail
        }
        if ($email) {
            & git config --global user.email $email
            Write-Log ($LogMessages.messages.settingUserEmail -replace '\{value\}', $email) -Level "success"
        }
    }

    # -- init.defaultBranch ------------------------------------------------------
    $branchConfig = $gc.defaultBranch
    if ($branchConfig.enabled) {
        $currentBranch = & git config --global init.defaultBranch 2>$null
        if ($currentBranch -eq $branchConfig.value) {
            Write-Log ($LogMessages.messages.defaultBranchAlreadySet -replace '\{value\}', $currentBranch) -Level "info"
        }
        else {
            & git config --global init.defaultBranch $branchConfig.value
            Write-Log ($LogMessages.messages.settingDefaultBranch -replace '\{value\}', $branchConfig.value) -Level "success"
        }
    }

    # -- credential.helper -------------------------------------------------------
    $credConfig = $gc.credentialManager
    if ($credConfig.enabled) {
        $currentCred = & git config --global credential.helper 2>$null
        if ($currentCred -eq $credConfig.helper) {
            Write-Log ($LogMessages.messages.credentialManagerAlreadySet -replace '\{value\}', $currentCred) -Level "info"
        }
        else {
            & git config --global credential.helper $credConfig.helper
            Write-Log ($LogMessages.messages.settingCredentialManager -replace '\{value\}', $credConfig.helper) -Level "success"
        }
    }

    # -- core.autocrlf -----------------------------------------------------------
    $lineConfig = $gc.lineEndings
    if ($lineConfig.enabled) {
        $currentCrlf = & git config --global core.autocrlf 2>$null
        if ($currentCrlf -eq $lineConfig.autocrlf) {
            Write-Log ($LogMessages.messages.autocrlfAlreadySet -replace '\{value\}', $currentCrlf) -Level "info"
        }
        else {
            & git config --global core.autocrlf $lineConfig.autocrlf
            Write-Log ($LogMessages.messages.settingAutocrlf -replace '\{value\}', $lineConfig.autocrlf) -Level "success"
        }
    }

    # -- core.editor -------------------------------------------------------------
    $editorConfig = $gc.editor
    if ($editorConfig.enabled) {
        $currentEditor = & git config --global core.editor 2>$null
        if ($currentEditor -eq $editorConfig.value) {
            Write-Log ($LogMessages.messages.editorAlreadySet -replace '\{value\}', $currentEditor) -Level "info"
        }
        else {
            & git config --global core.editor $editorConfig.value
            Write-Log ($LogMessages.messages.settingEditor -replace '\{value\}', $editorConfig.value) -Level "success"
        }
    }

    # -- push.autoSetupRemote ----------------------------------------------------
    $pushConfig = $gc.pushAutoSetupRemote
    if ($pushConfig.enabled) {
        $currentPush = & git config --global push.autoSetupRemote 2>$null
        $isAlreadySet = $currentPush -eq "true"
        if ($isAlreadySet) {
            Write-Log ($LogMessages.messages.pushAutoSetupAlreadySet -replace '\{value\}', $currentPush) -Level "info"
        }
        else {
            & git config --global push.autoSetupRemote true
            Write-Log $LogMessages.messages.settingPushAutoSetup -Level "success"
        }
    }
}

function Update-GitPath {
    param(
        $Config,
        $LogMessages
    )

    $isPathUpdateDisabled = -not $Config.path.updateUserPath
    if ($isPathUpdateDisabled) { return }

    $gitExe = Get-Command git -ErrorAction SilentlyContinue
    $isGitMissing = -not $gitExe
    if ($isGitMissing) { return }

    $gitDir = Split-Path -Parent $gitExe.Source

    $isAlreadyInPath = Test-InPath -Directory $gitDir
    if ($isAlreadyInPath) {
        Write-Log ($LogMessages.messages.pathAlreadyContains -replace '\{path\}', $gitDir) -Level "info"
    }
    else {
        Write-Log ($LogMessages.messages.addingToPath -replace '\{path\}', $gitDir) -Level "info"
        Add-ToUserPath -Directory $gitDir
    }
}

function Uninstall-Git {
    <#
    .SYNOPSIS
        Full Git uninstall: choco uninstall git, git-lfs, gh, purge tracking.
    #>
    param(
        $Config,
        $LogMessages
    )

    # 1. Uninstall Git
    Write-Log ($LogMessages.messages.uninstalling -replace '\{name\}', "Git") -Level "info"
    $isUninstalled = Uninstall-ChocoPackage -PackageName $Config.chocoPackageName
    if ($isUninstalled) {
        Write-Log ($LogMessages.messages.uninstallSuccess -replace '\{name\}', "Git") -Level "success"
    } else {
        Write-Log ($LogMessages.messages.uninstallFailed -replace '\{name\}', "Git") -Level "error"
    }

    # 2. Uninstall Git LFS
    $hasLfs = $Config.gitLfs.enabled
    if ($hasLfs) {
        Write-Log ($LogMessages.messages.uninstalling -replace '\{name\}', "Git LFS") -Level "info"
        Uninstall-ChocoPackage -PackageName $Config.gitLfs.chocoPackageName
    }

    # 3. Uninstall GitHub CLI
    $hasGhCli = $Config.githubCli.enabled
    if ($hasGhCli) {
        Write-Log ($LogMessages.messages.uninstalling -replace '\{name\}', "GitHub CLI") -Level "info"
        Uninstall-ChocoPackage -PackageName $Config.githubCli.chocoPackageName
    }

    # 4. Remove tracking records
    Remove-InstalledRecord -Name "git"
    Remove-InstalledRecord -Name "git-lfs"
    Remove-InstalledRecord -Name "gh"
    Remove-ResolvedData -ScriptFolder "07-install-git"

    Write-Log $LogMessages.messages.uninstallComplete -Level "success"
}
