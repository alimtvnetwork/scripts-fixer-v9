# Specification: VS Code Context Menu Installer (script 54)

> **Status:** Implemented as `scripts/54-vscode-menu-installer/` in project version **v0.57.0**.
>
> **Relation to script 10:** Script 10 (`vscode-context-menu-fix`) is the
> heavyweight "do everything" orchestrator (auto-detect install type, choco
> shim fallback, edition resolution, etc.). Script 54 is the **focused
> installer/uninstaller pair** -- thin, surgical, hand-off-ready. It owns
> exactly the registry keys it writes, and uninstall is guaranteed to never
> touch a sibling key.

---

## 1. Purpose

Provide a clean **installer/uninstaller pair** for the classic
"Open with Code" Windows Explorer right-click entries:

- `install.ps1` writes three registry keys (file, folder, folder background).
- `uninstall.ps1` removes **only** those three keys -- nothing else.

The pair is designed to be:

1. **Self-contained**: no dependency on script 10's helpers.
2. **Surgical**: uninstall reads a strict path **allow-list** from
   `config.json` and deletes only those paths. Sibling keys (e.g. a
   separately-installed `VSCode2`, `OpenWithCode`, `EditWithCode`) are never
   touched.
3. **Hand-off-ready**: the two top-level scripts have self-explanatory
   names so they can be linked from another tool, scheduled, or invoked by
   a non-PowerShell wrapper.

---

## 2. Goals & Non-Goals

### 2.1 Goals

| # | Goal | Acceptance |
|---|------|------------|
| G1 | Distinct installer + uninstaller files | `install.ps1` and `uninstall.ps1` both exist at the script root and run independently |
| G2 | Surgical uninstall | Uninstall **only** removes paths listed in `config.json::registryPaths` |
| G3 | No collateral damage | A test sibling key (e.g. `HKCR\Directory\shell\VSCode2`) survives uninstall intact |
| G4 | Idempotent | Re-running install or uninstall is safe (no errors, no duplicates) |
| G5 | CODE RED logging | Every registry write/delete failure logs the full path and the reason |
| G6 | VS Code edition selectable | Can install for stable, insiders, or both |
| G7 | Bootstrap-only dependency on shared helpers | Uses logging + json-utils + admin assertion only -- no script 10 imports |

### 2.2 Non-Goals

- **No auto-detection of choco shims, WindowsApps, etc.** Script 54 expects
  the VS Code path to be either resolvable from `config.json` or passed
  via `-VsCodePath`. For full auto-detection, use script 10.
- **No Win 11 modern context menu**. Classic context menu only.
- **No per-user installation.** Writes to `HKCR` (machine-wide) only.
- **No edition co-existence checks.** Installing both stable and insiders
  creates two separate registry trees with separate top keys.

---

## 3. Locked-in Design Decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Surgical removal strategy | **Path allow-list from `config.json`** (no `.resolved/` lookup, no label matching) |
| D2 | Number of files | **Three** top-level scripts: `install.ps1`, `uninstall.ps1`, `run.ps1` (router) |
| D3 | Editions supported | stable + insiders, toggled via `enabledEditions` in config |
| D4 | Three menu locations | file (`HKCR\*`), folder (`HKCR\Directory`), folder background (`HKCR\Directory\Background`) |

---

## 4. File Layout

```text
scripts/54-vscode-menu-installer/
├── config.json                # Registry path allow-list + edition paths
├── log-messages.json          # All user-facing strings
├── install.ps1                # Standalone installer
├── uninstall.ps1              # Standalone uninstaller
├── run.ps1                    # Router (install | uninstall | -Help)
└── helpers/
    ├── vscode-install.ps1     # Install logic (Register-VsCodeMenuEntry)
    └── vscode-uninstall.ps1   # Surgical uninstall logic (Remove-VsCodeMenuEntry)

spec/54-vscode-menu-installer/
└── readme.md                  # ← this document

.resolved/54-vscode-menu-installer/
└── resolved.json              # Audit trail (timestamp, edition, vsCodeExe)
```

---

## 5. Configuration Reference (`config.json`)

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `enabled` | bool | `true` | Master switch for install (uninstall ignores this) |
| `enabledEditions` | string[] | `["stable","insiders"]` | Which editions install touches |
| `editions.<name>.label` | string | (per edition) | Visible menu label |
| `editions.<name>.vsCodePath` | string | (auto-resolved env var path) | Where Code.exe lives; overridable per call via `-VsCodePath` |
| `editions.<name>.registryPaths.file` | string | `HKCR\*\shell\VSCode` | File right-click key (allow-list entry) |
| `editions.<name>.registryPaths.directory` | string | `HKCR\Directory\shell\VSCode` | Folder right-click key |
| `editions.<name>.registryPaths.background` | string | `HKCR\Directory\Background\shell\VSCode` | Folder background key |
| `editions.<name>.commandTemplates.file` | string | `"{exe}" "%1"` | File-click command |
| `editions.<name>.commandTemplates.directory` | string | `"{exe}" "%V"` | Folder-click command |
| `editions.<name>.commandTemplates.background` | string | `"{exe}" "%V"` | Background command |

**Surgical-uninstall contract (D1):** the uninstaller iterates only over
the three `registryPaths` values per edition. Any registry key not listed
here -- including sibling keys created by other installers, IDE plugins, or
manual edits -- is **never** touched.

---

## 6. Commands

### 6.1 install.ps1

```powershell
.\install.ps1                                # all enabled editions, paths from config
.\install.ps1 -Edition stable                # only stable edition
.\install.ps1 -Edition insiders -VsCodePath "D:\VSI\Code - Insiders.exe"
.\install.ps1 -Help
```

### 6.2 uninstall.ps1

```powershell
.\uninstall.ps1                              # remove all editions in config
.\uninstall.ps1 -Edition stable              # remove only stable edition's keys
.\uninstall.ps1 -Help
```

### 6.3 run.ps1 (router)

```powershell
.\run.ps1 install [-Edition <name>] [-VsCodePath <path>]
.\run.ps1 uninstall [-Edition <name>]
.\run.ps1 -Help
```

The two standalone scripts are the canonical entry points. `run.ps1` exists
so the project's master `-I 54` dispatcher can route in.

---

## 7. Install Algorithm

For each `editionName` in `config.enabledEditions`:

1. Resolve VS Code path:
   - Use `-VsCodePath` parameter if provided.
   - Otherwise expand `editions.<name>.vsCodePath` env vars and `Test-Path`.
   - On miss, log the exact expanded path and **skip this edition**
     (continue with others).
2. For each of the three `registryPaths` (`file`, `directory`, `background`):
   - Compute command line via `commandTemplates.<key>` with `{exe}`
     substituted.
   - Write the parent key:
     - `(Default)` = label
     - `Icon` = `"{exe}"`
   - Write the `\command` subkey:
     - `(Default)` = command line
   - Verify via `reg.exe query`. Log pass/miss with full path.
3. Save `.resolved/54-vscode-menu-installer/resolved.json` with the
   resolved exe + per-edition status.

---

## 8. Uninstall Algorithm (Surgical)

For each `editionName` in `config.enabledEditions` (or just the one passed
via `-Edition`):

1. Read **only** the three paths in `editions.<name>.registryPaths` from
   config. **No registry enumeration. No sibling-key discovery.**
2. For each path:
   - `reg.exe query` -> if not present, log "already absent: <path>" and
     continue.
   - If present, `reg.exe delete <path> /f`. Recursive delete handles the
     `\command` subkey automatically.
   - Log success/failure with the full path and (on failure) `reg.exe`
     exit code.
3. Purge `.installed/vscode-menu-installer.json` and
   `.resolved/54-vscode-menu-installer/`.

**Surgical guarantee:** because the loop iterates over a static path
allow-list, an unrelated key like
`HKCR\Directory\shell\VSCode2` or `HKCR\Directory\shell\OpenWithCode` is
**provably untouched** -- it never enters the loop.

---

## 9. Logging & CODE RED Compliance

| Failure | Logged path | Logged reason |
|---------|-------------|---------------|
| VS Code exe missing | Full expanded path | "executable not found -- skipping edition <name>" |
| Registry write failed | Full `Registry::HKEY_CLASSES_ROOT\…` path | Exception message |
| Registry delete failed | Translated `HKCR\…` path | `reg.exe exit <code>` |
| Verify miss | Full path | "expected present after install but absent" |
| Not admin | Current user name | "Administrator privileges required" |
| Unknown edition in `enabledEditions` | Edition name | "no editions.<name> block in config" |

---

## 10. Comparison with Script 10

| Concern | Script 10 (`vscode-context-menu-fix`) | Script 54 (`vscode-menu-installer`) |
|---------|---------------------------------------|--------------------------------------|
| File count | 3 (config, log-messages, run.ps1) + helpers | 5 (install + uninstall + run + 2 helpers) + config + log-messages |
| Auto-detect choco shim, WindowsApps, where.exe | Yes | **No** -- explicit `vsCodePath` only |
| Standalone install / uninstall files | No -- single `run.ps1` with subcommands | **Yes** -- `install.ps1` + `uninstall.ps1` |
| Uninstall surgical-by-allow-list | Best-effort | **Strict** -- enumerates only allow-list |
| Edition support | stable + insiders | stable + insiders |
| Dependency on shared helpers | Heavy (logging, resolved, git-pull, help, installed) | Light (logging, json-utils only) |
| Use case | First-time setup, repair, troubleshoot | Hand-off, repeatable install, scripted uninstall |

Both scripts can coexist. Script 10 remains the recommended entry point for
end users. Script 54 is the recommended entry point for tooling, automation,
and "I want to know exactly what gets touched" workflows.

---

## 11. Failure Modes

| Failure | Behavior |
|---------|----------|
| User runs without admin | Both scripts abort cleanly with admin message |
| `config.json` missing | Both scripts abort with full path in error |
| One edition's exe missing | That edition is skipped; other editions still process |
| All editions' exes missing | Install logs all paths tried, exits with non-zero code |
| Uninstall called before install | All three paths log "already absent" -- no error |
| Uninstall called twice | Second run is a no-op |
| User manually creates a sibling key (e.g. `\VSCode2`) | Sibling key is **never** read or modified |

---

## 12. Test Plan

1. **Fresh install (stable)**: `.\install.ps1 -Edition stable` → all three
   keys present, "Open with Code" appears in right-click.
2. **Surgical uninstall**: create a sibling test key
   `HKCR\Directory\shell\VSCode2` with `(Default) = "test"`. Run
   `.\uninstall.ps1 -Edition stable`. Confirm all three VSCode keys are
   gone AND the `VSCode2` test key is intact.
3. **Idempotent install**: run `install.ps1` twice → second run reports
   success, no errors.
4. **Idempotent uninstall**: run `uninstall.ps1` on a system that was
   never installed → all three paths log "already absent", exit 0.
5. **Both editions**: install both, uninstall both → both removed.
6. **Single edition uninstall preserves other**: install both, then
   `.\uninstall.ps1 -Edition stable` → insiders keys still present.
7. **Missing exe**: rename `Code.exe`, run install → edition is skipped,
   exact path logged, other editions still process.

---

## 13. Prerequisites

- Windows 10 / Windows 11
- PowerShell 5.1+
- Administrator privileges (asserted on entry by all three scripts)
- VS Code installed (path resolvable from config or `-VsCodePath`)

---

## 14. Definition of Done

- [x] Spec exists at `spec/54-vscode-menu-installer/readme.md` (this file)
- [x] `install.ps1` and `uninstall.ps1` are standalone, runnable directly
- [x] `config.json` declares the path allow-list explicitly
- [x] Uninstall iterates only the allow-list -- no enumeration
- [x] Both editions supported
- [x] CODE RED logging on every failure path
- [x] Registered as `54` in `scripts/registry.json`
- [x] Project version bumped (≥ minor) on first ship
- [x] Changelog entry added
