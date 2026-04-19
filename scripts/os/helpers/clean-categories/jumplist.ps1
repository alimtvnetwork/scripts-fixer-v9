<# Bucket B: jumplist -- Recent\AutomaticDestinations + CustomDestinations #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "jumplist" -Label "Taskbar jump-lists" -Bucket "B"
$base = Join-Path (Get-AppDataPath) "Microsoft\Windows\Recent"
foreach ($sub in @("AutomaticDestinations", "CustomDestinations")) {
    Invoke-PathSweep -Path (Join-Path $base $sub) -Result $result -DryRun:$DryRun -LogPrefix "jumplist/$sub"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
