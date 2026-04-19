# 10 -- `os hib-off` Subcommand

**Type**: subcommand under `os` dispatcher
**Invocation**: `.\run.ps1 os hib-off` or `.\run.ps1 os hibernate-off`
**Requires**: Admin elevation

## What it does

Disables Windows hibernation, freeing the `hiberfil.sys` file (often 4-16 GB).

```powershell
powercfg.exe /hibernate off
```

## Implementation

### `scripts/os/helpers/hibernate.ps1`
```powershell
param([switch]$Off, [switch]$On)
Initialize-Logging -ScriptName "hibernate"

# Assert admin (re-launch if not)
# ... standard pattern

if ($On) {
    powercfg.exe /hibernate on
    Write-Log -Level "ok" -Message "Hibernation enabled"
} else {
    # Default: off
    $sizeBefore = if (Test-Path "C:\hiberfil.sys") { (Get-Item "C:\hiberfil.sys" -Force).Length } else { 0 }
    powercfg.exe /hibernate off
    Start-Sleep -Seconds 2
    $sizeAfter = if (Test-Path "C:\hiberfil.sys") { (Get-Item "C:\hiberfil.sys" -Force).Length } else { 0 }
    $freed = [Math]::Round(($sizeBefore - $sizeAfter) / 1GB, 2)
    Write-Log -Level "ok" -Message "Hibernation disabled. Freed ${freed} GB (hiberfil.sys removed)."
}
Save-LogFile -Status "ok"
```

## Verification

```powershell
.\run.ps1 os hib-off
Test-Path C:\hiberfil.sys   # should be $false
```

## Open questions

None.
