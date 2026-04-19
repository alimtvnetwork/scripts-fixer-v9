# 09 -- Lightshot Install + Configure

**Script ID**: 51
**Folder**: `scripts/51-install-lightshot/`
**Keywords**: `lightshot`
**OS-dir install**: yes

## What it does

1. `choco install lightshot -y`
2. Configure Lightshot to:
   - Disable upload notifications
   - Default action: copy to clipboard (no auto-upload prompts)
   - JPEG quality: 100%

## Lightshot config location

Lightshot stores settings in the Windows registry:
`HKCU:\Software\Skillbrains\Lightshot`

Relevant values (verified from Lightshot 5.5.x):
| Value | Type | Setting |
|-------|------|---------|
| `ShowNotifications` | DWORD | `0` (off) |
| `ShowUploadDialog` | DWORD | `0` (no upload prompt) |
| `JpegQuality` | DWORD | `100` |
| `DefaultAction` | DWORD | `0` (copy to clipboard) |

## Implementation

### `scripts/51-install-lightshot/config.json`
```json
{
  "enabled": true,
  "chocoPackageName": "lightshot",
  "alwaysUpgradeToLatest": true,
  "skipDevDirPrompt": true,
  "tweaks": {
    "showNotifications": 0,
    "showUploadDialog": 0,
    "jpegQuality": 100,
    "defaultAction": 0
  }
}
```

### `scripts/51-install-lightshot/helpers/lightshot.ps1`
- `Install-Lightshot` -- choco install/upgrade
- `Set-LightshotTweaks`:
  ```powershell
  $key = "HKCU:\Software\Skillbrains\Lightshot"
  if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
  Set-ItemProperty -Path $key -Name "ShowNotifications" -Value 0 -Type DWord
  Set-ItemProperty -Path $key -Name "ShowUploadDialog"  -Value 0 -Type DWord
  Set-ItemProperty -Path $key -Name "JpegQuality"       -Value 100 -Type DWord
  Set-ItemProperty -Path $key -Name "DefaultAction"     -Value 0 -Type DWord
  ```
- Log each tweak with before/after value

### `scripts/51-install-lightshot/run.ps1`
1. Initialize logging
2. `Install-Lightshot`
3. `Set-LightshotTweaks`
4. Verify: registry values match config + `Test-Path "$env:ProgramFiles\Skillbrains\Lightshot\Lightshot.exe"` (or `${env:ProgramFiles(x86)}`)
5. Save log

## Registry + keyword wiring

- `scripts/registry.json`: `"51": "51-install-lightshot"`
- `scripts/shared/install-keywords.json`: `"lightshot": [51]`

## Verification

```powershell
.\run.ps1 install lightshot
Get-ItemProperty "HKCU:\Software\Skillbrains\Lightshot"
# JpegQuality=100, ShowNotifications=0, ShowUploadDialog=0, DefaultAction=0
```

## Open questions

- Lightshot's exact registry value names have shifted across versions. If install fails verification on a future build, fall back to `%APPDATA%\Skillbrains\Lightshot\settings.xml` (older versions used XML). Add detection in helper.
