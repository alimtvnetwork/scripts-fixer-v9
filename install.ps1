# --------------------------------------------------------------------------
#  Scripts Fixer -- One-liner bootstrap installer
#  Usage:  irm https://raw.githubusercontent.com/alimtvnetwork/scripts-fixer-v7/main/install.ps1 | iex
#
#  Auto-discovery: probes scripts-fixer-vN repos (N = current+1..current+30)
#  in parallel and redirects to the newest published version.
#  Spec: spec/install-bootstrap/readme.md
#  Disable with: -NoUpgrade  or  $env:SCRIPTS_FIXER_NO_UPGRADE = "1"
#  Version check: -Version (shows current and latest, no install)
# --------------------------------------------------------------------------
& {
    param([switch]$NoUpgrade, [switch]$Version)

    $ErrorActionPreference = "Stop"

    # ----- Configuration ----------------------------------------------------
    $owner    = "alimtvnetwork"
    $baseName = "scripts-fixer"
    $current  = 8   # <-- bump this when this file is copied into a new -vN repo
    $folder   = Join-Path $env:USERPROFILE "scripts-fixer"
    $repo     = "https://github.com/$owner/$baseName-v$current.git"

    $probeMax = 30
    if ($env:SCRIPTS_FIXER_PROBE_MAX) {
        $parsed = 0
        if ([int]::TryParse($env:SCRIPTS_FIXER_PROBE_MAX, [ref]$parsed) -and $parsed -gt 0 -and $parsed -le 100) {
            $probeMax = $parsed
        }
    }

    Write-Host ""
    Write-Host "  Scripts Fixer -- Bootstrap Installer (v$current)" -ForegroundColor Cyan
    Write-Host ""

    # ----- Version check mode (discover + report, no clone) ----------------
    if ($Version) {
        $rangeEnd = $current + $probeMax
        Write-Host "  [VERSION] Bootstrap v$current" -ForegroundColor Cyan
        Write-Host "  [SCAN] Probing v$($current + 1)..v$rangeEnd for newer releases (parallel)..." -ForegroundColor Yellow

        $hasThreadJob = $null -ne (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
        $found = @()

        try {
            if ($hasThreadJob) {
                $jobs = @()
                foreach ($n in ($current + 1)..$rangeEnd) {
                    $url = "https://raw.githubusercontent.com/$owner/$baseName-v$n/main/install.ps1"
                    $jobs += Start-ThreadJob -ScriptBlock {
                        param($u, $v)
                        try {
                            $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                            if ($r.StatusCode -eq 200) { return $v }
                        } catch {}
                        return $null
                    } -ArgumentList $url, $n
                }
                $results = $jobs | Wait-Job -Timeout 15 | Receive-Job
                $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
                $found = @($results | Where-Object { $null -ne $_ })
            } else {
                foreach ($n in ($current + 1)..$rangeEnd) {
                    $url = "https://raw.githubusercontent.com/$owner/$baseName-v$n/main/install.ps1"
                    try {
                        $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
                        if ($r.StatusCode -eq 200) { $found += $n }
                    } catch {}
                }
            }
        } catch {
            Write-Host "  [WARN] Discovery failed: $_" -ForegroundColor Yellow
        }

        if ($found.Count -gt 0) {
            $latest = ($found | Measure-Object -Maximum).Maximum
            if ($latest -gt $current) {
                Write-Host "  [FOUND] Newer version available: v$latest" -ForegroundColor Green
                Write-Host "  [RESOLVED] Would redirect to $baseName-v$latest" -ForegroundColor Cyan
            } else {
                Write-Host "  [OK] You're on the latest (v$current)" -ForegroundColor Green
            }
        } else {
            Write-Host "  [OK] You're on the latest (v$current)" -ForegroundColor Green
        }
        Write-Host ""
        Write-Host "  (Use without -Version flag to actually install)" -ForegroundColor DarkGray
        return
    }

    # ----- Auto-discovery: probe for newer -vN repos -----------------------
    $skipDiscovery = $NoUpgrade -or $env:SCRIPTS_FIXER_NO_UPGRADE -eq "1" -or $env:SCRIPTS_FIXER_REDIRECTED -eq "1"

    if ($skipDiscovery) {
        if ($env:SCRIPTS_FIXER_REDIRECTED -eq "1") {
            Write-Host "  [SKIP] Auto-discovery skipped (already redirected)." -ForegroundColor DarkGray
        } else {
            Write-Host "  [SKIP] Auto-discovery disabled." -ForegroundColor DarkGray
        }
    } else {
        $rangeEnd = $current + $probeMax
        Write-Host "  [SCAN] Currently on v$current. Probing v$($current + 1)..v$rangeEnd for newer releases (parallel)..." -ForegroundColor Yellow

        $hasThreadJob = $null -ne (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
        $found = @()

        try {
            if ($hasThreadJob) {
                $jobs = @()
                foreach ($n in ($current + 1)..$rangeEnd) {
                    $url = "https://raw.githubusercontent.com/$owner/$baseName-v$n/main/install.ps1"
                    $jobs += Start-ThreadJob -ScriptBlock {
                        param($u, $v)
                        try {
                            $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                            if ($r.StatusCode -eq 200) { return $v }
                        } catch {}
                        return $null
                    } -ArgumentList $url, $n
                }
                $results = $jobs | Wait-Job -Timeout 15 | Receive-Job
                $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
                $found = @($results | Where-Object { $null -ne $_ })
            } else {
                # Sequential fallback (Windows PowerShell 5.1 without ThreadJob module)
                foreach ($n in ($current + 1)..$rangeEnd) {
                    $url = "https://raw.githubusercontent.com/$owner/$baseName-v$n/main/install.ps1"
                    try {
                        $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
                        if ($r.StatusCode -eq 200) { $found += $n }
                    } catch {}
                }
            }
        } catch {
            Write-Host "  [WARN] Discovery failed: $_  -- continuing with v$current" -ForegroundColor Yellow
            $found = @()
        }

        if ($found.Count -gt 0) {
            $latest = ($found | Measure-Object -Maximum).Maximum
            if ($latest -gt $current) {
                Write-Host "  [FOUND] Newer version available: v$latest" -ForegroundColor Green
                Write-Host "  [REDIRECT] Switching to $baseName-v$latest..." -ForegroundColor Cyan
                Write-Host ""
                $env:SCRIPTS_FIXER_REDIRECTED = "1"
                $newUrl = "https://raw.githubusercontent.com/$owner/$baseName-v$latest/main/install.ps1"
                try {
                    $script = (Invoke-WebRequest -Uri $newUrl -UseBasicParsing -TimeoutSec 15).Content
                    Invoke-Expression $script
                    return
                } catch {
                    Write-Host "  [WARN] Failed to fetch v$latest installer: $_  -- falling back to v$current" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [OK] You're on the latest (v$current). Continuing..." -ForegroundColor Green
            }
        } else {
            Write-Host "  [OK] You're on the latest (v$current). Continuing..." -ForegroundColor Green
        }
        Write-Host ""
    }

    # ----- Check git is available ------------------------------------------
    $hasGit = Get-Command git -ErrorAction SilentlyContinue
    if (-not $hasGit) {
        Write-Host "  [ERROR] git is not installed. Install Git first, then re-run." -ForegroundColor Red
        Write-Host "          winget install Git.Git" -ForegroundColor DarkGray
        return
    }

    # ----- Always wipe & re-clone (guarantees a clean, up-to-date checkout) -
    $hasFolder = Test-Path $folder
    if ($hasFolder) {
        Write-Host "  [CLEAN] Existing folder found at $folder -- removing for fresh clone..." -ForegroundColor Yellow
        try {
            # Clear read-only bits (git pack files often are) before removal
            Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
            Write-Host "  [OK] Removed previous folder." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Failed to remove existing folder: $folder" -ForegroundColor Red
            Write-Host "          Reason: $_" -ForegroundColor Red
            Write-Host "          Close any open file/terminal in that folder and re-run." -ForegroundColor DarkGray
            return
        }
    }

    Write-Host "  [>>] Cloning fresh into $folder ..." -ForegroundColor Yellow
    $cloneOutput = & git clone $repo $folder 2>&1
    $cloneExit = $LASTEXITCODE
    if ($cloneExit -ne 0 -or -not (Test-Path (Join-Path $folder ".git"))) {
        Write-Host "  [ERROR] Clone failed (exit $cloneExit) for repo: $repo" -ForegroundColor Red
        Write-Host "          Target folder: $folder" -ForegroundColor Red
        if ($cloneOutput) {
            Write-Host "          Git output:" -ForegroundColor DarkGray
            $cloneOutput | ForEach-Object { Write-Host "            $_" -ForegroundColor DarkGray }
        }
        Write-Host "          Check that the repo exists and your network is reachable." -ForegroundColor DarkGray
        return
    }
    Write-Host "  [OK] Cloned successfully." -ForegroundColor Green

    # ----- Launch interactive menu -----------------------------------------
    Write-Host ""
    Write-Host "  Launching interactive menu..." -ForegroundColor Cyan
    Write-Host ""
    Set-Location $folder
    & .\run.ps1 -d
} @args
