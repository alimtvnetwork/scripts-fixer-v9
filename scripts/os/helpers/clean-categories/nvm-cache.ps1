<# Bucket F: nvm-cache -- nvm-windows download tmp + per-installed-Node-version npm caches.
   Cleans:
     %APPDATA%\nvm\tmp                                     (download staging for nvm install <ver>)
     %APPDATA%\nvm\v<X.Y.Z>\node_cache                     (per-version npm cache when redirected)
     %APPDATA%\nvm\v<X.Y.Z>\.npm                           (POSIX-style npm cache when redirected)
     'nvm cache clear' is invoked when CLI is on PATH (best effort, nvm-windows >=1.1.10).
   SAFE: every installed Node version under nvm\v<X.Y.Z>\node.exe + npm\,
         the active version (nvm\nodejs symlink),
         settings.txt / .nvmrc files in projects.
   NOTE: the global npm cache (%APPDATA%\npm-cache, %LOCALAPPDATA%\npm-cache) is handled by
         the npm-cache category. This helper only walks nvm-redirected per-version caches
         to avoid double-counting.
   NOTE: this targets nvm-windows (coreybutler/nvm-windows). The POSIX nvm.sh is not Windows-native.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "nvm-cache" -Label "nvm-windows tmp + per-version npm caches (Node versions SAFE)" -Bucket "F"

# nvm-windows resolves NVM_HOME from env; fall back to %APPDATA%\nvm if unset.
$nvmHome = $env:NVM_HOME
if ([string]::IsNullOrWhiteSpace($nvmHome)) {
    $nvmHome = Join-Path (Get-AppDataPath) "nvm"
}
if (-not (Test-Path -LiteralPath $nvmHome)) {
    $result.Notes += "nvm-windows not present (no NVM_HOME, no $nvmHome)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}
$result.Notes += "NVM_HOME resolved to: $nvmHome"

# (1) Best-effort 'nvm cache clear' first (CLI removes its own tmp/ and aria2 partials)
if (-not $DryRun) {
    $nvmCmd = Get-Command "nvm" -ErrorAction SilentlyContinue
    if ($null -ne $nvmCmd) {
        try {
            & nvm cache clear 2>$null | Out-Null
            $result.Notes += "Invoked 'nvm cache clear' before path sweep"
        } catch {
            Write-Log "nvm cache clear failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

$foundAny = $false

# (2) Top-level tmp (download staging)
$tmpDir = Join-Path $nvmHome "tmp"
if (Test-Path -LiteralPath $tmpDir) {
    $foundAny = $true
    Invoke-PathSweep -Path $tmpDir -Result $result -DryRun:$DryRun -LogPrefix "nvm/tmp"
}

# (3) Per-version redirected npm caches (only present when user redirected via npm config)
$versions = @(Get-ChildItem -LiteralPath $nvmHome -Directory -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '^v\d+\.\d+\.\d+' })
foreach ($v in $versions) {
    $perVersionCandidates = @(
        (Join-Path $v.FullName "node_cache"),
        (Join-Path $v.FullName ".npm")
    )
    foreach ($pvc in $perVersionCandidates) {
        if (Test-Path -LiteralPath $pvc) {
            $foundAny = $true
            Invoke-PathSweep -Path $pvc -Result $result -DryRun:$DryRun -LogPrefix "nvm/$($v.Name)/$(Split-Path -Leaf $pvc)"
        }
    }
}
if ($versions.Count -eq 0) {
    $result.Notes += "No Node versions found under $nvmHome (nvm install <ver> first)"
} else {
    $result.Notes += "Scanned $($versions.Count) installed Node version(s) for redirected npm caches"
}

if (-not $foundAny) {
    $result.Notes += "nvm present but no caches to clean (tmp/, per-version node_cache/.npm all empty or missing)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
