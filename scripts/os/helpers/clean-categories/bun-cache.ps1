<# Bucket F: bun-cache -- Bun's global install + module cache.
   Cleans:
     %USERPROFILE%\.bun\install\cache
     %LOCALAPPDATA%\bun-cache (older layout)
     'bun pm cache rm' invoked first when CLI is on PATH (best effort).
   SAFE: %USERPROFILE%\.bun\bin (the bun runtime + globally-linked CLIs),
         project node_modules, bun.lockb files.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "bun-cache" -Label "Bun install/module cache (.bun/bin runtime SAFE)" -Bucket "F"

if (-not $DryRun) {
    $bunCmd = Get-Command "bun" -ErrorAction SilentlyContinue
    if ($null -ne $bunCmd) {
        try {
            & bun pm cache rm 2>$null | Out-Null
            $result.Notes += "Invoked 'bun pm cache rm' before path sweep"
        } catch {
            Write-Log "bun pm cache rm failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

$candidates = @(
    (Join-Path (Get-UserProfilePath) ".bun\install\cache"),
    (Join-Path (Get-LocalAppDataPath) "bun-cache")
)

$foundAny = $false
foreach ($c in $candidates) {
    $isPresent = Test-Path -LiteralPath $c
    if (-not $isPresent) { continue }
    $foundAny = $true
    Invoke-PathSweep -Path $c -Result $result -DryRun:$DryRun -LogPrefix "bun-cache/$(Split-Path -Leaf $c)"
}

if (-not $foundAny) {
    $result.Notes += "Bun cache not present (no .bun\install\cache, no bun-cache)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
