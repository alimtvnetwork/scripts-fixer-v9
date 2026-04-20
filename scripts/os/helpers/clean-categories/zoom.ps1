<# Bucket E: zoom -- Cache only. Recordings + saved chats are NEVER touched. #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "zoom" -Label "Zoom cache (recordings + chats preserved)" -Bucket "E"

$roamingRoot = Join-Path (Get-AppDataPath) "Zoom"
$localRoot   = Join-Path $env:LOCALAPPDATA "Zoom"

$isRoamingMissing = -not (Test-Path -LiteralPath $roamingRoot)
$isLocalMissing   = -not (Test-Path -LiteralPath $localRoot)
if ($isRoamingMissing -and $isLocalMissing) {
    $result.Notes += "Zoom not installed"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Roaming: data/Cache + logs (NEVER touch data/zoomus.db, recordings, or saved chats)
if (-not $isRoamingMissing) {
    foreach ($sub in @("data\Cache", "data\Logs", "logs", "Temp")) {
        $p = Join-Path $roamingRoot $sub
        Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "zoom-roaming/$sub"
    }
}

# Local: bin/aomhost cache (Electron-style)
if (-not $isLocalMissing) {
    foreach ($sub in @("Cache", "GPUCache", "Code Cache")) {
        $p = Join-Path $localRoot $sub
        Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "zoom-local/$sub"
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
