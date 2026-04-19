<# Bucket E: discord -- Cache / Code Cache / GPUCache (NOT Local Storage = login state) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "discord" -Label "Discord cache (login preserved)" -Bucket "E"
$root = Join-Path (Get-AppDataPath) "discord"
if (-not (Test-Path -LiteralPath $root)) {
    $result.Notes += "Discord not installed"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}
foreach ($sub in @("Cache", "Code Cache", "GPUCache")) {
    Invoke-PathSweep -Path (Join-Path $root $sub) -Result $result -DryRun:$DryRun -LogPrefix "discord/$sub"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
