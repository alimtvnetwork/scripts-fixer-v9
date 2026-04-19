<# Bucket C: font-cache -- Windows font cache (stop FontCache service first) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "font-cache" -Label "Windows font cache" -Bucket "C"
$dir = Join-Path (Get-LocalAppDataPath) "Microsoft\Windows\FontCache"

if (-not (Test-Path -LiteralPath $dir)) {
    $result.Notes += "Path not present: $dir"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

if (-not $DryRun) { Stop-WindowsService -Name "FontCache" -Result $result | Out-Null }
Invoke-PathSweep -Path $dir -Result $result -DryRun:$DryRun -LogPrefix "font-cache"
if (-not $DryRun) { Start-WindowsService -Name "FontCache" -Result $result }

# Also wipe system-wide ServiceProfiles font cache
$sysCache = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache"
Invoke-PathSweep -Path $sysCache -Result $result -DryRun:$DryRun -LogPrefix "font-cache-sys"

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
