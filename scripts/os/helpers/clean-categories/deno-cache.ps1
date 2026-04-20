<# Bucket F: deno-cache -- Deno's module + transpilation + npm-compat cache.
   Cleans (whole DENO_DIR contents -- Deno re-fetches on next run):
     $env:DENO_DIR                          (when set explicitly)
     %LOCALAPPDATA%\deno                    (Windows default)
     'deno cache --reload' is NOT invoked (it re-downloads, defeating the purpose);
     instead we rely on path sweep -- Deno will re-populate on the next 'deno run'.
   Subfolders cleaned (each only if present):
     deps\        -- remote module cache (https://*)
     gen\         -- transpiled .js / .d.ts artifacts
     npm\         -- node_modules-compat cache (Deno 1.28+)
     registries\  -- JSR/npm registry metadata
   SAFE: Deno runtime binary (deno.exe under ~/.deno/bin or scoop/winget shim),
         your project source code, deno.json / deno.lock files,
         any DENO_INSTALL_ROOT scripts installed via 'deno install'.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "deno-cache" -Label "Deno module/transpile/npm cache (runtime + project code SAFE)" -Bucket "F"

# Resolve DENO_DIR with an explicit precedence: $env:DENO_DIR, then 'deno info --json', then default.
$denoDir = $env:DENO_DIR
$denoCmd = Get-Command "deno" -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($denoDir) -and $null -ne $denoCmd) {
    try {
        $info = & deno info --json 2>$null | ConvertFrom-Json -ErrorAction Stop
        if ($info -and $info.denoDir) { $denoDir = "$($info.denoDir)".Trim() }
    } catch {
        Write-Log "deno info probe failed: $($_.Exception.Message)" -Level "warn"
    }
}
if ([string]::IsNullOrWhiteSpace($denoDir)) {
    $denoDir = Join-Path (Get-LocalAppDataPath) "deno"
}

if (-not (Test-Path -LiteralPath $denoDir)) {
    $result.Notes += "Deno cache not present (resolved DENO_DIR = $denoDir does not exist)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$result.Notes += "DENO_DIR resolved to: $denoDir"

# Sweep known subfolders rather than the whole DENO_DIR root,
# so any future user data (e.g. install\bin shims) stays untouched.
$subs = @("deps", "gen", "npm", "registries")
$foundAny = $false
foreach ($sub in $subs) {
    $target = Join-Path $denoDir $sub
    if (-not (Test-Path -LiteralPath $target)) { continue }
    $foundAny = $true
    Invoke-PathSweep -Path $target -Result $result -DryRun:$DryRun -LogPrefix "deno/$sub"
}

if (-not $foundAny) {
    $result.Notes += "DENO_DIR exists but no known cache subfolders (deps/gen/npm/registries) under $denoDir"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
