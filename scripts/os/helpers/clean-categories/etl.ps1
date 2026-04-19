<# Bucket A: etl -- ETW trace files #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "etl" -Label "ETW trace files (*.etl)" -Bucket "A"
foreach ($p in @("C:\Windows\System32\LogFiles\WMI", "C:\Windows\Logs")) {
    Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -Filter "*.etl" -LogPrefix "etl"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
