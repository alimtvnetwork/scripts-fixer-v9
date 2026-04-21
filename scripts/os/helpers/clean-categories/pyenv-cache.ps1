<# Bucket F: pyenv-cache -- pyenv-win download cache + per-installed-version pip caches.
   Cleans:
     %USERPROFILE%\.pyenv\pyenv-win\cache              (downloaded Python installer .exe + .zip)
     %USERPROFILE%\.pyenv\pyenv-win\install_cache      (alt cache name on older pyenv-win)
     %USERPROFILE%\.pyenv\pyenv-win\versions\<v>\Lib\site-packages\..\pip\cache  (per-version pip cache)
       -- discovered as: <v>\Lib\site-packages\pip\_internal\.. NOT touched (that's pip itself);
          we walk <v>\.cache\pip and AppData-style cache redirected via per-version PYTHONUSERBASE only when present.
     'pyenv rehash' is invoked AFTER sweep when CLI is on PATH (best effort -- refreshes shim metadata).
   SAFE: every installed Python interpreter under versions\<v>\python.exe + Lib\site-packages\<pkg>,
         pyenv shims (pyenv-win\shims), .python-version files in projects,
         the pyenv installer/registry itself.
   NOTE: the per-version pip cache (versions\<v>\.cache\pip) only exists when a user
         explicitly redirects pip via env var; most installs cache to %LOCALAPPDATA%\pip\Cache,
         which is handled by the separate pip-cache category. This helper avoids double-counting.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "pyenv-cache" -Label "pyenv-win download cache + per-version pip caches (interpreters SAFE)" -Bucket "F"

$pyenvRoot = Join-Path (Get-UserProfilePath) ".pyenv\pyenv-win"
if (-not (Test-Path -LiteralPath $pyenvRoot)) {
    $result.Notes += "pyenv-win not present (no $pyenvRoot)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# (1) Top-level installer caches
$topCandidates = @(
    (Join-Path $pyenvRoot "cache"),
    (Join-Path $pyenvRoot "install_cache")
)
$foundAny = $false
foreach ($c in $topCandidates) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    $foundAny = $true
    Invoke-PathSweep -Path $c -Result $result -DryRun:$DryRun -LogPrefix "pyenv/$(Split-Path -Leaf $c)"
}

# (2) Per-version pip caches (only when redirected -- skip the global pip cache, that's pip-cache category)
$versionsRoot = Join-Path $pyenvRoot "versions"
if (Test-Path -LiteralPath $versionsRoot) {
    $versions = @(Get-ChildItem -LiteralPath $versionsRoot -Directory -Force -ErrorAction SilentlyContinue)
    foreach ($v in $versions) {
        $perVersionPip = Join-Path $v.FullName ".cache\pip"
        if (Test-Path -LiteralPath $perVersionPip) {
            $foundAny = $true
            Invoke-PathSweep -Path $perVersionPip -Result $result -DryRun:$DryRun -LogPrefix "pyenv/versions/$($v.Name)/.cache/pip"
        }
    }
    if ($versions.Count -eq 0) {
        $result.Notes += "No Python versions installed under $versionsRoot"
    } else {
        $result.Notes += "Scanned $($versions.Count) installed Python version(s) for redirected pip caches"
    }
}

if (-not $foundAny) {
    $result.Notes += "pyenv-win present but no caches to clean (cache/, install_cache/, per-version .cache/pip all empty or missing)"
}

# (3) Best-effort 'pyenv rehash' AFTER sweep (refreshes shim metadata; never removes interpreters)
if (-not $DryRun) {
    $pyenvCmd = Get-Command "pyenv" -ErrorAction SilentlyContinue
    if ($null -ne $pyenvCmd) {
        try {
            & pyenv rehash 2>$null | Out-Null
            $result.Notes += "Invoked 'pyenv rehash' after sweep (shim refresh)"
        } catch {
            Write-Log "pyenv rehash failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
