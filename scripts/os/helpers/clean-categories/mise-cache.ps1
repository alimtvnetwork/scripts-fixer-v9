<# Bucket F: mise-cache -- mise (formerly rtx) tool-version manager cache + downloads.
   Cleans:
     %LOCALAPPDATA%\mise\cache                   (Windows default -- MISE_CACHE_DIR)
     %LOCALAPPDATA%\mise\downloads               (raw download cache for installer artifacts)
     $env:MISE_CACHE_DIR (when set explicitly)   (overrides %LOCALAPPDATA%\mise\cache)
     $env:MISE_DATA_DIR\downloads (when set)     (overrides %LOCALAPPDATA%\mise\downloads)
     'mise cache clear' is invoked when CLI is on PATH (best effort, drops in-memory caches too).
   SAFE: every installed tool under MISE_DATA_DIR\installs\<plugin>\<version>,
         shims under MISE_DATA_DIR\shims, .mise.toml / .tool-versions in projects,
         the mise binary itself.
   NOTE: this is the cache + downloads only. Per-tool installs are NOT swept here --
         use 'mise prune' / 'mise uninstall' for that (mise has its own age policy).
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "mise-cache" -Label "mise cache + downloads (installed tools + shims SAFE)" -Bucket "F"

# (1) Best-effort 'mise cache clear' first (CLI flushes its own in-memory + on-disk cache atomically)
if (-not $DryRun) {
    $miseCmd = Get-Command "mise" -ErrorAction SilentlyContinue
    if ($null -ne $miseCmd) {
        try {
            & mise cache clear 2>$null | Out-Null
            $result.Notes += "Invoked 'mise cache clear' before path sweep"
        } catch {
            Write-Log "mise cache clear failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

# Resolve cache + downloads with env-var precedence
$miseCache = $env:MISE_CACHE_DIR
if ([string]::IsNullOrWhiteSpace($miseCache)) {
    $miseCache = Join-Path (Get-LocalAppDataPath) "mise\cache"
}
$miseDownloads = $null
if (-not [string]::IsNullOrWhiteSpace($env:MISE_DATA_DIR)) {
    $miseDownloads = Join-Path $env:MISE_DATA_DIR "downloads"
} else {
    $miseDownloads = Join-Path (Get-LocalAppDataPath) "mise\downloads"
}

$result.Notes += "MISE_CACHE resolved to: $miseCache"
$result.Notes += "MISE_DOWNLOADS resolved to: $miseDownloads"

$candidates = @($miseCache, $miseDownloads)
$foundAny = $false
foreach ($c in $candidates) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    $foundAny = $true
    $leaf = Split-Path -Leaf $c
    Invoke-PathSweep -Path $c -Result $result -DryRun:$DryRun -LogPrefix "mise/$leaf"
}

if (-not $foundAny) {
    $result.Notes += "mise cache + downloads not present (neither $miseCache nor $miseDownloads exists)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
