<# Bucket F: pnpm-store -- pnpm's content-addressable store (CAS) of package tarballs.
   Cleans:
     %USERPROFILE%\.pnpm-store              (legacy / cross-platform default)
     %LOCALAPPDATA%\pnpm\store              (Windows default since pnpm v6+)
     %LOCALAPPDATA%\pnpm-cache              (transient HTTP cache, present on some installs)
     'pnpm store prune' invoked first when CLI is on PATH (best effort -- removes only
     unreferenced content, much safer than nuking the whole store).
   SAFE: %LOCALAPPDATA%\pnpm\* outside of \store\ (the pnpm runtime itself,
         shims under \pnpm-global, the .tool-versions / package.json files in projects,
         project node_modules symlinks resolve back from the store on next install).
   NOTE: project node_modules created with --frozen-lockfile may need a single
         'pnpm install' afterwards to repopulate from the store.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "pnpm-store" -Label "pnpm CAS store (.pnpm-store + LOCALAPPDATA\pnpm\store; runtime SAFE)" -Bucket "F"

# Best-effort 'pnpm store prune' first (only removes unreferenced content)
if (-not $DryRun) {
    $pnpmCmd = Get-Command "pnpm" -ErrorAction SilentlyContinue
    if ($null -ne $pnpmCmd) {
        try {
            & pnpm store prune 2>$null | Out-Null
            $result.Notes += "Invoked 'pnpm store prune' before path sweep (unreferenced content only)"
        } catch {
            Write-Log "pnpm store prune failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

$candidates = @(
    (Join-Path (Get-UserProfilePath) ".pnpm-store"),
    (Join-Path (Get-LocalAppDataPath) "pnpm\store"),
    (Join-Path (Get-LocalAppDataPath) "pnpm-cache")
)

$foundAny = $false
foreach ($c in $candidates) {
    $isPresent = Test-Path -LiteralPath $c
    if (-not $isPresent) { continue }
    $foundAny = $true
    # Carve LogPrefix so it stays readable: pnpm-store/<lastTwoSegments>
    $parent = Split-Path -Parent $c
    $leaf   = Split-Path -Leaf $c
    $parentLeaf = Split-Path -Leaf $parent
    Invoke-PathSweep -Path $c -Result $result -DryRun:$DryRun -LogPrefix "pnpm-store/$parentLeaf/$leaf"
}

if (-not $foundAny) {
    $result.Notes += "pnpm store not present (no .pnpm-store, LOCALAPPDATA\pnpm\store, LOCALAPPDATA\pnpm-cache)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
