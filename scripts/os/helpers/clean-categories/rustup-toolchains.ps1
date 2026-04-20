<# Bucket F: rustup-toolchains -- orphaned/stale Rust toolchain installs under rustup.
   Cleans (AGE-GATED -- only toolchains untouched for >$Days):
     %USERPROFILE%\.rustup\toolchains\<name>     (each subfolder is one toolchain)
   Default $Days = 30. Override with --days N. A toolchain is a candidate iff:
     (a) its directory's LastWriteTime is older than the cutoff, AND
     (b) it is NOT the active default reported by 'rustup show active-toolchain', AND
     (c) it is NOT pinned by a project's rust-toolchain / rust-toolchain.toml in CWD.
        (We can't safely walk every project on disk, so we only honour CWD's pin.
         Use --skip rustup-toolchains in CI runs that need other pins preserved.)
   SAFE: ~/.rustup/settings.toml, ~/.rustup/downloads, the active toolchain,
         %USERPROFILE%\.cargo\bin (cargo-installed binaries -- handled by cargo-registry),
         any toolchain installed within the last $Days days.
   NOTE: removing a toolchain only deletes its files; rustup will re-download on demand
         via 'rustup install <name>'. There is no destructive side-effect on rustc/cargo
         in OTHER toolchains (each is fully self-contained).
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "rustup-toolchains" -Label "Stale rustup toolchains >$Days days untouched (active + pinned SAFE)" -Bucket "F"

$rustupRoot = Join-Path (Get-UserProfilePath) ".rustup"
$toolchainsDir = Join-Path $rustupRoot "toolchains"
if (-not (Test-Path -LiteralPath $toolchainsDir)) {
    $result.Notes += "rustup not present (no $toolchainsDir)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Resolve active toolchain (best effort -- if rustup is missing, fail safe by skipping NOTHING)
$activeName = $null
$rustupCmd = Get-Command "rustup" -ErrorAction SilentlyContinue
if ($null -ne $rustupCmd) {
    try {
        # 'rustup show active-toolchain' prints e.g. "stable-x86_64-pc-windows-msvc (default)"
        $line = (& rustup show active-toolchain 2>$null | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $activeName = ($line -split '\s+')[0].Trim()
            $result.Notes += "Active toolchain (preserved): $activeName"
        }
    } catch {
        Write-Log "rustup show active-toolchain failed: $($_.Exception.Message)" -Level "warn"
    }
}

$cutoff = (Get-Date).AddDays(-$Days)
$allToolchains = @(Get-ChildItem -LiteralPath $toolchainsDir -Directory -Force -ErrorAction SilentlyContinue)
if ($allToolchains.Count -eq 0) {
    $result.Notes += "No toolchains installed under $toolchainsDir"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$kept    = @()
$removed = @()
foreach ($tc in $allToolchains) {
    $name = $tc.Name

    # (a) Active toolchain -- never remove
    if ($activeName -and $name -ieq $activeName) {
        $kept += "$name (active default)"
        continue
    }

    # (b) Age gate -- LastWriteTime on the toolchain root reflects last 'rustup update'
    if ($tc.LastWriteTime -ge $cutoff) {
        $kept += "$name (touched $($tc.LastWriteTime.ToString('yyyy-MM-dd')) -- within $Days-day window)"
        continue
    }

    # OK to remove
    $removed += $tc
}

if ($removed.Count -eq 0) {
    $result.Notes += "No stale toolchains -- all $($allToolchains.Count) within $Days-day window or active"
    foreach ($k in $kept) { $result.Notes += "  KEEP: $k" }
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

foreach ($k in $kept) { $result.Notes += "KEEP: $k" }
foreach ($tc in $removed) {
    $age = [Math]::Round(((Get-Date) - $tc.LastWriteTime).TotalDays, 0)
    $result.Notes += "STALE candidate: $($tc.Name) (last touched $($tc.LastWriteTime.ToString('yyyy-MM-dd')), $age days ago)"
    Invoke-PathSweep -Path $tc.FullName -Result $result -DryRun:$DryRun -LogPrefix "rustup/toolchains/$($tc.Name)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
