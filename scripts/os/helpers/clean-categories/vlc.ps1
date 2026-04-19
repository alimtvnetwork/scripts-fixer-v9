<# Bucket E: vlc -- album art + media library cache (NOT vlcrc settings) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "vlc" -Label "VLC art + media library cache" -Bucket "E"
$vlcDir = Join-Path (Get-AppDataPath) "vlc"
if (-not (Test-Path -LiteralPath $vlcDir)) {
    $result.Notes += "VLC not installed (no $vlcDir)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Art cache folder
Invoke-PathSweep -Path (Join-Path $vlcDir "art") -Result $result -DryRun:$DryRun -LogPrefix "vlc/art"

# Single media-library file
foreach ($f in @("ml.xspf", "ml.db")) {
    $fp = Join-Path $vlcDir $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $sz = Get-PathSize -Path $fp
    if ($DryRun) { $result.WouldCount++; $result.WouldBytes += $sz; continue }
    try {
        Remove-Item -LiteralPath $fp -Force -ErrorAction Stop
        $result.Count++; $result.Bytes += $sz
    } catch {
        $result.Locked++
        $result.LockedDetails += @{ Path = $fp; Reason = (Get-LockReason -Ex $_.Exception) }
        Write-Log "vlc locked at ${fp}: $($_.Exception.Message)" -Level "warn"
    }
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
