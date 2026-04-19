# 07 -- `fix-long-path` (`flp`) Subcommand

**Type**: subcommand under `os` dispatcher
**Invocation**: `.\run.ps1 os flp` or `.\run.ps1 os fix-long-path`
**Requires**: Admin elevation
**Reboot**: not strictly required, but recommended

## What it does

Enables Windows long-path support (paths > 260 chars). The same toggle exposed in:
**Group Policy Editor -> Computer Config -> Administrative Templates -> System -> Filesystem -> "Enable Win32 long paths"**

## Implementation (registry direct, no gpedit needed)

### `scripts/os/helpers/longpath.ps1`
```powershell
Initialize-Logging -ScriptName "fix-long-path"

# Assert admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log -Level "fail" -Message "Admin required. Re-launching..."
    Start-Process pwsh -Verb RunAs -ArgumentList "-File `"$PSCommandPath`""
    return
}

$key = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
$name = "LongPathsEnabled"
$current = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name

if ($current -eq 1) {
    Write-Log -Level "ok" -Message "Long paths already enabled"
} else {
    Set-ItemProperty -Path $key -Name $name -Value 1 -Type DWord
    $verify = (Get-ItemProperty -Path $key -Name $name).$name
    if ($verify -eq 1) {
        Write-Log -Level "ok" -Message "Long paths enabled (LongPathsEnabled=1). Reboot recommended."
    } else {
        Write-Log -Level "fail" -Message "Failed to set LongPathsEnabled at $key"
        Save-LogFile -Status "fail"; return
    }
}
Save-LogFile -Status "ok"
```

## Verification

```powershell
.\run.ps1 os flp
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled
# Expected: LongPathsEnabled : 1
```

## Open questions

None.
