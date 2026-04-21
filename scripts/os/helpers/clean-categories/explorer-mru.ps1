<#
    Bucket B: explorer-mru -- Run/RecentDocs/TypedPaths registry keys

    Verbose mode (-Verbose / --verbose forwarded by clean-runner.ps1) writes
    every registry read + delete to
        .logs/os-clean-explorer-mru-registry-trace.log
    via scripts/shared/registry-trace.ps1.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$sharedDir = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) "..\shared"
$sharedDir = (Resolve-Path $sharedDir).Path
. (Join-Path $sharedDir "registry-trace.ps1")

$isVerbose = $PSBoundParameters.ContainsKey('Verbose') -or ($VerbosePreference -ne 'SilentlyContinue')
Initialize-RegistryTrace -ScriptName "os-clean-explorer-mru" -VerboseEnabled $isVerbose

$result = New-CleanResult -Category "explorer-mru" -Label "Explorer MRU (Run/RecentDocs/TypedPaths)" -Bucket "B"

$keys = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
)

foreach ($k in $keys) {
    if (-not (Test-Path $k)) {
        $result.Notes += "Key not present: $k"
        Write-RegistryTrace -Op "READ-ONLY" -Path $k -Status "SKIP" -Reason "key not present"
        continue
    }
    try {
        $vals = (Get-Item $k).GetValueNames()
        Write-RegistryTrace -Op "GET" -Path $k -NewValue "$($vals.Count) value(s)" -Status "OK" -Reason "enumerated value names"

        if ($DryRun) {
            $result.WouldCount += $vals.Count
            $result.Notes += "DRY-RUN: would clear $($vals.Count) value(s) under $k"
            foreach ($v in $vals) {
                Write-RegistryTrace -Op "REMOVE-VALUE" -Path $k -Name $v -Status "SKIP" -Reason "dry-run"
            }
            continue
        }
        foreach ($v in $vals) {
            $oldVal = $null
            try {
                $oldVal = (Get-ItemProperty -Path $k -Name $v -ErrorAction SilentlyContinue).$v
            } catch {}
            try {
                Remove-ItemProperty -Path $k -Name $v -Force -ErrorAction Stop
                $result.Count++
                Write-RegistryTrace -Op "REMOVE-VALUE" -Path $k -Name $v -OldValue $oldVal -Status "OK"
            } catch {
                Write-Log "explorer-mru failed at ${k}\${v}: $($_.Exception.Message)" -Level "warn"
                $result.Locked++
                $result.LockedDetails += @{ Path = "$k\$v"; Reason = (Get-LockReason -Ex $_.Exception) }
                Write-RegistryTrace -Op "REMOVE-VALUE" -Path $k -Name $v -OldValue $oldVal -Status "FAIL" -Reason $_.Exception.Message
            }
        }
        # Also remove subkeys under RecentDocs (per-extension folders)
        if ($k -match "RecentDocs$") {
            Get-ChildItem -Path $k -ErrorAction SilentlyContinue | ForEach-Object {
                $subPath = $_.PSPath
                try {
                    Remove-Item -Path $subPath -Recurse -Force -ErrorAction Stop
                    $result.Count++
                    Write-RegistryTrace -Op "REMOVE-KEY" -Path $subPath -Status "OK" -Reason "RecentDocs per-extension subkey"
                } catch {
                    Write-Log "explorer-mru subkey failed at ${subPath}: $($_.Exception.Message)" -Level "warn"
                    Write-RegistryTrace -Op "REMOVE-KEY" -Path $subPath -Status "FAIL" -Reason $_.Exception.Message
                }
            }
        }
    } catch {
        Write-Log "explorer-mru enum failed at ${k}: $($_.Exception.Message)" -Level "warn"
        Write-RegistryTrace -Op "GET" -Path $k -Status "FAIL" -Reason $_.Exception.Message
    }
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
Close-RegistryTrace -Status $result.Status
return $result
