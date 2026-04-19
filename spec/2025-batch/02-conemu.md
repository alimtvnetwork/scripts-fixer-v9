# 02 -- ConEmu + Settings

**Script ID**: 48
**Folder**: `scripts/48-install-conemu/`
**Keywords**: `conemu` (= install+settings), `conemu+settings` (alias), `conemu-settings` (settings only), `install-conemu` (install only)
**OS-dir install**: yes
**Settings source**: `settings/06 - conemu/ConEmu.xml` (already copied from user upload)

## What it does

1. Installs ConEmu via `choco install conemu -y`
2. Copies `settings/06 - conemu/ConEmu.xml` to `%APPDATA%\ConEmu\ConEmu.xml`
3. Backs up any existing `ConEmu.xml` to `ConEmu.xml.bak.<timestamp>` first
4. Supports an `export` mode that copies `%APPDATA%\ConEmu\ConEmu.xml` back into the repo

## Three install modes (mirrors notepad++ / obs)

| Keyword | Mode | Behaviour |
|---------|------|-----------|
| `conemu` | `install+settings` | choco install + copy XML |
| `conemu+settings` | `install+settings` | same as above |
| `conemu-settings` | `settings-only` | copy XML only (skip choco) |
| `install-conemu` | `install-only` | choco install, leave existing settings untouched |

Mode-mapping JSON pattern: identical to `scripts/33-install-notepadpp/config.json`.

## Implementation

### `scripts/48-install-conemu/config.json`
```json
{
  "enabled": true,
  "chocoPackageName": "conemu",
  "alwaysUpgradeToLatest": true,
  "skipDevDirPrompt": true,
  "settings": {
    "sourceFolder": "settings/06 - conemu",
    "fileName": "ConEmu.xml",
    "targetFolder": "%APPDATA%\\ConEmu",
    "backupExisting": true,
    "maxFileSizeBytes": 2097152
  },
  "modes": {
    "default": "install+settings",
    "valid": ["install+settings", "settings-only", "install-only"]
  }
}
```

### `scripts/48-install-conemu/helpers/conemu.ps1`
- `Install-ConEmu` -- choco install/upgrade with `Assert-Choco`
- `Sync-ConEmuSettings` -- copy with backup, expand `%APPDATA%`, mkdir if missing
- `Export-ConEmuSettings` -- reverse direction (machine -> repo), invoked by `run.ps1 -I 48 -- export`

### `scripts/48-install-conemu/run.ps1`
1. Parse `-Mode` and check for `export` arg in `$Rest`
2. If `export` -> `Export-ConEmuSettings`, exit
3. If mode includes install -> `Install-ConEmu`
4. If mode includes settings -> `Sync-ConEmuSettings`
5. Verify: `Test-Path "$env:APPDATA\ConEmu\ConEmu.xml"` AND `Get-Command ConEmu64 -ErrorAction SilentlyContinue` (skip command check in settings-only)

## Registry + keyword wiring

- `scripts/registry.json`: `"48": "48-install-conemu"`
- `scripts/shared/install-keywords.json`:
  ```json
  "conemu":           [48],
  "conemu+settings":  [48],
  "conemu-settings":  [48],
  "install-conemu":   [48]
  ```
- `modes` block: same shape as script 33 -- `"conemu": "install+settings"`, `"conemu-settings": "settings-only"`, etc.

## Verification

```powershell
.\run.ps1 install conemu
Test-Path "$env:APPDATA\ConEmu\ConEmu.xml"   # $true
Get-Command ConEmu64                          # found
.\run.ps1 -I 48 -- export                    # round-trip
```

## Open questions

- Verify that the uploaded XML opens cleanly on a fresh ConEmu install (no missing fontnames). If a font referenced in the XML isn't installed, ConEmu falls back silently -- not blocking.
