<#
.SYNOPSIS
    Inline helpers callable from profile config.json via { kind: "inline", function: "<name>" }.

.DESCRIPTION
    Each function takes -RootDir, -AutoYes, and -Step (the raw step hashtable
    from config) and returns nothing on success or throws on failure.
    The executor catches throws and marks the step as 'fail'.

    Available functions:
      Install-PSReadLineLatest -- updates PSReadLine to latest from PSGallery
      Setup-SshKey             -- detect / generate ed25519 SSH key
      Setup-GitHubDir          -- create $HOME\GitHub default folder
      Apply-DefaultGitConfig   -- merge default-gitconfig template into ~\.gitconfig
#>

function Install-PSReadLineLatest {
    param(
        [string]$RootDir,
        [bool]$AutoYes,
        [hashtable]$Step
    )
    Write-Log "PSReadLine: ensuring latest from PSGallery..." -Level "info"

    # Trust PSGallery silently
    try {
        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($repo -and $repo.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
    } catch {}

    Install-Module -Name PSReadLine -Force -SkipPublisherCheck -AcceptLicense -Scope CurrentUser -ErrorAction Stop

    $mod = Get-Module -Name PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($mod) {
        Write-Log "PSReadLine installed: version $($mod.Version)" -Level "success"
    } else {
        throw "PSReadLine module not found after install."
    }
}

function Setup-SshKey {
    param(
        [string]$RootDir,
        [bool]$AutoYes,
        [hashtable]$Step
    )
    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    $keyFile = Join-Path $sshDir "id_ed25519"
    $hasKey = Test-Path $keyFile

    if ($hasKey) {
        Write-Log "SSH key already exists: $keyFile (skipping generation)" -Level "info"
    } else {
        $sshKeygen = Get-Command "ssh-keygen" -ErrorAction SilentlyContinue
        if (-not $sshKeygen) {
            throw "ssh-keygen not found in PATH. Install Git for Windows (which bundles OpenSSH) or run script 07 first."
        }

        # Read git user.email if available, else fall back to hostname@local
        $email = $null
        $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
        if ($gitCmd) {
            try {
                $email = (& git config --global user.email 2>$null).Trim()
            } catch {}
        }
        if ([string]::IsNullOrWhiteSpace($email)) {
            $email = "$env:USERNAME@$env:COMPUTERNAME"
        }

        if (-not $AutoYes) {
            Write-Host "  [ INFO ] Generating SSH key for: $email" -ForegroundColor Cyan
            Write-Host "  [ INFO ] Press Enter at the passphrase prompt for no passphrase, or supply one." -ForegroundColor DarkGray
        }
        & ssh-keygen -t ed25519 -C "$email" -f "$keyFile" -N '""' 2>&1 | Out-Null
        if (-not (Test-Path $keyFile)) {
            throw "ssh-keygen did not produce the expected key at $keyFile"
        }
        Write-Log "SSH key generated at $keyFile" -Level "success"
    }

    $pubKey = "$keyFile.pub"
    if (Test-Path $pubKey) {
        $contents = Get-Content $pubKey -Raw
        Write-Host ""
        Write-Host "  Your public key (copy this to GitHub/GitLab/Bitbucket):" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    $contents" -ForegroundColor White
        Write-Host ""
        try {
            Set-Clipboard -Value $contents
            Write-Host "  [ INFO ] Public key copied to clipboard." -ForegroundColor Cyan
        } catch {}
    }
}

function Setup-GitHubDir {
    param(
        [string]$RootDir,
        [bool]$AutoYes,
        [hashtable]$Step
    )
    $defaultDir = Join-Path $env:USERPROFILE "GitHub"
    if (-not (Test-Path $defaultDir)) {
        New-Item -ItemType Directory -Path $defaultDir -Force | Out-Null
        Write-Log "Created default GitHub directory at $defaultDir" -Level "success"
    } else {
        Write-Log "Default GitHub directory already exists at $defaultDir" -Level "info"
    }

    Write-Host ""
    Write-Host "  [ INFO ] To add this folder to GitHub Desktop:" -ForegroundColor Cyan
    Write-Host "          Open GitHub Desktop -> File -> Add Local Repository -> select $defaultDir" -ForegroundColor DarkGray
    Write-Host "          (GitHub Desktop has no public CLI to do this programmatically.)" -ForegroundColor DarkGray
    Write-Host ""
}

function Apply-DefaultGitConfig {
    param(
        [string]$RootDir,
        [bool]$AutoYes,
        [hashtable]$Step
    )
    $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        throw "git not found in PATH. Run script 07 first."
    }

    # Existing user.name / user.email are preserved if already set
    $existingName  = (& git config --global user.name 2>$null)
    $existingEmail = (& git config --global user.email 2>$null)

    if ([string]::IsNullOrWhiteSpace($existingName)) {
        if (-not $AutoYes) {
            Write-Host ""
            Write-Host "  Enter git user.name (default: Alim Ul Karim): " -ForegroundColor Yellow -NoNewline
            $name = Read-Host
            if ([string]::IsNullOrWhiteSpace($name)) { $name = "Alim Ul Karim" }
        } else {
            $name = "Alim Ul Karim"
        }
        & git config --global user.name "$name" | Out-Null
        Write-Log "Set git user.name = $name" -Level "success"
    } else {
        Write-Log "git user.name already set: $existingName (kept)" -Level "info"
    }

    if ([string]::IsNullOrWhiteSpace($existingEmail)) {
        if (-not $AutoYes) {
            Write-Host "  Enter git user.email: " -ForegroundColor Yellow -NoNewline
            $em = Read-Host
            if (-not [string]::IsNullOrWhiteSpace($em)) {
                & git config --global user.email "$em" | Out-Null
                Write-Log "Set git user.email = $em" -Level "success"
            } else {
                Write-Log "Skipped git user.email (no value provided)" -Level "warn"
            }
        }
    } else {
        Write-Log "git user.email already set: $existingEmail (kept)" -Level "info"
    }

    # LFS filter block
    & git config --global filter.lfs.clean   "git-lfs clean -- %f"          | Out-Null
    & git config --global filter.lfs.smudge  "git-lfs smudge -- %f"         | Out-Null
    & git config --global filter.lfs.process "git-lfs filter-process"       | Out-Null
    & git config --global filter.lfs.required true                          | Out-Null

    # safe.directory = *
    & git config --global --replace-all safe.directory "*" | Out-Null

    # gitlab insteadOf rewrite
    & git config --global url."ssh://git@gitlab.com/".insteadOf "https://gitlab.com/" | Out-Null

    Write-Log "Applied default git config (LFS filters, safe.directory=*, gitlab url rewrite)" -Level "success"
}
