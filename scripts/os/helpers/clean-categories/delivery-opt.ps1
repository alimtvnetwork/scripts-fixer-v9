<# Bucket A: delivery-opt -- Windows Update Delivery Optimization cache #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "delivery-opt" -Label "Delivery Optimization cache" -Bucket "A"
Invoke-PathSweep -Path "C:\Windows\SoftwareDistribution\DeliveryOptimization\Cache" `
                 -Result $result -DryRun:$DryRun -LogPrefix "delivery-opt"
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
