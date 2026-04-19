<# Bucket G: obs-recordings -- ~/Videos *.mkv|*.mp4 older than N days (DESTRUCTIVE, consent-gated) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "obs-recordings" -Label "OBS recordings >$Days days old" -Bucket "G" -Destructive

$consented = Confirm-DestructiveCategory -Category "obs-recordings" `
    -Warning "PERMANENTLY DELETES user video files (.mkv/.mp4) under ~/Videos older than $Days days." `
    -AutoYes:$Yes -DryRun:$DryRun
if (-not $consented) {
    $result.Status = "skip"
    $result.Notes += "Consent declined"
    return $result
}

$videos = Join-Path (Get-UserProfilePath) "Videos"
if (-not (Test-Path -LiteralPath $videos)) {
    $result.Notes += "~/Videos not present"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

$cutoff = (Get-Date).AddDays(-$Days)
$old = @(Get-ChildItem -LiteralPath $videos -Recurse -Force -ErrorAction SilentlyContinue -File |
         Where-Object { ($_.Extension -ieq ".mkv" -or $_.Extension -ieq ".mp4") -and $_.LastWriteTime -lt $cutoff })

if ($old.Count -eq 0) {
    $result.Notes += "No recordings older than $Days days under $videos"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

foreach ($f in $old) {
    if ($DryRun) {
        $result.WouldCount++; $result.WouldBytes += $f.Length
        $result.Notes += "DRY-RUN: would delete $($f.FullName) ($([Math]::Round($f.Length/1MB,2)) MB, $($f.LastWriteTime.ToString('yyyy-MM-dd')))"
        continue
    }
    try {
        $sz = $f.Length
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        $result.Count++; $result.Bytes += $sz
    } catch {
        $reason = Get-LockReason -Ex $_.Exception
        $result.Locked++
        $result.LockedDetails += @{ Path = $f.FullName; Reason = $reason }
        Write-Log "obs-recordings locked at $($f.FullName): ${reason}" -Level "warn"
    }
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
