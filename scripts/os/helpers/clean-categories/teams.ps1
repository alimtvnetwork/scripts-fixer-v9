<# Bucket E: teams -- Cache only for Classic (Electron) AND New Teams (WebView2).
   Auth tokens (Local Storage) and chat state (IndexedDB) are NEVER touched. #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "teams" -Label "Teams cache (Classic + New, auth + chat preserved)" -Bucket "E"

# Classic Teams (Electron) -- %APPDATA%\Microsoft\Teams
$classicRoot = Join-Path $env:APPDATA "Microsoft\Teams"
# New Teams (MSIX, WebView2) -- %LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache
$newTeamsRoot = Join-Path $env:LOCALAPPDATA "Packages\MSTeams_8wekyb3d8bbwe\LocalCache"

$isClassicMissing = -not (Test-Path -LiteralPath $classicRoot)
$isNewMissing     = -not (Test-Path -LiteralPath $newTeamsRoot)
if ($isClassicMissing -and $isNewMissing) {
    $result.Notes += "Teams not installed (neither Classic nor New)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

if (-not $isClassicMissing) {
    foreach ($sub in @("Cache", "Code Cache", "GPUCache", "blob_storage", "tmp", "Service Worker\CacheStorage")) {
        $p = Join-Path $classicRoot $sub
        Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "teams-classic/$sub"
    }
}

if (-not $isNewMissing) {
    # WebView2 cache lives under Microsoft\MSTeams\EBWebView\Default
    $webView = Join-Path $newTeamsRoot "Microsoft\MSTeams\EBWebView\Default"
    foreach ($sub in @("Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage")) {
        $p = Join-Path $webView $sub
        Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "teams-new/$sub"
    }
    # Logs
    $logsDir = Join-Path $newTeamsRoot "Microsoft\MSTeams\Logs"
    Invoke-PathSweep -Path $logsDir -Result $result -DryRun:$DryRun -LogPrefix "teams-new/Logs"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
