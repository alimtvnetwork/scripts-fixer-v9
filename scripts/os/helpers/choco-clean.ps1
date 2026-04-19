<#
.SYNOPSIS
    Internal helper: clean Chocolatey cache / leftovers WITHOUT touching the live install.

.DESCRIPTION
    What this DELETES (safe -- choco re-creates / re-downloads on demand):
      * C:\ProgramData\chocolatey\lib-bad\*    (failed install leftovers)
      * C:\ProgramData\chocolatey\lib-bkp\*    (upgrade backups)
      * C:\ProgramData\chocolatey\.chocolatey\*\.backup  (per-package upgrade backups)
      * C:\ProgramData\chocolatey\lib\*\*.nupkg          (cached package files)
      * %TEMP%\chocolatey\*                              (download/extraction temp)
      * runs `choco-cleaner` if installed (community extension)

    What this LEAVES ALONE (the live install -- never touched):
      * C:\ProgramData\chocolatey\bin
      * C:\ProgramData\chocolatey\lib\<pkg>\tools  (executables / runtime)
      * C:\ProgramData\chocolatey\config
      * C:\ProgramData\chocolatey\logs

    CODE RED: every Remove-Item failure logs the exact path + reason.
    Locked files are caught + reported, never crash the script.

.NOTES
    Dot-sourced by clean.ps1. Returns a hashtable:
      @{ Count = N; Bytes = N; Locked = N; LockedDetails = @(...); Status = "ok"|"warn"|"skip" }
#>

function Invoke-ChocoCacheClean {
    param(
        [Parameter(Mandatory)][PSObject]$Config,
        [Parameter(Mandatory)][PSObject]$LogMessages,
        [int]$StepNum = 0
    )

    $result = [ordered]@{
        Step   = $StepNum
        Label  = "Chocolatey cache (lib-bad, lib-bkp, *.nupkg, .backup, TEMP)"
        Count  = 0
        Bytes  = 0
        Locked = 0
        LockedDetails = @()
        Status = "ok"
    }

    $chocoRoot = $Config.choco.root
    if (-not (Test-Path $chocoRoot)) {
        Write-Log $LogMessages.clean.chocoNotInstalled -Level "skip"
        $result.Status = "skip"
        return $result
    }

    Write-Log $LogMessages.clean.chocoCleanStart -Level "info"

    function Get-LockReasonLocal {
        param([System.Exception]$Ex)
        if ($null -eq $Ex) { return "unknown error" }
        $m = $Ex.Message
        if ($m -match "being used by another process|in use") { return "in use by another process" }
        if ($m -match "denied|UnauthorizedAccess")            { return "access denied (locked or protected)" }
        if ($m -match "sharing violation")                    { return "sharing violation (open handle)" }
        return $m.Split("`n")[0].Trim()
    }

    function Get-PathSize {
        param([string]$P)
        try {
            if (-not (Test-Path $P)) { return 0 }
            $i = Get-Item -LiteralPath $P -Force -ErrorAction SilentlyContinue
            if ($null -eq $i) { return 0 }
            if ($i.PSIsContainer) {
                $sum = (Get-ChildItem -Path $P -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { -not $_.PSIsContainer } |
                        Measure-Object -Property Length -Sum).Sum
                if ($null -eq $sum) { return 0 }
                return [long]$sum
            }
            return [long]$i.Length
        } catch { return 0 }
    }

    # 1. Targeted folders: lib-bad, lib-bkp -- wipe their CONTENTS (keep the folder itself)
    foreach ($folder in $Config.choco.cleanPaths) {
        if (-not (Test-Path $folder)) { continue }
        $items = Get-ChildItem -Path $folder -Force -ErrorAction SilentlyContinue
        foreach ($it in $items) {
            $sz = Get-PathSize -P $it.FullName
            try {
                Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop
                $result.Count++
                $result.Bytes += $sz
            } catch {
                $reason = Get-LockReasonLocal -Ex $_.Exception
                $result.Locked++
                $result.LockedDetails += @{ Path = $it.FullName; Reason = $reason }
                Write-Log "Choco clean locked at $($it.FullName): ${reason}" -Level "warn"
            }
        }
    }

    # 2. Per-package .backup folders under .chocolatey
    try {
        $backups = Get-Item -Path $Config.choco.backupGlob -Force -ErrorAction SilentlyContinue
        foreach ($b in $backups) {
            $sz = Get-PathSize -P $b.FullName
            try {
                Remove-Item -LiteralPath $b.FullName -Recurse -Force -ErrorAction Stop
                $result.Count++
                $result.Bytes += $sz
            } catch {
                $reason = Get-LockReasonLocal -Ex $_.Exception
                $result.Locked++
                $result.LockedDetails += @{ Path = $b.FullName; Reason = $reason }
                Write-Log "Choco backup locked at $($b.FullName): ${reason}" -Level "warn"
            }
        }
    } catch {
        Write-Log "Choco backup glob enum failed at $($Config.choco.backupGlob): $($_.Exception.Message)" -Level "warn"
    }

    # 3. *.nupkg cache files inside lib\<pkg>\
    try {
        $nupkgs = Get-Item -Path $Config.choco.nupkgCacheGlob -Force -ErrorAction SilentlyContinue
        foreach ($n in $nupkgs) {
            $sz = Get-PathSize -P $n.FullName
            try {
                Remove-Item -LiteralPath $n.FullName -Force -ErrorAction Stop
                $result.Count++
                $result.Bytes += $sz
            } catch {
                $reason = Get-LockReasonLocal -Ex $_.Exception
                $result.Locked++
                $result.LockedDetails += @{ Path = $n.FullName; Reason = $reason }
                Write-Log "Choco .nupkg locked at $($n.FullName): ${reason}" -Level "warn"
            }
        }
    } catch {
        Write-Log "Choco .nupkg glob enum failed at $($Config.choco.nupkgCacheGlob): $($_.Exception.Message)" -Level "warn"
    }

    # 4. choco-cleaner (community extension) if installed
    if ($Config.choco.useChocoCleaner) {
        $cleanerExe = $null
        try {
            $cmd = Get-Command "choco-cleaner.ps1" -ErrorAction SilentlyContinue
            if ($cmd) { $cleanerExe = $cmd.Source }
            if (-not $cleanerExe) {
                $candidate = "C:\ProgramData\chocolatey\bin\choco-cleaner.ps1"
                if (Test-Path $candidate) { $cleanerExe = $candidate }
            }
        } catch {}

        if ($cleanerExe) {
            Write-Log $LogMessages.clean.chocoCleanerFound -Level "info"
            try {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cleanerExe 2>&1 | Out-Null
            } catch {
                $msg = ($LogMessages.clean.chocoCleanerFailed -replace '\{error\}', $_.Exception.Message)
                Write-Log $msg -Level "warn"
            }
        } else {
            Write-Log $LogMessages.clean.chocoCleanerNotFound -Level "info"
        }
    }

    if ($result.Locked -gt 0) { $result.Status = "warn" }
    $mb = Format-Bytes -Bytes $result.Bytes
    Write-Log "Choco cache cleanup done: removed $($result.Count) item(s), freed ${mb} MB, locked $($result.Locked)" -Level $(if ($result.Locked -eq 0) { "success" } else { "warn" })
    return $result
}
