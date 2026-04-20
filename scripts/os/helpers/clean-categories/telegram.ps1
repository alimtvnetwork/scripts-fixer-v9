<# Bucket E: telegram -- user_data\cache only (NOT chats, NOT media, NOT login) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "telegram" -Label "Telegram cache (chats + login safe)" -Bucket "E"

$appdata = Get-AppDataPath
$local   = Get-LocalAppDataPath
if ([string]::IsNullOrWhiteSpace($appdata)) {
    $result.Notes += "APPDATA not set"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Telegram Desktop install locations
$candidateRoots = @(
    (Join-Path $appdata "Telegram Desktop"),
    (Join-Path $local   "Telegram Desktop")
)

$found = $false
foreach ($root in $candidateRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $found = $true

    # cache lives under tdata\user_data\cache (and media_cache, emoji)
    $userDataDirs = @()
    try {
        $userDataDirs += Get-ChildItem -LiteralPath (Join-Path $root "tdata") -Directory -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match "^user_data" }
    } catch {
        Write-Log "telegram tdata enumerate failed at ${root}: $($_.Exception.Message)" -Level "warn"
    }

    foreach ($ud in $userDataDirs) {
        foreach ($sub in @("cache", "media_cache", "emoji")) {
            $p = Join-Path $ud.FullName $sub
            if (Test-Path -LiteralPath $p) {
                Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "telegram/$($ud.Name)/$sub"
            }
        }
    }
}

if (-not $found) {
    $result.Notes += "Telegram Desktop not installed"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
