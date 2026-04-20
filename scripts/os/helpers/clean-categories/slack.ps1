<# Bucket E: slack -- Cache / GPUCache only. Local Storage (login token) + IndexedDB (history) preserved. #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "slack" -Label "Slack cache (login + history preserved)" -Bucket "E"

# Standard install (Squirrel/Electron) and MS Store variant.
$candidates = @(
    (Join-Path $env:APPDATA "Slack"),
    (Join-Path $env:LOCALAPPDATA "slack"),
    (Join-Path $env:LOCALAPPDATA "Packages\91750D7E.Slack_8she8kybcnzg4\LocalCache\Roaming\Slack")
)

$found = $false
foreach ($root in $candidates) {
    $isRootMissing = -not (Test-Path -LiteralPath $root)
    if ($isRootMissing) { continue }
    $found = $true
    foreach ($sub in @("Cache", "Code Cache", "GPUCache", "logs", "Service Worker\CacheStorage")) {
        $p = Join-Path $root $sub
        Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "slack/$sub"
    }
}

if (-not $found) {
    $result.Notes += "Slack not installed"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
