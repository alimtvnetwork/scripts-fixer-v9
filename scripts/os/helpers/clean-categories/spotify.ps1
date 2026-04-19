<# Bucket E: spotify -- Storage + Browser\Cache (NOT offline downloads) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "spotify" -Label "Spotify cache (offline downloads safe)" -Bucket "E"
$root = Join-Path (Get-LocalAppDataPath) "Spotify"
if (-not (Test-Path -LiteralPath $root)) {
    $result.Notes += "Spotify not installed"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}
foreach ($sub in @("Storage", "Browser\Cache", "Data")) {
    Invoke-PathSweep -Path (Join-Path $root $sub) -Result $result -DryRun:$DryRun -LogPrefix "spotify/$sub"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
