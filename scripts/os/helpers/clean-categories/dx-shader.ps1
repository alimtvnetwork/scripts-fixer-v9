<# Bucket C: dx-shader -- DirectX + NVIDIA + AMD shader caches #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "dx-shader" -Label "DirectX/NVIDIA/AMD shader cache" -Bucket "C"
$lad = Get-LocalAppDataPath
foreach ($rel in @("D3DSCache", "NVIDIA\GLCache", "NVIDIA\DXCache", "AMD\DxCache", "AMD\GLCache")) {
    Invoke-PathSweep -Path (Join-Path $lad $rel) -Result $result -DryRun:$DryRun -LogPrefix "dx-shader"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
