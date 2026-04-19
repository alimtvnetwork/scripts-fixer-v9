# 06 -- OneNote (with tray + OneDrive disable)

**Script ID**: 50
**Folder**: `scripts/50-install-onenote/`
**Keywords**: `onenote`
**OS-dir install**: yes
**Mechanism**: Chocolatey (`choco install onenote -y`) -- NOT Microsoft Store

## What it does

1. Installs OneNote (free desktop version) via `choco install onenote -y`. If `onenote` package is unavailable, falls back to direct download from Microsoft (URL pinned in config).
2. Removes OneNote tray icon (registry tweak)
3. Disables OneDrive (process kill + scheduled task disable + autostart removal)

## Implementation

### `scripts/50-install-onenote/config.json`
```json
{
  "enabled": true,
  "chocoPackageName": "onenote",
  "fallbackDownload": {
    "enabled": true,
    "url": "https://go.microsoft.com/fwlink/p/?LinkID=2024522",
    "fileName": "OneNoteSetup.exe",
    "silentArgs": "/silent"
  },
  "skipDevDirPrompt": true,
  "tweaks": {
    "removeTrayIcon": true,
    "disableOneDrive": true
  }
}
```

### `scripts/50-install-onenote/helpers/onenote.ps1`
- `Install-OneNote` -- try choco, fall back to download-and-install on failure
- `Remove-OneNoteTray` -- registry: delete `HKCU:\Software\Microsoft\Office\16.0\OneNote\Options\OneNoteTrayIcon` value, kill `ONENOTEM.EXE`
- `Disable-OneDrive`:
  ```powershell
  Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
  Get-ScheduledTask -TaskName "OneDrive*" | Disable-ScheduledTask -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name OneDrive -ErrorAction SilentlyContinue
  # Optional: uninstall via Settings -- log a one-line note
  ```

### `scripts/50-install-onenote/run.ps1`
1. Initialize logging
2. `Install-OneNote`
3. `Remove-OneNoteTray`
4. `Disable-OneDrive`
5. Verify: OneNote launchable + OneDrive process not running
6. Save log

## Registry + keyword wiring

- `scripts/registry.json`: `"50": "50-install-onenote"`
- `scripts/shared/install-keywords.json`: `"onenote": [50]`

## Verification

```powershell
.\run.ps1 install onenote
Get-Process OneDrive -ErrorAction SilentlyContinue   # should be null
```

## Open questions

- Choco's `onenote` package coverage is inconsistent. The fallback download is the safety net. Decision: log a clear `[NOTICE]` if the fallback path was used.
