<# Bucket D: chrome -- Cache + Code Cache + GPUCache (cookies/history NEVER touched) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "chrome" -Label "Chrome cache (all profiles)" -Bucket "D"
$root = Join-Path (Get-LocalAppDataPath) "Google\Chrome\User Data"
if (-not (Test-Path -LiteralPath $root)) {
    $result.Notes += "Chrome not installed (no $root)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$profiles = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -eq "Default" -or $_.Name -match "^Profile \d+$" -or $_.Name -eq "Guest Profile" })
foreach ($p in $profiles) {
    foreach ($sub in @("Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage", "Service Worker\ScriptCache")) {
        Invoke-PathSweep -Path (Join-Path $p.FullName $sub) -Result $result -DryRun:$DryRun -LogPrefix "chrome/$($p.Name)/$sub"
    }
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
