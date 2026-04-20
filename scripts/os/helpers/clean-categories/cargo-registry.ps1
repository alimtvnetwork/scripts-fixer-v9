<# Bucket F: cargo-registry -- Cargo's global registry/index/git checkout cache.
   Cleans:
     %USERPROFILE%\.cargo\registry\cache    (downloaded .crate tarballs)
     %USERPROFILE%\.cargo\registry\src      (extracted sources -- rebuilt on next build)
     %USERPROFILE%\.cargo\git\checkouts     (git-source checkouts -- recloned on demand)
     %USERPROFILE%\.cargo\git\db            (bare clones -- recloned on demand)
   SAFE: ~/.cargo/bin (installed binaries via 'cargo install'),
         ~/.cargo/config.toml, ~/.cargo/credentials.toml,
         registry\index (re-syncing it costs minutes -- left alone).
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "cargo-registry" -Label "Cargo registry cache + git checkouts (~/.cargo/bin + index SAFE)" -Bucket "F"

$cargoRoot = Join-Path (Get-UserProfilePath) ".cargo"
$hasCargo = Test-Path -LiteralPath $cargoRoot
if (-not $hasCargo) {
    $result.Notes += "Cargo not present (no $cargoRoot)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$targets = @(
    "registry\cache",
    "registry\src",
    "git\checkouts",
    "git\db"
)

foreach ($sub in $targets) {
    $target = Join-Path $cargoRoot $sub
    $isPresent = Test-Path -LiteralPath $target
    if (-not $isPresent) { continue }
    Invoke-PathSweep -Path $target -Result $result -DryRun:$DryRun -LogPrefix "cargo/$sub"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
