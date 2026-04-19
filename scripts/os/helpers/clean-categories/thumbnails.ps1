<# Bucket B: thumbnails -- thumbcache + iconcache #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "thumbnails" -Label "Thumbnail + icon cache" -Bucket "B"
$dir = Join-Path (Get-LocalAppDataPath) "Microsoft\Windows\Explorer"
if (-not (Test-Path -LiteralPath $dir)) {
    $result.Notes += "Path not present: $dir"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

foreach ($pat in @("thumbcache_*.db", "iconcache_*.db")) {
    Invoke-PathSweep -Path $dir -Result $result -DryRun:$DryRun -Filter $pat -LogPrefix "thumbnails"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
