<# Bucket A: error-reports -- Windows Error Reporting (WER) ReportArchive + ReportQueue #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "error-reports" -Label "Windows Error Reports (WER)" -Bucket "A"
$werRoot = Join-Path (Get-ProgramDataPath) "Microsoft\Windows\WER"
foreach ($sub in @("ReportArchive", "ReportQueue", "Temp")) {
    $p = Join-Path $werRoot $sub
    Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "wer/$sub"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
