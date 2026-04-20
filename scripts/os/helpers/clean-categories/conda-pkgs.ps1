<# Bucket F: conda-pkgs -- Anaconda/Miniconda's package + index cache.
   Cleans:
     %USERPROFILE%\anaconda3\pkgs            (cached package tarballs + extracted dirs)
     %USERPROFILE%\miniconda3\pkgs           (Miniconda equivalent)
     %USERPROFILE%\.conda\pkgs\cache         (per-user conda channel index cache)
     'conda clean --all --yes' invoked first when CLI is on PATH (best effort).
   SAFE: every conda environment under envs\, base interpreter, .condarc,
         user notebooks, project requirements.txt / environment.yml.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "conda-pkgs" -Label "Conda package cache + index (envs + base interpreter SAFE)" -Bucket "F"

# Best-effort 'conda clean --all --yes' first (CLI is most accurate)
if (-not $DryRun) {
    $condaCmd = Get-Command "conda" -ErrorAction SilentlyContinue
    if ($null -ne $condaCmd) {
        try {
            & conda clean --all --yes 2>$null | Out-Null
            $result.Notes += "Invoked 'conda clean --all --yes' before path sweep"
        } catch {
            Write-Log "conda clean failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

$userProfile = Get-UserProfilePath
$candidates = @(
    (Join-Path $userProfile "anaconda3\pkgs"),
    (Join-Path $userProfile "miniconda3\pkgs"),
    (Join-Path $userProfile ".conda\pkgs\cache")
)

$foundAny = $false
foreach ($c in $candidates) {
    $isPresent = Test-Path -LiteralPath $c
    if (-not $isPresent) { continue }
    $foundAny = $true
    Invoke-PathSweep -Path $c -Result $result -DryRun:$DryRun -LogPrefix "conda/$(Split-Path -Leaf (Split-Path -Parent $c))/$(Split-Path -Leaf $c)"
}

if (-not $foundAny) {
    $result.Notes += "Conda not present (no anaconda3\pkgs, miniconda3\pkgs, .conda\pkgs\cache under $userProfile)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
