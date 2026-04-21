# Spec: Script Fixer Context Menu (script 53)

## Overview

An **opt-in** Windows Explorer right-click cascading menu titled
**"Script Fixer v{version}"**. It exposes every script in `scripts/registry.json`
grouped automatically into categories. Clicking any leaf opens an
**elevated** PowerShell terminal (`pwsh` 7+ if available, else `powershell` 5.1)
that runs the chosen script via the project's `run.ps1` dispatcher.

This script does **not** install itself automatically. The user opts in by
running `.\run.ps1 install` and opts out by running `.\run.ps1 uninstall`.

## User answers (locked-in decisions)

| Decision         | Choice                                                              |
| ---------------- | ------------------------------------------------------------------- |
| Menu scope       | Everywhere: files, folders, folder background, desktop background   |
| Categories       | **Auto** from `registry.json` (no hand-curated list)                |
| Terminal         | `pwsh` 7+ preferred, fallback to `powershell` 5.1                   |
| Elevation        | **Always elevated** via UAC (`HasLUAShield` + `runas`)              |
| Version display  | Top-level label only: `Script Fixer v{version}` -- leaves stay short |

## Problem

The repo has 50+ scripts. Asking users to open a terminal, `cd` into the
repo, and remember the right script ID is a bad workflow -- especially for
"fixer" / repair scripts that are needed exactly when something is broken
and the user is already frustrated.

A native cascading right-click menu lets users launch any script from
anywhere in Explorer, with one click and one UAC prompt.

## Solution

A **classic Windows shell-extension** built entirely from registry entries
(no DLLs, no installers). Three pieces:

1. **Top-level cascading entry** with `MUIVerb` + `SubCommands=""`
   (the Vista/7+ "owner-drawn submenu" trick). Title is
   `Script Fixer v{version}` so the user always sees which version is
   wired up.
2. **Per-category subkeys** under `shell\<top>\shell\<category>\` --
   themselves cascading menus when a category has more than 1 script,
   leaf entries when it has exactly 1.
3. **Per-script leaf entries** whose `command` is:

   ```text
   "{shell.exe}" -NoExit -ExecutionPolicy Bypass -Command
       "Set-Location -LiteralPath '{repoRoot}';
        & '.\\run.ps1' -I {scriptId}"
   ```

   Each leaf carries `HasLUAShield` so Windows shows the UAC shield and
   triggers elevation via `ShellExecute runas`. The shell itself runs
   elevated, and the inner `run.ps1` already handles re-asserting admin
   when needed.

The menu is installed **per-machine** (`HKEY_CLASSES_ROOT`) under four
shell roots so it shows everywhere:

| Scope               | Registry root                                           |
| ------------------- | ------------------------------------------------------- |
| File right-click    | `HKCR\*\shell\ScriptFixer`                              |
| Folder right-click  | `HKCR\Directory\shell\ScriptFixer`                      |
| Folder background   | `HKCR\Directory\Background\shell\ScriptFixer`           |
| Desktop background  | `HKCR\DesktopBackground\Shell\ScriptFixer`              |

## Auto-categorization rules

Categories are inferred from the registry folder name with the leading
`NN-` numeric prefix stripped:

| Pattern (after stripping `NN-`)            | Category           |
| ------------------------------------------ | ------------------ |
| Exact match: `databases`                   | Databases          |
| Exact match: `audit`                       | Audit              |
| Exact match: `scan`                        | Scan               |
| Exact match: `os`                          | OS Utilities       |
| Exact match: `profile`                     | Profile            |
| Exact match: `git-tools`                   | Git Tools          |
| Exact match: `models`                      | AI Models          |
| `install-mysql`/`mariadb`/`postgresql`/`mongodb`/`redis`/`couchdb`/`cassandra`/`neo4j`/`elasticsearch`/`duckdb`/`litedb`/`sqlite` | Databases |
| `install-ollama` / `install-llama-cpp`     | AI Models          |
| `install-vscode` / `vscode-settings-sync` / `install-notepadpp` / `install-dbeaver` / `install-gitmap` / `install-windows-terminal` / `install-conemu` | Editors & IDEs |
| `*-context-menu*` / `vscode-folder-repair` / `script-fixer-context-menu` | Context Menu Fixers |
| `windows-tweaks` / `install-winget` / `install-powershell` / `install-ubuntu-font` | Windows |
| `install-docker` / `install-kubernetes`    | Containers         |
| `install-nodejs`/`pnpm`/`python`/`golang`/`cpp`/`php`/`flutter`/`dotnet`/`java`/`rust`/`python-libs` | Languages & Runtimes |
| `install-git` / `install-github-desktop`   | Git                |
| `install-all-dev-tools`                    | Bundles            |
| `install-obs` / `install-whatsapp` / `install-onenote` / `install-lightshot` / `install-sticky-notes` / `install-package-managers` | Apps |
| Anything else                              | Other              |

Categories are sorted alphabetically; within a category, scripts are sorted
by their numeric ID. Categories with **only one** script are flattened --
the single script appears at the top level instead of in its own submenu --
to avoid useless one-item cascades.

## Top-level entry shape (per scope)

```text
HKCR\Directory\Background\shell\ScriptFixer
  (Default)        = "Script Fixer v0.55.0"        ; the visible label
  MUIVerb          = "Script Fixer v0.55.0"        ; required for owner-drawn submenu
  SubCommands      = ""                            ; signals "I'm a cascading parent"
  Icon             = "{repoRoot}\assets\fixer.ico" ; optional, falls back to powershell.exe icon

HKCR\Directory\Background\shell\ScriptFixer\shell\Databases
  (Default)        = "Databases"
  MUIVerb          = "Databases"
  SubCommands      = ""

HKCR\Directory\Background\shell\ScriptFixer\shell\Databases\shell\18
  (Default)        = "18 -- install-mysql"
  Icon             = "{shell.exe}"
HKCR\Directory\Background\shell\ScriptFixer\shell\Databases\shell\18\command
  (Default)        = "{shell.exe}" -NoExit ... -I 18
```

The same structure is mirrored under `HKCR\*\shell\ScriptFixer`,
`HKCR\Directory\shell\ScriptFixer`, and `HKCR\DesktopBackground\Shell\ScriptFixer`.

## File Structure

```
scripts/53-script-fixer-context-menu/
  config.json                  # Scope toggles, top-level title template,
                               # category map overrides, shell preferences
  log-messages.json            # All display strings
  run.ps1                      # install | uninstall | refresh | --help
  helpers/
    categorize.ps1             # registry.json -> { category -> [scripts] }
    shell-detect.ps1           # pick pwsh.exe vs powershell.exe
    menu-writer.ps1            # build/teardown the cascading registry tree

spec/53-script-fixer-context-menu/
  readme.md                    # this file

.resolved/53-script-fixer-context-menu/
  resolved.json                # { installedAt, version, shellExe, scopes,
                               #   topLevelLabel, leafCount, categories }
```

## Commands

```powershell
.\run.ps1                 # default: install (idempotent)
.\run.ps1 install         # explicit install (or refresh if already present)
.\run.ps1 refresh         # uninstall + re-install (use after adding scripts)
.\run.ps1 uninstall       # remove every key this script created, in every scope
.\run.ps1 -Help
```

`refresh` is the recommended way to update after editing `registry.json`,
adding a new script, or bumping the project version (so the title updates
to the new `v{version}`).

## Execution flow (install)

1. Load `config.json` + `log-messages.json`, banner, init logging.
2. `git pull`, disabled check, **assert admin**.
3. Read `scripts/version.json` -> compose `topLevelLabel` from
   `config.titleTemplate` (default `"Script Fixer v{version}"`).
4. Resolve shell exe: try `pwsh.exe` (PATH, `C:\Program Files\PowerShell\*`,
   WindowsApps), fall back to `powershell.exe`. Persist to `.resolved/`.
5. Read `scripts/registry.json` -> `Get-ScriptCategorization` -> ordered
   `[ {category, items: [{id, folder, label}]} ]`. Flatten singletons.
6. For each enabled scope in `config.scopes`:
   a. **Wipe any pre-existing tree** at the scope's `topKey` (so install is
      idempotent and reflects the current registry.json).
   b. Write top-level entry with `MUIVerb`, `SubCommands=""`, optional `Icon`.
   c. For each category: write category subkey under `topKey\shell\<safeCat>`.
   d. For each script: write leaf under `category\shell\<id>` with `command`.
7. Verify final state: every expected key + value exists.
8. Save resolved state.

## Execution flow (uninstall)

1. For each scope in `config.scopes` (regardless of enabled flag, so a
   previously-enabled-then-disabled scope still cleans up):
   - `reg.exe delete <topKey> /f` (recursive delete handles all children).
2. Remove `.installed/` + `.resolved/` records.

## Elevation strategy

Each leaf carries `HasLUAShield = ""` (empty string value). That is the
documented Windows trick to render the UAC shield icon and trigger an
elevation prompt via `ShellExecuteEx` with the `runas` verb. The launched
shell process is therefore already elevated when `run.ps1` starts -- no
nested `Start-Process -Verb RunAs` shenanigans, no double UAC prompt.

## CODE RED compliance

Every registry write, every `reg.exe` invocation, every category-build
failure logs the **exact registry path** and the **exact failure reason**
(non-zero exit code, exception message, missing prerequisite path). No
silent failures.

## Versioning

The top-level menu label embeds the project version
(`scripts/version.json`). When the user bumps the version, they must run
`.\run.ps1 refresh` for the label to update -- documented in the help
output and in `log-messages.json`.

## Prerequisites

- Windows 10 / 11
- PowerShell 5.1+ to run the installer itself
- Administrator privileges (asserted)
- The repo's `run.ps1` dispatcher must exist at the repo root
  (it's the entry point each leaf invokes)

## Install Keywords

| Keyword               |
| --------------------- |
| `script-fixer-menu`   |
| `fixer-menu`          |
| `right-click-fixer`   |

```powershell
.\run.ps1 install script-fixer-menu
```
