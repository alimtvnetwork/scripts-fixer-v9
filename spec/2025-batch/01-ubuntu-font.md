# 01 -- Ubuntu Font Install

**Script ID**: 47
**Folder**: `scripts/47-install-ubuntu-font/`
**Keywords**: `ubuntu-font`, `ubuntu.font`
**OS-dir install**: yes (no dev-dir prompt)

## What it does

Installs the Ubuntu font family system-wide via Chocolatey.

## Implementation

### `scripts/47-install-ubuntu-font/config.json`
```json
{
  "enabled": true,
  "chocoPackageName": "ubuntu.font",
  "alwaysUpgradeToLatest": true,
  "skipDevDirPrompt": true
}
```

### `scripts/47-install-ubuntu-font/run.ps1`

Standard pattern (mirrors script 33 `notepadpp` minus the settings sync):
1. `Initialize-Logging -ScriptName "Install Ubuntu Font"`
2. `Assert-Choco`
3. `Install-ChocoPackage -Name "ubuntu.font"` (or `Upgrade-ChocoPackage` if already installed -- decided by `Test-ToolInstalled`)
4. Verify with: list installed fonts via `Get-ChildItem "$env:WINDIR\Fonts\Ubuntu*.ttf"` (success if at least 1 file present)
5. `Save-LogFile -Status "ok"`

### `scripts/47-install-ubuntu-font/log-messages.json`

Standard messages: `start`, `installing`, `installed`, `upgrading`, `upgraded`, `verify-ok`, `verify-fail`, `done`.

## Registry + keyword wiring

- `scripts/registry.json`: `"47": "47-install-ubuntu-font"`
- `scripts/shared/install-keywords.json`: `"ubuntu-font": [47]`, `"ubuntu.font": [47]`

## Verification

```powershell
.\run.ps1 install ubuntu-font
.\run.ps1 -I 47
Test-Path "$env:WINDIR\Fonts\Ubuntu-R.ttf"  # should be $true
```

## Open questions

None.
