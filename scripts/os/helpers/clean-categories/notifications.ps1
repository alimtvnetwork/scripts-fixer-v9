<# Bucket B: notifications -- wpndatabase.db #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "notifications" -Label "Windows Notifications (wpndatabase)" -Bucket "B"
$dbDir = Join-Path (Get-LocalAppDataPath) "Microsoft\Windows\Notifications"
if (-not (Test-Path -LiteralPath $dbDir)) {
    $result.Notes += "Path not present: $dbDir"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Stop notification service so file can be removed
if (-not $DryRun) { Stop-WindowsService -Name "WpnUserService*" -Result $result | Out-Null }

foreach ($pattern in @("wpndatabase.db", "wpndatabase.db-shm", "wpndatabase.db-wal", "appdb.dat")) {
    $f = Join-Path $dbDir $pattern
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $sz = Get-PathSize -Path $f
    if ($DryRun) { $result.WouldCount++; $result.WouldBytes += $sz; continue }
    try {
        Remove-Item -LiteralPath $f -Force -ErrorAction Stop
        $result.Count++; $result.Bytes += $sz
    } catch {
        $reason = Get-LockReason -Ex $_.Exception
        $result.Locked++
        $result.LockedDetails += @{ Path = $f; Reason = $reason }
        Write-Log "notifications locked at ${f}: ${reason}" -Level "warn"
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
