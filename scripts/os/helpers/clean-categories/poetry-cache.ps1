<# Bucket F: poetry-cache -- Python Poetry's package + virtualenv-builder cache.
   Cleans:
     %LOCALAPPDATA%\pypoetry\Cache           (Windows default -- POETRY_CACHE_DIR)
     %USERPROFILE%\.cache\pypoetry           (POSIX-style fallback used by some installs)
     'poetry cache clear --all PyPI --no-interaction' invoked when CLI is on PATH (best effort).
   SAFE: every project's pyproject.toml / poetry.lock,
         already-created venvs under <project>\.venv,
         the Poetry tool itself (~/AppData/Roaming/Python/Scripts/poetry.exe).
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "poetry-cache" -Label "Poetry package + venv-builder cache (pyproject + .venv SAFE)" -Bucket "F"

# Best-effort 'poetry cache clear --all PyPI' first
if (-not $DryRun) {
    $poetryCmd = Get-Command "poetry" -ErrorAction SilentlyContinue
    if ($null -ne $poetryCmd) {
        try {
            & poetry cache clear --all PyPI --no-interaction 2>$null | Out-Null
            $result.Notes += "Invoked 'poetry cache clear --all PyPI --no-interaction' before path sweep"
        } catch {
            Write-Log "poetry cache clear failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

$candidates = @(
    (Join-Path (Get-LocalAppDataPath) "pypoetry\Cache"),
    (Join-Path (Get-UserProfilePath) ".cache\pypoetry")
)

$foundAny = $false
foreach ($c in $candidates) {
    $isPresent = Test-Path -LiteralPath $c
    if (-not $isPresent) { continue }
    $foundAny = $true
    Invoke-PathSweep -Path $c -Result $result -DryRun:$DryRun -LogPrefix "poetry/$(Split-Path -Leaf (Split-Path -Parent $c))"
}

if (-not $foundAny) {
    $result.Notes += "Poetry cache not present (no pypoetry\Cache under LOCALAPPDATA, no .cache\pypoetry under USERPROFILE)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
