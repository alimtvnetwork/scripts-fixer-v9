<# Bucket B: explorer-mru -- Run/RecentDocs/TypedPaths registry keys #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "explorer-mru" -Label "Explorer MRU (Run/RecentDocs/TypedPaths)" -Bucket "B"

$keys = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
)

foreach ($k in $keys) {
    if (-not (Test-Path $k)) {
        $result.Notes += "Key not present: $k"
        continue
    }
    try {
        $vals = (Get-Item $k).GetValueNames()
        if ($DryRun) {
            $result.WouldCount += $vals.Count
            $result.Notes += "DRY-RUN: would clear $($vals.Count) value(s) under $k"
            continue
        }
        foreach ($v in $vals) {
            try {
                Remove-ItemProperty -Path $k -Name $v -Force -ErrorAction Stop
                $result.Count++
            } catch {
                Write-Log "explorer-mru failed at ${k}\${v}: $($_.Exception.Message)" -Level "warn"
                $result.Locked++
                $result.LockedDetails += @{ Path = "$k\$v"; Reason = (Get-LockReason -Ex $_.Exception) }
            }
        }
        # Also remove subkeys under RecentDocs (per-extension folders)
        if ($k -match "RecentDocs$") {
            Get-ChildItem -Path $k -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction Stop; $result.Count++ }
                catch { Write-Log "explorer-mru subkey failed at $($_.PSPath): $($_.Exception.Message)" -Level "warn" }
            }
        }
    } catch {
        Write-Log "explorer-mru enum failed at ${k}: $($_.Exception.Message)" -Level "warn"
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
