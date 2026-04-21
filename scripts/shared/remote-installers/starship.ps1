# Starship prompt -- local installer wrapper
#
# Replaces the broken upstream https://starship.rs/install.ps1 (which 404s as
# of 2026-04-20: Starship publishes only install.sh; on Windows users are
# directed to winget / scoop). This wrapper is checked into the repo so it can
# be SHA256-pinned in install-keywords.json -> remote.starship.sha256 and
# routed through the same CODE RED integrity guard as every other remote
# installer.
#
# Resolution order:
#   1. winget install --id Starship.Starship -e --source winget       (preferred)
#   2. scoop install starship                                          (fallback)
#   3. cargo install starship --locked                                 (last resort)
#
# Each step logs the exact CLI it tried and the exact reason it skipped. On
# failure it prints a [ FAIL ] block listing all three attempts so the user
# never has to guess which path the script took.

$ErrorActionPreference = "Stop"

$isInstalled = $false
$attempts    = New-Object System.Collections.ArrayList

function Test-StarshipPresent {
    $cmd = Get-Command starship -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

if (Test-StarshipPresent) {
    $existingPath = (Get-Command starship).Source
    Write-Host "  [ SKIP ] starship is already installed at: $existingPath" -ForegroundColor Yellow
    Write-Host "          version: $(starship --version 2>&1 | Select-Object -First 1)" -ForegroundColor DarkGray
    return
}

# ── 1. winget ────────────────────────────────────────────────────────
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
$hasWinget = $null -ne $wingetCmd
if ($hasWinget) {
    $cli = "winget install --id Starship.Starship -e --source winget --accept-package-agreements --accept-source-agreements"
    Write-Host "  [ STEP ] $cli" -ForegroundColor Cyan
    try {
        & winget install --id Starship.Starship -e --source winget --accept-package-agreements --accept-source-agreements
        $code = $LASTEXITCODE
        if ($code -eq 0 -or $code -eq -1978335189) {
            # -1978335189 = APPINSTALLER_CLI_ERROR_INSTALL_PACKAGE_ALREADY_INSTALLED
            $isInstalled = $true
            [void]$attempts.Add("winget: OK (exit $code)")
        } else {
            [void]$attempts.Add("winget: FAILED (exit $code) -- $cli")
        }
    } catch {
        [void]$attempts.Add("winget: THREW -- $($_.Exception.Message)  cli: $cli")
    }
} else {
    [void]$attempts.Add("winget: not present on PATH (skipped)")
}

# ── 2. scoop ─────────────────────────────────────────────────────────
if (-not $isInstalled) {
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
    $hasScoop = $null -ne $scoopCmd
    if ($hasScoop) {
        $cli = "scoop install starship"
        Write-Host "  [ STEP ] $cli" -ForegroundColor Cyan
        try {
            & scoop install starship
            $code = $LASTEXITCODE
            if ($code -eq 0) {
                $isInstalled = $true
                [void]$attempts.Add("scoop: OK")
            } else {
                [void]$attempts.Add("scoop: FAILED (exit $code) -- $cli")
            }
        } catch {
            [void]$attempts.Add("scoop: THREW -- $($_.Exception.Message)  cli: $cli")
        }
    } else {
        [void]$attempts.Add("scoop: not present on PATH (skipped)")
    }
}

# ── 3. cargo ─────────────────────────────────────────────────────────
if (-not $isInstalled) {
    $cargoCmd = Get-Command cargo -ErrorAction SilentlyContinue
    $hasCargo = $null -ne $cargoCmd
    if ($hasCargo) {
        $cli = "cargo install starship --locked"
        Write-Host "  [ STEP ] $cli" -ForegroundColor Cyan
        try {
            & cargo install starship --locked
            $code = $LASTEXITCODE
            if ($code -eq 0) {
                $isInstalled = $true
                [void]$attempts.Add("cargo: OK")
            } else {
                [void]$attempts.Add("cargo: FAILED (exit $code) -- $cli")
            }
        } catch {
            [void]$attempts.Add("cargo: THREW -- $($_.Exception.Message)  cli: $cli")
        }
    } else {
        [void]$attempts.Add("cargo: not present on PATH (skipped)")
    }
}

# ── Refresh PATH so freshly-installed starship.exe is discoverable ───
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# ── Final report ─────────────────────────────────────────────────────
Write-Host ""
if ($isInstalled -or (Test-StarshipPresent)) {
    $finalPath = if (Test-StarshipPresent) { (Get-Command starship).Source } else { "<install path>" }
    Write-Host "  [  OK  ] Starship installed: $finalPath" -ForegroundColor Green
    foreach ($a in $attempts) { Write-Host "          $a" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  Next: add to your PowerShell profile -> Invoke-Expression (&starship init powershell)" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "  [ FAIL ] Could not install Starship via any package manager." -ForegroundColor Red
    Write-Host "          Source: scripts/shared/remote-installers/starship.ps1" -ForegroundColor DarkGray
    foreach ($a in $attempts) { Write-Host "          $a" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  Install manually from: https://starship.rs/  (then re-run to verify)" -ForegroundColor Yellow
    exit 1
}
