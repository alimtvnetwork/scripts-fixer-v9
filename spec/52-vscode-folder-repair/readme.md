# Spec: VS Code Folder-Only Context Menu Repair

## Overview

Repairs the Windows Explorer **"Open with Code"** entry so it shows up
**only when right-clicking folders**, not when right-clicking files or empty
folder backgrounds. After the registry is fixed, the script restarts
`explorer.exe` so the change takes effect immediately.

## Problem

Default and third-party installs of VS Code often add the "Open with Code"
entry in three places at once:

1. `HKCR\*\shell\VSCode` -- shows on every **file** right-click
2. `HKCR\Directory\shell\VSCode` -- shows on **folder** right-click (the one we want)
3. `HKCR\Directory\Background\shell\VSCode` -- shows on every empty area inside a folder

That clutters the menu. Users reported they only want the folder entry.

## Solution

A focused PowerShell script that:

- Reads target lists from `config.json` (`removeFromTargets`, `ensureOnTargets`)
- Removes the file + background entries via `reg.exe delete /f`
- Re-creates / repairs the folder entry with correct label, icon, and `%V` command argument
- Verifies each target is in the expected state (present / absent)
- Restarts `explorer.exe` so Explorer picks up the new menu without sign-out

It reuses the registry + path-resolution helpers from script 10
(`10-vscode-context-menu-fix/helpers/registry.ps1`) so logic stays in one
place.

## File Structure

```
scripts/52-vscode-folder-repair/
  config.json
  log-messages.json
  run.ps1
  helpers/
    repair.ps1

spec/52-vscode-folder-repair/
  readme.md

.resolved/52-vscode-folder-repair/
  resolved.json    (auto-created)
```

## config.json keys

| Key                       | Type     | Description                                                |
|---------------------------|----------|------------------------------------------------------------|
| `enabled`                 | bool     | Master switch                                              |
| `editions.*`              | object   | Stable / Insiders edition definitions                      |
| `editions.*.vscodePath`   | object   | `user` and `system` install paths                          |
| `editions.*.registryPaths`| object   | Three keys: `file`, `directory`, `background`              |
| `editions.*.contextMenuLabel` | string | Menu label                                                |
| `installationType`        | string   | `user` or `system` -- preferred install root               |
| `enabledEditions`         | string[] | Editions to process                                        |
| `removeFromTargets`       | string[] | Targets to delete (default `["file","background"]`)        |
| `ensureOnTargets`         | string[] | Targets to keep + repair (default `["directory"]`)         |
| `restartExplorer`         | bool     | Whether to restart `explorer.exe` at the end               |
| `restartExplorerWaitMs`   | int      | Pause between kill and start                               |

## Execution Flow

1. Load config + log messages, banner, init logging
2. `git pull`, disabled check, **assert admin**
3. For each edition in `enabledEditions`:
   - Resolve VS Code exe (uses cached `.resolved/` first, then config paths,
     then Chocolatey shim, then `Get-Command` / `where.exe`)
   - For each `removeFromTargets`: delete the registry key (and its `\command`)
   - For each `ensureOnTargets`: ensure key exists with label, icon, command
   - Verify final state matches expectation
4. Restart `explorer.exe` (skippable with `.\run.ps1 no-restart` or
   `restartExplorer=false` in config)
5. Save resolved state, save log file

## Commands

```powershell
.\run.ps1               # Full repair + explorer restart
.\run.ps1 no-restart    # Repair only, leave Explorer running
.\run.ps1 -Help         # Show help
```

## CODE RED Compliance

Every remove / ensure / verify failure path logs the **exact registry path**
and the failure reason (`reg.exe exit N`, exception message, etc.) per the
project-wide error-management rule.

## Prerequisites

- Windows 10 / 11
- PowerShell 5.1+
- Administrator privileges
- VS Code installed (script 01) so the executable can be resolved
