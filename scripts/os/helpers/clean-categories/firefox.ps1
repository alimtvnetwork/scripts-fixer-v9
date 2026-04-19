<# Bucket D: firefox -- cache2 + startupCache (cookies/history NEVER touched) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "firefox" -Label "Firefox cache (all profiles)" -Bucket "D"
$roots = @(
    (Join-Path (Get-LocalAppDataPath) "Mozilla\Firefox\Profiles"),
    (Join-Path (Get-AppDataPath) "Mozilla\Firefox\Profiles")
)
$found = $false
foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $found = $true
    $profiles = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)
    foreach ($p in $profiles) {
        foreach ($sub in @("cache2", "startupCache", "OfflineCache", "thumbnails")) {
            Invoke-PathSweep -Path (Join-Path $p.FullName $sub) -Result $result -DryRun:$DryRun -LogPrefix "firefox/$($p.Name)/$sub"
        }
    }
}
if (-not $found) { $result.Notes += "Firefox not installed" }
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
