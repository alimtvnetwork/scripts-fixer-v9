# Specification: Script Fixer Context Menu (script 53)

> **Status:** Implemented in `scripts/53-script-fixer-context-menu/` as of project version **v0.56.0**. This document is the authoritative design contract — any future change to the script must update this spec first.

---

## 1. Purpose

Provide an **opt-in** Windows Explorer right-click cascading submenu titled
**"Script Fixer vX.Y.Z"** that lists every script in this repository, grouped
into categories, and launches the selected script in an elevated PowerShell
terminal.

The menu lowers the activation cost of running repair / install scripts when
they are most needed (Explorer is already open, the user is already
frustrated, and remembering numeric script IDs is friction).

---

## 2. Goals & Non-Goals

### 2.1 Goals

| # | Goal | Acceptance criterion |
|---|------|----------------------|
| G1 | One-click access to every script | Every entry in `scripts/registry.json` appears in the menu, in the correct category |
| G2 | Discoverable version | The top-level label embeds the project version, e.g. `Script Fixer v0.56.0` |
| G3 | Strictly opt-in | Nothing is written to the registry until the user explicitly runs `.\run.ps1 install` |
| G4 | Clean uninstall | `.\run.ps1 uninstall` removes every key created by this script across every scope, in any order, repeatable safely |
| G5 | Idempotent install | Running `install` twice in a row produces an identical registry state (no orphans, no duplicates) |
| G6 | Elevation in one prompt | Each launch shows the UAC shield once and the resulting shell process is already elevated |
| G7 | Self-updating from `registry.json` | Adding a new script + running `refresh` exposes it in the menu without code edits |
| G8 | Visible failure paths | Every registry/file/path failure logs the exact path and reason (CODE RED rule) |

### 2.2 Non-Goals

- **No automatic installation.** Bundle scripts (e.g. script 12) MUST NOT silently install this menu.
- **No DLL / native shell extension.** Pure registry implementation; no compiled component.
- **No Windows 11 modern context menu.** Only the classic context menu (which Win 11 still surfaces under "Show more options"). A future spec may cover the modern menu.
- **No per-user installation.** The menu installs into `HKCR` (machine-wide) only. A per-user variant (`HKCU\Software\Classes`) is out of scope for v1.
- **No GUI.** All interaction is via `.\run.ps1` commands.

---

## 3. Locked-in Design Decisions

These were chosen by the user via clarifying questions and are now contractual:

| # | Decision | Value |
|---|----------|-------|
| D1 | Menu scope | **Everywhere** — files, folders, folder background, Desktop background (4 registry roots) |
| D2 | Categorization source | **Auto** from `scripts/registry.json` with config-driven label map and heuristic fallback |
| D3 | Terminal | **`pwsh` 7+** preferred, fallback to **`powershell` 5.1** |
| D4 | Elevation | **Always elevated** via UAC (`HasLUAShield` value + Windows' built-in `runas` resolution) |
| D5 | Version display | **Top-level label only**: `Script Fixer v{version}` — leaf labels stay short |

---

## 4. Terminology

| Term | Meaning |
|------|---------|
| **Scope** | One of the four shell roots where the menu can appear (file / directory / background / desktop) |
| **Top-level entry** | The cascading parent shown directly in Explorer's right-click menu |
| **Category** | A second-level cascading parent (e.g. "Databases", "Languages & Runtimes") |
| **Leaf** | A clickable terminal launcher whose `command` runs `run.ps1 -I <id>` |
| **Singleton category** | A category that contains exactly one leaf — flattened to the top level so users don't traverse a one-item submenu |
| **Repo root** | The directory containing the top-level `run.ps1` dispatcher (resolved at install time, baked into each leaf's command) |

---

## 5. User Stories

| ID | As a... | I want... | So that... |
|----|---------|-----------|------------|
| US1 | repo user | to right-click anywhere in Explorer and see "Script Fixer v0.56.0" | I always know which version is wired up and can launch any script without a terminal |
| US2 | repo user | hovering "Script Fixer" to expand into "Databases", "Editors & IDEs", … | I can find scripts by intent, not by remembering IDs |
| US3 | repo user | clicking a leaf to open an elevated terminal that runs that script | I get one UAC prompt and immediately see live output |
| US4 | repo user | to opt-out cleanly | I can remove the menu without leftover registry junk |
| US5 | repo maintainer | to add a script and refresh the menu in one command | new scripts surface automatically |
| US6 | repo maintainer | to bump the project version and have the menu label update | the menu always reflects the installed version |

---

## 6. Architecture

### 6.1 File layout

```text
scripts/53-script-fixer-context-menu/
├── config.json                # Scope toggles, title template, category map, shell config
├── log-messages.json          # All user-facing strings (i18n / search ready)
├── run.ps1                    # Entry point: install | uninstall | refresh | -Help
└── helpers/
    ├── categorize.ps1         # registry.json -> ordered [{Category, Items[]}]
    ├── shell-detect.ps1       # Resolves pwsh.exe / powershell.exe
    └── menu-writer.ps1        # New-CascadingParent / New-LeafEntry / Remove-MenuTree

spec/53-script-fixer-context-menu/
└── readme.md                  # ← this document

.resolved/53-script-fixer-context-menu/
└── resolved.json              # Auto-saved post-install state (audit trail)
```

### 6.2 Data flow

```text
                           +---------------------+
        scripts/version.json -->| Get-ProjectVersion  |--+
                           +---------------------+  |
                                                    v
   scripts/registry.json ---> Get-ScriptCategorization --> Ordered category list
                                                    |
   config.shell + helpers/shell-detect.ps1 ---> Resolve-ShellExe --> shellExe path
                                                    |
                                                    v
                           +---------------------+
                           | menu-writer.ps1     |
                           | per scope:          |
                           |   Remove-MenuTree   | (idempotent wipe)
                           |   New-CascadingParent (top)
                           |   New-CascadingParent (each category)
                           |   New-LeafEntry      (each script)
                           |   Test-MenuKeyExists (verify)
                           +---------------------+
                                                    |
                                                    v
                           Save-ResolvedData (audit trail)
```

### 6.3 Component responsibilities

| Component | Responsibility | NOT responsible for |
|-----------|----------------|---------------------|
| `run.ps1` | Argument parsing, admin assertion, top-level orchestration, summary | Registry I/O, categorization, shell resolution |
| `helpers/categorize.ps1` | Read `registry.json`, apply `categoryMap` then heuristics, sort, flatten singletons | Reading config.json, registry I/O |
| `helpers/shell-detect.ps1` | Locate `pwsh.exe` then fall back to `powershell.exe`, log every miss | Building command lines |
| `helpers/menu-writer.ps1` | All registry create/delete/verify operations | Categorization, shell detection |

---

## 7. Registry Layout

### 7.1 Scopes (D1)

| Scope key   | Top-level path                                                  | Where it appears                |
|-------------|------------------------------------------------------------------|---------------------------------|
| `file`      | `HKCR\*\shell\ScriptFixer`                                       | Right-click on any file         |
| `directory` | `HKCR\Directory\shell\ScriptFixer`                               | Right-click on any folder       |
| `background`| `HKCR\Directory\Background\shell\ScriptFixer`                    | Right-click empty area in folder|
| `desktop`   | `HKCR\DesktopBackground\Shell\ScriptFixer`                       | Right-click the Desktop         |

Each scope can be toggled independently in `config.scopes.<name>.enabled`. A
disabled scope is **also wiped** at install time (so toggling off + reinstall
removes the menu from that scope).

### 7.2 Cascading parent shape

For every cascading parent (top level + each category):

| Value name    | Type    | Value                               | Why |
|---------------|---------|-------------------------------------|-----|
| `(Default)`   | REG_SZ  | The visible label                   | Required by Explorer for legacy clients |
| `MUIVerb`     | REG_SZ  | Same as `(Default)`                 | Required for owner-drawn cascading menus on Vista+ |
| `SubCommands` | REG_SZ  | `""` (empty string)                 | Documented signal that "I'm a parent — read children from `\shell`" |
| `Icon`        | REG_SZ  | `config.iconPath` (if non-empty)    | Optional polish |

### 7.3 Leaf shape

Each leaf lives at `<parent>\shell\<safeId>` and has:

| Value name      | Type   | Value | Why |
|-----------------|--------|-------|-----|
| `(Default)`     | REG_SZ | `"NN -- pretty-folder-name"` | Visible label |
| `HasLUAShield`  | REG_SZ | `""`  | Renders UAC shield + triggers elevation via `runas` (D4) |
| `Icon`          | REG_SZ | Path to `pwsh.exe` (or override) | Visual cue that this opens a terminal |

And the `command` subkey:

| Path            | Value | Value template |
|-----------------|-------|----------------|
| `<leaf>\command` | `(Default)` | See § 7.4 |

### 7.4 Command line template

`config.shell.commandTemplate` (default):

```text
"{shellExe}" -NoExit -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '{repoRoot}'; & '.\run.ps1' -I {scriptId}"
```

Placeholders are substituted at install time:

| Placeholder   | Source                                      |
|---------------|----------------------------------------------|
| `{shellExe}`  | Output of `Resolve-ShellExe` (absolute path) |
| `{repoRoot}`  | Resolved at install time from `run.ps1`'s location (parent of `scripts/`) |
| `{scriptId}`  | The numeric ID from `registry.json` (e.g. `52`) |

Rationale for `-NoExit`: keeps the terminal open after the script finishes so
the user can read output (success or failure).

---

## 8. Categorization Algorithm

Implemented in `helpers/categorize.ps1::Get-ScriptCategorization`.

### 8.1 Inputs

- `scripts/registry.json` — `{ scripts: { "01": "01-install-vscode", ... } }`
- `config.categoryMap` — exact-match lookup (key = stripped folder name, value = category label)
- `config.flattenSingletonCategories` — bool

### 8.2 Per-script category resolution

1. Strip leading `\d+-` prefix from the folder name (`52-vscode-folder-repair` → `vscode-folder-repair`).
2. If the stripped name appears in `config.categoryMap`, use that label.
3. Otherwise fall back to `Get-CategoryFromFolder` heuristic (regex switch by intent).
4. Anything still unmatched falls into `"Other"`.

### 8.3 Sorting & flattening

1. Within each category, items are sorted by **numeric ID** ascending (lexical fallback for non-numeric IDs).
2. Categories are sorted **alphabetically** by display label.
3. If `flattenSingletonCategories` is `true`, every category containing exactly 1 item is removed and its item is appended to a special `_root` group placed **after** the alphabetic categories — these render as top-level leaves directly under the "Script Fixer" parent.

### 8.4 Subkey safety

Category and leaf labels are sanitized via `ConvertTo-SafeSubkey`:

- Strip `\ / : * ? " < > |`
- Collapse whitespace
- Truncate to `config.categorySubkeyMaxLen` (default 60)
- Empty result → `"Item"`

The **visible label** (`(Default)` value) is unchanged; only the **subkey name** is sanitized.

---

## 9. Shell Resolution

Implemented in `helpers/shell-detect.ps1::Resolve-ShellExe`.

### 9.1 Order

1. `Get-Command pwsh` (PATH lookup).
2. Each path in `config.shell.pwshSearchPaths`, with environment variables expanded:
   - `%ProgramFiles%\PowerShell\7\pwsh.exe`
   - `%ProgramFiles%\PowerShell\6\pwsh.exe`
   - `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`
3. `config.shell.legacyPath` (`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`).

### 9.2 Failure behavior

If all candidates miss, install **aborts** with an error listing every path it tried (CODE RED rule).

---

## 10. Commands

Implemented in `run.ps1`.

| Command                    | Behavior |
|----------------------------|----------|
| `.\run.ps1`                | Defaults to `install` (idempotent) |
| `.\run.ps1 install`        | Wipes any prior tree per scope, then writes a fresh tree |
| `.\run.ps1 refresh`        | `uninstall` followed by `install` — recommended after editing `registry.json` or bumping `version.json` |
| `.\run.ps1 uninstall`      | `reg.exe delete /f` for every scope's top key, then purges `.installed/` and `.resolved/` records |
| `.\run.ps1 -Help`          | Prints commands + examples from `log-messages.json` |

Refresh is preferred over manual delete-then-install because it runs both
inside the same admin session and the same logging context.

---

## 11. Idempotency Contract

- **Install**: per-scope wipe (`Remove-MenuTree`) → recreate. Re-running install N times yields the same final registry state as running it once.
- **Uninstall**: per-scope `reg.exe delete /f`. Running uninstall on a system that was never installed returns success without error (logs `wipeNothingToDo` per scope).
- **Refresh**: equivalent to `uninstall && install`, both running under the same admin session.

---

## 12. Versioning Contract

- The top-level label is computed at install time from `scripts/version.json` via `Get-ProjectVersion`.
- The label is **not** dynamically refreshed. Bumping `version.json` requires `.\run.ps1 refresh`.
- If `version.json` is missing or unparseable, the label falls back to `Script Fixer vunknown` and a warning is logged with the exact path that failed.
- The install-time version is also written to `.resolved/53-script-fixer-context-menu/resolved.json` for audit.

---

## 13. Logging & CODE RED Compliance

Every failure logs the **exact path** plus the **exact reason**:

| Failure point        | Path logged                                  | Reason logged                                |
|----------------------|----------------------------------------------|----------------------------------------------|
| Registry write       | The full `Registry::HKEY_CLASSES_ROOT\…` path| Exception message                            |
| Registry delete      | The translated `HKCR\…` path                 | `reg.exe exit <code>` or exception message   |
| Shell detection miss | All searched paths joined by `; `            | "Could not resolve a PowerShell executable"  |
| Missing `version.json`| Full path that was tested                    | "version.json not found"                     |
| Missing `registry.json`| Full path that was tested                  | "registry.json not found -- aborting"        |
| Missing admin        | Current user name                            | "This script must be run as Administrator."  |

All strings live in `log-messages.json` for searchability and i18n readiness.

---

## 14. Configuration Reference (`config.json`)

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `enabled` | bool | `true` | Master switch. When `false`, `install` becomes a no-op (does NOT uninstall) |
| `titleTemplate` | string | `"Script Fixer v{version}"` | Top-level label template; `{version}` is the only placeholder |
| `categorySubkeyMaxLen` | int | `60` | Max length of sanitized subkey names |
| `flattenSingletonCategories` | bool | `true` | Whether to promote single-item categories to top-level leaves |
| `iconPath` | string | `""` | Optional icon for top-level + category parents |
| `shell.preferred` | string | `"pwsh"` | Documentary; resolution order is hard-coded in `Resolve-ShellExe` |
| `shell.fallback` | string | `"powershell"` | Documentary |
| `shell.pwshSearchPaths` | string[] | (3 paths) | Searched in order after PATH lookup |
| `shell.legacyPath` | string | (powershell.exe) | Final fallback |
| `shell.commandTemplate` | string | (see § 7.4) | The `(Default)` value written to each `\command` key |
| `scopes.<name>.enabled` | bool | `true` | Toggle per scope |
| `scopes.<name>.topKey` | string | (per scope) | Registry top key — change at your own risk |
| `categoryMap` | object | (large) | Folder-stripped-name → category label exact-match table |

---

## 15. Failure Modes & Mitigations

| Failure | Mitigation |
|---------|------------|
| User runs without admin | `Assert-Admin` aborts with a clear message; nothing is written |
| `registry.json` missing | Install aborts before any registry write (logged) |
| `version.json` missing  | Install proceeds with label `Script Fixer vunknown` (warning) |
| No PowerShell found     | Install aborts (no leaves can be wired) |
| Partial install (e.g. 1 scope fails mid-write) | Final summary marks failure; user is told to run `refresh` |
| User edits `registry.json` after install | Menu is stale; `.\run.ps1 refresh` rebuilds it (documented in summary tip) |
| User uninstalls VS Code / a tool | Affected leaf still appears but its inner script handles "not installed" itself; this menu does not pre-validate tool presence |
| User runs an unrelated script that bumps `version.json` | Menu label becomes stale; `refresh` updates it |

---

## 16. Security Considerations

- All leaves run as Administrator (D4). The menu is therefore a **privileged surface** — anyone with write access to `scripts/registry.json` or `run.ps1` can effectively achieve admin code execution from any user who clicks a leaf.
- The repo is assumed to be trusted (cloned by the user, not world-writable).
- No tokens, secrets, or credentials are stored in the registry — only paths and command lines.
- Uninstall removes 100 % of the keys this script created. Nothing is left behind.

---

## 17. Test Plan

Manual acceptance checklist (no automated harness — registry side effects):

1. **Install fresh**
   - Run `.\run.ps1 -I 53 install` as admin.
   - Right-click on a file, folder, folder background, and Desktop → menu present in all 4 places.
   - Top-level label matches `scripts/version.json`.
2. **Categories present**
   - "Databases" submenu lists every `install-<dbms>` script, sorted by ID.
   - Singleton categories appear at top level (e.g. one-off scripts), not as one-item submenus.
3. **Leaf launch**
   - Click a leaf → UAC prompt → terminal opens → `run.ps1 -I <id>` runs → terminal stays open after completion.
4. **Refresh after edit**
   - Add a fake script to `registry.json` (e.g. `"99": "99-test"`).
   - Run `.\run.ps1 -I 53 refresh` → new entry appears.
5. **Uninstall**
   - Run `.\run.ps1 -I 53 uninstall`.
   - Right-click everywhere → menu absent.
   - `.installed/` + `.resolved/53-script-fixer-context-menu/` records removed.
6. **Idempotency**
   - Run `install` twice in a row → no errors, identical registry state.
   - Run `uninstall` on a clean system → returns success, logs `wipeNothingToDo`.
7. **Failure paths**
   - Rename `version.json` → install logs warning + uses `vunknown`.
   - Rename `registry.json` → install aborts with exact path in error.
   - Run as non-admin → aborts with admin message.

---

## 18. Future Extensions (out of v1 scope)

| # | Idea | Notes |
|---|------|-------|
| F1 | Custom `.ico` for top-level + per-category | Add `assets/fixer.ico`; populate `iconPath` |
| F2 | Per-script icons | Extend `categoryMap` from `string` to `{ category, icon }` |
| F3 | Hide disabled scripts | Read each script's `config.json.enabled` and skip when `false` |
| F4 | Per-user installation | Mirror layout under `HKCU\Software\Classes` |
| F5 | Modern Win 11 context menu | Build a packaged sparse-signed shell extension (much larger scope) |
| F6 | Auto-refresh hook on version bump | Tie into a project-wide post-bump task |
| F7 | Optional confirmation prompt before launch | New `confirmBeforeLaunch` config flag |
| F8 | Logging the launch event | Each leaf could append to `logs/menu-launches.jsonl` before invoking `run.ps1` |

---

## 19. Implementation Pointers

| Want to change... | Edit... |
|-------------------|---------|
| The menu title format | `config.titleTemplate` |
| Which scopes show the menu | `config.scopes.*.enabled` |
| Category names / regrouping | `config.categoryMap` (or extend `Get-CategoryFromFolder`) |
| Singleton flattening behavior | `config.flattenSingletonCategories` |
| The shell that runs each leaf | `config.shell.pwshSearchPaths` / `legacyPath` / `commandTemplate` |
| User-facing strings | `scripts/53-script-fixer-context-menu/log-messages.json` |
| Add a brand icon | Drop a `.ico` somewhere, set `config.iconPath` |

---

## 20. Install Keywords

Recognized by the dispatcher's keyword router:

| Keyword               | Resolves to |
|-----------------------|-------------|
| `script-fixer-menu`   | script 53   |
| `fixer-menu`          | script 53   |
| `right-click-fixer`   | script 53   |

```powershell
.\run.ps1 install script-fixer-menu
```

---

## 21. Prerequisites

- Windows 10 / Windows 11
- PowerShell **5.1+** to run the installer
- **Administrator** privileges
- The repo's top-level `run.ps1` dispatcher (the script bakes its absolute path into every leaf at install time)
- Optional but recommended: `pwsh` 7+ for prettier terminal output

---

## 22. Definition of Done

This script is "done" when **all** of the following hold:

- [x] Spec exists at `spec/53-script-fixer-context-menu/readme.md` (this file)
- [x] `scripts/53-script-fixer-context-menu/{config.json,log-messages.json,run.ps1}` present
- [x] Three helpers present: `categorize.ps1`, `shell-detect.ps1`, `menu-writer.ps1`
- [x] Registered in `scripts/registry.json` as ID `53`
- [x] Project version bumped (≥ minor) on first ship
- [x] Changelog entry added
- [x] All 7 test-plan items pass on a fresh Windows 10/11 admin shell
- [x] CODE RED rule satisfied: every failure path logs exact path + reason
