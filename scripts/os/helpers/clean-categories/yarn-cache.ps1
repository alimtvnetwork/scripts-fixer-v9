<# Bucket F: yarn-cache -- global Yarn package cache (Classic v1 + Berry v2+).
   Cleans:
     %LOCALAPPDATA%\Yarn\Cache\v6 (Berry default), %LOCALAPPDATA%\Yarn\Cache\*
     %USERPROFILE%\.yarn\berry\cache (Berry alt), %USERPROFILE%\AppData\Local\Yarn\Cache
     'yarn cache clean --all' invoked first when CLI is on PATH (best effort).
   SAFE: project node_modules, lockfiles, .yarnrc, global packages installed via 'yarn global add'.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "yarn-cache" -Label "Yarn global cache (v1 + Berry) -- projects + lockfiles SAFE" -Bucket "F"

# Best-effort 'yarn cache clean' first (CLI knows its own layout best)
if (-not $DryRun) {
    $yarnCmd = Get-Command "yarn" -ErrorAction SilentlyContinue
    if ($null -ne $yarnCmd) {
        try {
            & yarn cache clean --all 2>$null | Out-Null
            $result.Notes += "Invoked 'yarn cache clean --all' before path sweep"
        } catch {
            Write-Log "yarn cache clean failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

$candidates = @(
    (Join-Path (Get-LocalAppDataPath) "Yarn\Cache"),
    (Join-Path (Get-UserProfilePath) ".yarn\berry\cache"),
    (Join-Path (Get-UserProfilePath) ".cache\yarn")
)

$foundAny = $false
foreach ($c in $candidates) {
    $isPresent = Test-Path -LiteralPath $c
    if (-not $isPresent) { continue }
    $foundAny = $true
    Invoke-PathSweep -Path $c -Result $result -DryRun:$DryRun -LogPrefix "yarn-cache/$(Split-Path -Leaf $c)"
}

if (-not $foundAny) {
    $result.Notes += "Yarn cache not present (no Yarn\Cache, .yarn\berry\cache, .cache\yarn)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
