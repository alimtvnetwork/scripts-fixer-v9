<# Bucket E: clipchamp -- Microsoft Clipchamp video editor LocalCache + TempState #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "clipchamp" -Label "Clipchamp cache (drafts safe)" -Bucket "E"
$packagesRoot = Join-Path (Get-LocalAppDataPath) "Packages"
if (-not (Test-Path -LiteralPath $packagesRoot)) {
    $result.Notes += "Packages root not present: $packagesRoot"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$pkgs = @(Get-ChildItem -LiteralPath $packagesRoot -Directory -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like "Clipchamp.Clipchamp_*" -or $_.Name -like "Microsoft.Clipchamp_*" })
if ($pkgs.Count -eq 0) {
    $result.Notes += "Clipchamp not installed"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

foreach ($pkg in $pkgs) {
    foreach ($sub in @("LocalCache", "TempState", "AC\INetCache")) {
        Invoke-PathSweep -Path (Join-Path $pkg.FullName $sub) -Result $result -DryRun:$DryRun -LogPrefix "clipchamp/$sub"
    }
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
