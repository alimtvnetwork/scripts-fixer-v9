<# Bucket C: web-cache -- legacy IE/Edge INetCache #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "web-cache" -Label "Legacy IE/Edge INetCache" -Bucket "C"
Invoke-PathSweep -Path (Join-Path (Get-LocalAppDataPath) "Microsoft\Windows\INetCache") `
                 -Result $result -DryRun:$DryRun -LogPrefix "inetcache"
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
