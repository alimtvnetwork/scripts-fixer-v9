<# Bucket F: volta-cache -- Volta's tool installer + tarball download cache.
   Cleans:
     %LOCALAPPDATA%\Volta\cache                  (Windows default -- VOLTA_HOME\cache)
     %LOCALAPPDATA%\Volta\tmp                    (interrupted-install staging dir)
     $env:VOLTA_HOME\cache + tmp                 (when VOLTA_HOME is set explicitly)
   SAFE: every pinned tool under VOLTA_HOME\tools\image (Node/npm/yarn/pnpm runtimes),
         VOLTA_HOME\bin shims, VOLTA_HOME\hooks.json, project package.json "volta" pins.
   NOTE: Volta has no native 'volta cache clear' subcommand (as of v1.x); the cache is
         pure download artifacts (.tar.gz), and Volta re-fetches on next 'volta install'.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "volta-cache" -Label "Volta tool installer + tarball cache (pinned tools SAFE)" -Bucket "F"

# Resolve VOLTA_HOME with explicit precedence: $env:VOLTA_HOME, then %LOCALAPPDATA%\Volta.
$voltaHome = $env:VOLTA_HOME
if ([string]::IsNullOrWhiteSpace($voltaHome)) {
    $voltaHome = Join-Path (Get-LocalAppDataPath) "Volta"
}
if (-not (Test-Path -LiteralPath $voltaHome)) {
    $result.Notes += "Volta not present (no VOLTA_HOME, no $voltaHome)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}
$result.Notes += "VOLTA_HOME resolved to: $voltaHome"

# Sweep cache + tmp specifically -- never the whole VOLTA_HOME root (tools/, bin/, hooks must survive).
$subs = @("cache", "tmp")
$foundAny = $false
foreach ($sub in $subs) {
    $target = Join-Path $voltaHome $sub
    if (-not (Test-Path -LiteralPath $target)) { continue }
    $foundAny = $true
    Invoke-PathSweep -Path $target -Result $result -DryRun:$DryRun -LogPrefix "volta/$sub"
}

if (-not $foundAny) {
    $result.Notes += "VOLTA_HOME exists but cache/ and tmp/ are absent or empty (Volta re-creates on next install)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
