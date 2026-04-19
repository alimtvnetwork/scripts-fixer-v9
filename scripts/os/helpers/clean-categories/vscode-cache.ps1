<# Bucket F: vscode-cache -- Cache / CachedData / Code Cache / GPUCache / logs (workspaces SAFE) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "vscode-cache" -Label "VS Code cache + logs (workspaces safe)" -Bucket "F"
$root = Join-Path (Get-AppDataPath) "Code"
if (-not (Test-Path -LiteralPath $root)) {
    $result.Notes += "VS Code not installed (no $root)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}
foreach ($sub in @("Cache", "CachedData", "Code Cache", "GPUCache", "logs", "CachedExtensionVSIXs", "Crashpad\reports")) {
    Invoke-PathSweep -Path (Join-Path $root $sub) -Result $result -DryRun:$DryRun -LogPrefix "vscode/$sub"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
