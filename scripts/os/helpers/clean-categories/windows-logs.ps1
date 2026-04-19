<# Bucket A: windows-logs -- CBS / DISM / WindowsUpdate logs #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "windows-logs" -Label "Windows servicing logs (CBS/DISM/WU)" -Bucket "A"
foreach ($p in @("C:\Windows\Logs\CBS", "C:\Windows\Logs\DISM", "C:\Windows\Logs\WindowsUpdate")) {
    Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -Filter "*.log" -LogPrefix "winlogs"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
