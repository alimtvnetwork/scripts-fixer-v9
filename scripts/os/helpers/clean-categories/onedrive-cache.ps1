<# Bucket E: onedrive-cache -- OneDrive client cache + logs ONLY.
   Synced files ($env:OneDrive) and account settings (settings\Personal\*.dat) are NEVER touched. #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "onedrive-cache" -Label "OneDrive client cache (synced files preserved)" -Bucket "E"

$root = Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive"
$isRootMissing = -not (Test-Path -LiteralPath $root)
if ($isRootMissing) {
    $result.Notes += "OneDrive client not installed"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Hard guard: NEVER touch the user's synced files folder.
$syncedRoot = $env:OneDrive
$hasSyncedRoot = -not [string]::IsNullOrWhiteSpace($syncedRoot)
if ($hasSyncedRoot) {
    $result.Notes += "Skipping synced root: $syncedRoot"
}

# Cache + logs only. Settings/Personal/*.dat (account binding) is excluded.
foreach ($sub in @("logs", "setup\logs", "cache")) {
    $p = Join-Path $root $sub
    Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "onedrive/$sub"
}

# Update + telemetry binaries that get re-downloaded. These are hash-named .tmp / .dwp files.
$updateDir = Join-Path $root "StandaloneUpdater"
$isUpdateDirPresent = Test-Path -LiteralPath $updateDir
if ($isUpdateDirPresent) {
    Get-ChildItem -LiteralPath $updateDir -File -Filter "*.tmp" -ErrorAction SilentlyContinue | ForEach-Object {
        Invoke-PathSweep -Path $_.FullName -Result $result -DryRun:$DryRun -LogPrefix "onedrive/StandaloneUpdater"
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
