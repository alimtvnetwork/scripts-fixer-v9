# 03 -- WhatsApp Install

**Script ID**: 49
**Folder**: `scripts/49-install-whatsapp/`
**Keywords**: `whatsapp`, `wa`
**OS-dir install**: yes (Store-style desktop app)
**Mechanism**: Chocolatey (`choco install whatsapp -y`) -- NOT Microsoft Store

## What it does

Installs WhatsApp Desktop via Chocolatey. Skips the Microsoft Store path entirely (per locked decision).

## Implementation

### `scripts/49-install-whatsapp/config.json`
```json
{
  "enabled": true,
  "chocoPackageName": "whatsapp",
  "alwaysUpgradeToLatest": true,
  "skipDevDirPrompt": true
}
```

### `scripts/49-install-whatsapp/run.ps1`
Standard single-tool pattern:
1. `Initialize-Logging -ScriptName "Install WhatsApp"`
2. `Assert-Choco`
3. `Install-ChocoPackage -Name "whatsapp"` (or upgrade if installed)
4. Verify: `Test-Path "$env:LOCALAPPDATA\WhatsApp\WhatsApp.exe"` OR `Get-Command whatsapp -ErrorAction SilentlyContinue`
5. `Save-LogFile -Status "ok"`

## Registry + keyword wiring

- `scripts/registry.json`: `"49": "49-install-whatsapp"`
- `scripts/shared/install-keywords.json`: `"whatsapp": [49]`, `"wa": [49]`

## Verification

```powershell
.\run.ps1 install whatsapp
.\run.ps1 -I 49
```

## Open questions

- Some Chocolatey versions of `whatsapp` lag behind the official build. If the package is stale, the script should log a warning but still succeed. Future enhancement: fall back to direct download from `https://web.whatsapp.com/desktop/windows/release/x64/WhatsAppSetup.exe`.
