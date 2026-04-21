# Changelog

All notable changes to this project are documented in this file.

## [v0.58.0] -- 2026-04-21

### Added: confirmation prompt with Shift-click bypass for the Script Fixer menu (script 53)

Clicking any leaf in the cascading "Script Fixer vX.Y.Z" right-click menu now opens a 5-second countdown before invoking the chosen script. Hold **SHIFT** while right-clicking to reveal a twin "(no prompt -- Shift)" leaf that bypasses the countdown and runs immediately.

### Behavior

- **Default click**: opens elevated terminal -> "Auto-proceeding in 5s. Press Ctrl+C to cancel, any key to skip." -> runs `run.ps1 -I <id>`.
- **Shift+click**: a second leaf appears under the same cascading parent (Windows `Extended` verb attribute). Clicking it bypasses the prompt entirely.
- **Cancel during countdown**: Ctrl+C aborts -- script is NOT executed, terminal stays open so the user can read the cancellation message.
- **Skip during countdown**: any key proceeds immediately.

### New reusable helper

`scripts/shared/confirm-launch.ps1` -- exposes `Invoke-ConfirmedLaunch -RepoRoot -ScriptId -ScriptLabel -CountdownSeconds [-Bypass]`. Designed so any future menu (script 54, anything else) can opt in by pointing its `commandTemplate` at this helper -- single source of truth for "ask first, then run".

### Configuration (`scripts/53-script-fixer-context-menu/config.json`)

New block:

```json
"confirmBeforeLaunch": {
  "enabled": true,
  "countdownSeconds": 5,
  "emitBypassLeaves": true,
  "bypassLabelSuffix": " (no prompt -- Shift)",
  "bypassSubkeySuffix": "-NoPrompt"
}
```

Two command templates in `shell.commandTemplate` and `shell.bypassCommandTemplate` -- both call `Invoke-ConfirmedLaunch`, the bypass variant adds `-Bypass`. Placeholders: `{shellExe}`, `{repoRoot}`, `{scriptId}`, `{leafLabel}`, `{countdown}`.

### How "Shift to reveal" works

Each "no prompt" leaf gets the registry value `Extended = ""`. Windows hides any `shell\<verb>` entry carrying that value unless the user holds SHIFT during right-click. No DLL, no shell extension -- pure registry.

### Disabling

Set `confirmBeforeLaunch.enabled = false` and re-run `.\run.ps1 -I 53 refresh` to restore direct (no-prompt) leaves with no Shift twin. Set `emitBypassLeaves = false` to keep the prompt but drop the Shift bypass.

### Safety: helper-missing fallback

If `scripts/shared/confirm-launch.ps1` is absent at install time, the install logs the exact missing path (CODE RED rule) and falls back to direct invocation -- the menu still works, just without prompts. Install does not fail.

### Files

- **Added**: `scripts/shared/confirm-launch.ps1`
- **Modified**: `scripts/53-script-fixer-context-menu/config.json`, `scripts/53-script-fixer-context-menu/helpers/menu-writer.ps1` (`New-LeafEntry` now accepts `-Extended`), `scripts/53-script-fixer-context-menu/run.ps1` (dual-leaf emission via local `Write-ScriptLeafPair` helper).

### Refresh required

After upgrading, run `.\run.ps1 -I 53 refresh` (or `.\scripts\53-script-fixer-context-menu\install.ps1 -Refresh`) to rewrite the registry tree with the new dual leaves.

## [v0.57.0] -- 2026-04-21


### Added: standalone install/uninstall pair for the Script Fixer menu (script 53)

Two thin wrappers were added inside `scripts/53-script-fixer-context-menu/`:

- `install.ps1` -- alias for `.\run.ps1 install` (with `-Refresh` for `.\run.ps1 refresh`).
- `uninstall.ps1` -- alias for `.\run.ps1 uninstall`.

Existence rationale: hand-off / scheduling / linking from another tool now uses self-explanatory file names. All real logic still lives in `run.ps1` (single source of truth).

### Added: script 54 -- standalone VS Code menu installer/uninstaller

A new focused script `scripts/54-vscode-menu-installer/` ships an **independent** installer/uninstaller pair for the classic "Open with Code" right-click entries (file / folder / folder background). Coexists with script 10 (`vscode-context-menu-fix`); the two scripts have different jobs.

### What it does

- `install.ps1` writes the three context menu keys per enabled edition (stable, insiders).
- `uninstall.ps1` removes ONLY the registry paths declared in `config.json::editions.<name>.registryPaths` -- a strict allow-list. The uninstaller never enumerates the registry and never reads sibling keys, so a separately-installed key like `HKCR\Directory\shell\VSCode2` or `HKCR\Directory\shell\OpenWithCode` is **provably untouched**.
- `run.ps1` routes `install` / `uninstall` so the master `-I 54` dispatcher can invoke either path.

### Surgical-uninstall guarantee (your locked-in choice)

Per the user's "Path allow-list from config.json" decision, the uninstall loop iterates only over the three explicit `registryPaths` per edition. No registry enumeration, no fallback discovery, no label-match check -- just the static list. This is documented in `spec/54-vscode-menu-installer/readme.md` (G2, G3, section 8).

### Comparison: script 10 vs script 54

| Concern | Script 10 | Script 54 |
| --- | --- | --- |
| Standalone install/uninstall files | No | **Yes** |
| Auto-detect choco shim / WindowsApps / where.exe | Yes | No -- explicit `-VsCodePath` or config |
| Surgical-by-allow-list uninstall | Best-effort | **Strict** |
| Shared-helper dependency footprint | Heavy | Light |
| Use case | First-time setup, troubleshooting | Hand-off, scripted automation |

### File structure

```
scripts/54-vscode-menu-installer/
  config.json
  log-messages.json
  install.ps1
  uninstall.ps1
  run.ps1
  helpers/
    vscode-install.ps1
    vscode-uninstall.ps1
spec/54-vscode-menu-installer/
  readme.md
```

### Implementation notes

- Wildcard-safe writes via `[Microsoft.Win32.Registry]::ClassesRoot.CreateSubKey(...)`; deletes via `reg.exe delete /f`.
- Both editions (stable + insiders) are handled, and `-Edition <name>` lets you target one.
- VS Code path resolution is two-tier only: `-VsCodePath` override > expand env vars in `config.editions.<name>.vsCodePath`. No choco / where.exe / WindowsApps fallback (use script 10 for that).
- **CODE RED**: every install write, every uninstall delete, and every verify miss logs the exact registry path plus the failure reason.
- Registered as `"54": "54-vscode-menu-installer"` in `scripts/registry.json`.

## [v0.56.0] -- 2026-04-21


### Added: script 53 -- Script Fixer cascading right-click menu (opt-in)

A new opt-in PowerShell installer that adds a Windows Explorer right-click cascading menu titled **"Script Fixer v{version}"** (currently `Script Fixer v0.56.0`). Each leaf launches an **elevated** PowerShell terminal that runs the chosen script via the project's `run.ps1` dispatcher.

### What it does

- Reads `scripts/registry.json` and **auto-categorizes** every script (Databases, Editors & IDEs, Languages & Runtimes, Containers, Context Menu Fixers, Apps, etc.) using a config-driven map plus a heuristic fallback.
- Writes a cascading registry tree under **four scopes** so the menu appears everywhere: file right-click, folder right-click, folder background, and Desktop background.
- Single-script categories are flattened into the top level (no useless one-item submenus).
- Every leaf carries `HasLUAShield` so Windows shows the UAC shield and elevates via `runas` -- one prompt, no nested elevation.
- Uses `pwsh` 7+ when available (PATH -> `C:\Program Files\PowerShell\{7,6}` -> WindowsApps), falls back to `powershell` 5.1.

### Opt-in / opt-out

It is **not installed automatically**. Users who want it run:

```powershell
.\run.ps1 install      # add the menu (idempotent)
.\run.ps1 refresh      # uninstall + reinstall (run after editing registry.json or bumping version)
.\run.ps1 uninstall    # fully remove from every scope
```

### Why a separate script (53) instead of extending an existing one

Script 31 (`pwsh-context-menu`) and script 10 (`vscode-context-menu-fix`) each manage a single fixed entry. The Script Fixer menu is dynamic -- it rebuilds itself from `registry.json` -- so it gets its own folder with three focused helpers (`categorize.ps1`, `shell-detect.ps1`, `menu-writer.ps1`) and an `install | uninstall | refresh` command surface.

### File structure

```
scripts/53-script-fixer-context-menu/
  config.json
  log-messages.json
  run.ps1
  helpers/
    categorize.ps1
    shell-detect.ps1
    menu-writer.ps1
spec/53-script-fixer-context-menu/
  readme.md
```

### Implementation notes

- **Cascading menus**: built using the documented `MUIVerb` + `SubCommands=""` pattern (no DLL, no shell extension binary).
- **Wildcard-safe writes**: `[Microsoft.Win32.Registry]::ClassesRoot.CreateSubKey(...)` is used for writes (PowerShell's registry provider chokes on the `HKCR\*` wildcard); deletes use `reg.exe delete /f` for fully recursive teardown.
- **Idempotent install**: each scope's tree is wiped before being rebuilt, so re-running `install` always reflects the current `registry.json` and version.
- **Versioning**: top-level label is composed from `config.titleTemplate` (`"Script Fixer v{version}"`) using the value in `scripts/version.json`. Bumping the version requires `\.run.ps1 refresh` to refresh the menu label.
- **CODE RED compliance**: every registry write/delete failure logs the exact key path plus the failure reason (`reg.exe exit N` or exception message); shell-detection logs every searched path on a miss.
- Registered as `"53": "53-script-fixer-context-menu"` in `scripts/registry.json`.

## [v0.55.0] -- 2026-04-21


### Added: script 52 -- VS Code folder-only context menu repair

A new focused PowerShell script that repairs the Windows Explorer "Open with Code" entry so it appears **only when right-clicking folders** -- not on files and not on empty folder backgrounds -- then restarts `explorer.exe` so the change takes effect immediately without sign-out.

### What it does

1. **Removes** `HKCR\*\shell\VSCode` (file menu) and `HKCR\Directory\Background\shell\VSCode` (background menu)
2. **Ensures** `HKCR\Directory\shell\VSCode` (folder menu) exists with the correct label, icon and `"%V"` command
3. **Verifies** each target ended up in the expected state (present / absent)
4. **Restarts** `explorer.exe` (skippable via `.\run.ps1 no-restart` or `restartExplorer=false`)

Both **stable** and **insiders** editions are processed. Targets are configurable via `removeFromTargets` / `ensureOnTargets` arrays in `config.json`, so the same script can be repurposed (e.g. files-only, background-only) without code changes.

### File structure

```
scripts/52-vscode-folder-repair/
  config.json
  log-messages.json
  run.ps1
  helpers/repair.ps1
spec/52-vscode-folder-repair/
  readme.md
```

### Implementation notes

- **Reuses** `Resolve-VsCodePath`, `ConvertTo-RegPath` from script 10's `helpers/registry.ps1` -- no duplicated detection logic.
- Removal uses `reg.exe delete /f`, ensure uses `[Microsoft.Win32.Registry]::ClassesRoot` (avoids PowerShell provider issues with the `*` wildcard key).
- **CODE RED compliance**: every remove/ensure/verify failure logs the exact registry path plus the failure reason (`reg.exe exit N` or exception message).
- Registered as `"52": "52-vscode-folder-repair"` in `scripts/registry.json`.

## [v0.54.6] -- 2026-04-21


### Improved: thousand-separator `--summary-tail` values now get a dedicated warning

US-style (`1,000`) and EU-style (`1.000`) thousand-separated integers were previously misclassified -- `1,000` got the "comma decimal" warning (because of `3,5`), and `1.000` got the "trailing-dot decimal" warning. Both are clearly grouped integers, not decimals, so they now route through a dedicated branch that names the actual problem and suggests the stripped form.

**Behavior change** (warning text only -- all still fall back to default 20):

| Input          | Before (v0.54.5)                                | After (v0.54.6)                                                                              |
| -------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `1,000`        | "decimals are not allowed (got '1,000')"        | "thousand separators (',') are not allowed (got '1,000'); use a plain integer like '1000'"   |
| `1,000,000`    | "value '1,000,000' is not numeric"              | "thousand separators (',') are not allowed (got '1,000,000'); use a plain integer like '1000000'" |
| `1.000`        | "decimals are not allowed (got '1.000')"        | "thousand separators ('.') are not allowed (got '1.000'); use a plain integer like '1000'"   |
| `1.000.000`    | "value '1.000.000' is not numeric"              | "thousand separators ('.') are not allowed (got '1.000.000'); use a plain integer like '1000000'" |
| `-1,000`       | "decimals are not allowed (got '-1,000')"      | "thousand separators (',') are not allowed (got '-1,000'); use a plain integer like '-1000'" |
| `1,000.50`     | "value '1,000.50' is not numeric"               | unchanged (mixed separators -- ambiguous, stays generic)                                     |
| `3,5` / `3.5`  | "decimals are not allowed"                      | unchanged (still decimal-like)                                                               |
| `1,00`         | "value '1,00' is not numeric"                   | unchanged (2-digit trailing group is not a thousands shape)                                  |

### Implementation

- **`scripts/shared/registry-trace.ps1`** -- new `Test-ThousandSeparatorString` helper. Matches `^-?\d{1,3}(,\d{3})+$` (all-comma) and `^-?\d{1,3}(\.\d{3})+$` (all-dot). Mixed separators are intentionally rejected so they fall through to the generic branch.
- `Test-DecimalLikeString` now short-circuits to `$false` when the input matches a thousand-separator shape, so `1,000` / `1.000` never get misclassified as decimals.
- `Write-SummaryTailWarning` -- new branch placed BEFORE the decimal branch. Picks the separator (`','` or `'.'`) by inspecting the value, and computes the stripped suggestion (`$val -replace '[,.]',''`) so the user sees exactly what to type instead.
- **Verified**: thousand-sep, decimal, and integer inputs all route through their intended branch. Single-group `1.000` is treated as thousands (typo-friendly default), not as the decimal `1.000`.

No changes to `Get-SummaryTailArg` validation -- the parser still rejects anything that isn't a non-negative integer. Only the warning-message classification got more precise.

---

## [v0.54.5] -- 2026-04-21

### Improved: decimal-like `--summary-tail` values now warn consistently

Previously only strict `N.N` shapes (e.g. `3.5`) triggered the "decimals are not allowed" warning. Edge cases like `3.`, `.5`, `1e2`, or `3,5` (locale-comma) fell through to the generic "is not numeric" branch, confusing users who clearly intended a number.

**Behavior change** (warning text only -- all of these still fall back to default 20):

| Input        | Before (v0.54.4)                          | After (v0.54.5)                                |
| ------------ | ----------------------------------------- | ---------------------------------------------- |
| `3.5`        | "decimals are not allowed"                | "decimals are not allowed (got '3.5')"         |
| `3.`         | "value '3.' is not numeric"               | "decimals are not allowed (got '3.')"          |
| `.5`         | "value '.5' is not numeric"               | "decimals are not allowed (got '.5')"          |
| `1e2`        | "value '1e2' is not numeric"              | "decimals are not allowed (got '1e2')"         |
| `3,5`        | "value '3,5' is not numeric"              | "decimals are not allowed (got '3,5')"         |
| `abc`        | "value 'abc' is not numeric"              | unchanged                                      |
| `5O`         | "value '5O' is not numeric"               | unchanged                                      |

### Implementation

- **`scripts/shared/registry-trace.ps1`** -- new `Test-DecimalLikeString` helper centralises decimal detection. Recognised shapes: classic decimals (`3.5`), trailing dot (`3.`), leading dot (`.5`), signed decimals (`-3.5`), scientific notation (`1e2`, `1.5e2`), and comma-decimal (`3,5`). Plain integers still return `$false`.
- `Write-SummaryTailWarning` -- swapped the inline `^-?\d+\.\d+$` regex for a call to `Test-DecimalLikeString`. Decimal branch now echoes the offending value to match the format of the negative-integer branch.
- **Bug fix**: removed an orphan trailing `}` that had crept in after `Write-SummaryTailWarning` (would have caused a parser error if any function was added below it).
- **Verified**: all 16 test inputs (integers / decimal-like / non-numeric edge cases) route through the correct branch.

No changes to `Get-SummaryTailArg` validation -- the parser continues to reject anything that isn't a non-negative integer. Only the warning-message classification got more precise.

## [v0.54.4] -- 2026-04-21

### Improved: warning message echoes exact `--summary-tail` token form

The `[ WARN ]` line from `--summary-tail-warn` now quotes the user's verbatim flag token (preserving prefix style, casing, and separator) so it's immediately greppable in the original command line. Especially useful for empty/missing values where there's nothing else to identify the offending arg.

**Before** (v0.54.3):
```
[ WARN ] --summary-tail ignored: no value supplied after the flag. Falling back to default 20.
[ WARN ] --summary-tail ignored: empty value. Falling back to default 20.
```

**After** (v0.54.4):
```
[ WARN ] --summary-tail ignored: flag '--summary-tail=' has an empty value (nothing after the '='). Falling back to default 20.
[ WARN ] --summary-tail ignored: flag '/summary-tail:' has an empty value (nothing after the ':'). Falling back to default 20.
[ WARN ] --summary-tail ignored: flag '--Summary-Tail' supplied with no value after it. Falling back to default 20.
[ WARN ] --summary-tail ignored: '--summary-tail=abc' rejected -- value 'abc' is not numeric. Falling back to default 20.
```

The hint line below also now lists all 3 separator forms explicitly.

### Bug fix: colon separator (`--summary-tail:50`) now actually parses

The help text in v0.53.5 advertised `--summary-tail:50` as a valid form, but `Get-SummaryTailArg` only recognised `=`. Adding `--summary-tail:50` would silently fall back to default 20 (or trigger a confusing warning). `Get-SummaryTailArg`, `Remove-SummaryTailArg`, and `Get-SummaryTailRaw` now all accept `=` and `:` interchangeably.

### Implementation

- **`scripts/shared/registry-trace.ps1`**:
  - `Get-SummaryTailArg` -- inline-form loop now iterates over `@("=", ":")` separators
  - `Remove-SummaryTailArg` -- recognises both `--summary-tail=N` and `--summary-tail:N` for stripping
  - `Get-SummaryTailRaw` -- returns a new `Token` field with the verbatim user-typed prefix (e.g. `"--summary-tail="`, `"/summary-tail:"`, `"--Summary-Tail"`); `Form` now includes `"colon"`
  - `Write-SummaryTailWarning` -- form-specific reason text references `$token`; updated hint line shows all three accepted forms side by side
  - Backward compatible: missing `Token` field falls back to `"--summary-tail"` for older callers

## [v0.54.3] -- 2026-04-21

### Added: `--summary-tail-quiet` override flag

Companion to v0.54.0's `--summary-tail-warn`. Suppresses the `[ WARN ]` line for invalid `--summary-tail` values while keeping the silent fallback to default 20. Designed for CI workflows that have `--summary-tail-warn` enabled globally but want to silence noise on specific jobs that legitimately pass placeholders or computed values.

**Behavior matrix** (with invalid `--summary-tail abc`):

| Flags                                       | Output                          |
| ------------------------------------------- | ------------------------------- |
| (neither)                                   | silent fallback to 20 (default) |
| `--summary-tail-warn`                       | `[ WARN ]` + fallback to 20     |
| `--summary-tail-quiet`                      | silent fallback to 20 (no-op)   |
| `--summary-tail-warn --summary-tail-quiet`  | silent fallback to 20 (quiet wins) |

**Accepted forms** (case-insensitive): `--summary-tail-quiet`, `-summary-tail-quiet`, `/summary-tail-quiet`.

### Implementation

- **`scripts/shared/registry-trace.ps1`** -- 2 new helpers mirroring the warn-switch pair:
  - `Test-SummaryTailQuietSwitch` -- detects the flag in `$Argv`
  - `Remove-SummaryTailQuietSwitch` -- strips it before forwarding to children
- **`scripts/os/run.ps1`** -- dispatcher resolves `$emitTailWarn = $wantsTailWarn -and -not $wantsTailQuiet` so quiet always wins when both are present
- **`scripts/os/helpers/clean-runner.ps1`** -- same wiring at the per-category level
- **Help updated**: new flag entry under REGISTRY TRACE FLAGS plus a "Flag combination matrix" block in `Show-OsHelp`

No breaking changes. Default behavior remains silent.

## [v0.54.2] -- 2026-04-21

### Added: GitHub Actions CI example in `os --help`

New "CI EXAMPLE" section in `Show-OsHelp` demonstrates how `--summary-tail-warn` catches typos in workflow variables before they cause silent fallbacks. Includes a complete `.github/workflows/cleanup.yml` snippet, a worked typo scenario (`vars.TAIL_LINES = '5O'`), and a one-liner `grep` recipe to fail the job on bad config.

- **`scripts/os/run.ps1`** `Show-OsHelp`: appended a new "CI EXAMPLE -- catch typos in GitHub Actions" block after the "TRY IT" section. The snippet shows:
  - Full workflow YAML using `pwsh` shell, `actions/checkout@v4`, and `Tee-Object` to capture `summary.json`
  - Side-by-side comparison: silent fallback (no warn flag) vs visible `[ WARN ]` line (with warn flag)
  - How to confirm the resolution path via the new `tailSource` field (`default` vs `env`)
  - Optional `grep` recipe to convert the warning into a fail-fast CI check

Documentation only; no runtime behavior changes.

## [v0.54.1] -- 2026-04-21

### Added: "effective tail" line in summary header

The end-of-run registry-trace summary now displays which fallback was used to resolve the tail value, so users can confirm at a glance whether their `--summary-tail` was honoured or silently overridden.

**Human summary** -- new line right under the header:
```
  Registry trace summary
  ----------------------
    effective tail = 20 (from default)
    last 7 of 7 trace line(s):
    ...
```

The `(from ...)` value is one of:
- **`param`** -- explicit `-TailLines` parameter passed to `Close-RegistryTrace` (programmatic callers)
- **`env`** -- resolved from `REGTRACE_SUMMARY_TAIL` env var (set by `--summary-tail N` at the dispatcher)
- **`default`** -- nothing valid was passed; fell back to the module default (20)

**JSON summary** -- new `tailSource` field with the same three values:
```json
{"...","tailShown":20,"tailMax":20,"tailSource":"env","timestamp":"..."}
```

**Logfile mirror** -- the in-file summary block also gains the `effective tail = N (from <source>)` line so the trace logfile stays self-describing.

### Implementation

- **`scripts/shared/registry-trace.ps1`**:
  - `Close-RegistryTrace` now tracks a `$tailSource` variable alongside `$effectiveTail` during the param > env > default resolution chain
  - `Show-RegistryTraceSummary` accepts a new `-Source` parameter and prints the "effective tail" line in the header (always shown, even when 0 ops recorded)
  - `Show-RegistryTraceSummaryJsonOutput` accepts `-Source` and emits it as `tailSource` in the JSON payload
  - In-file summary mirror also prints the same line for log self-documentation

No breaking changes -- new parameters default to `"default"` so external callers continue to work unchanged.

## [v0.54.0] -- 2026-04-21

### Added: opt-in `--summary-tail-warn` flag for surfacing invalid `--summary-tail` values

Invalid `--summary-tail` values are still silently dropped by default (preserving CI pipeline stability), but you can now opt in to warnings when you want typos surfaced.

**New flag**: `--summary-tail-warn` (also accepts `-summary-tail-warn`, `/summary-tail-warn`, case-insensitive). When set, an invalid `--summary-tail` value triggers a yellow `[ WARN ]` line explaining exactly why the value was rejected:

```
.\run.ps1 os clean --summary-tail abc --summary-tail-warn
# [ WARN ] --summary-tail ignored: value 'abc' is not numeric. Falling back to default 20.
#         Pass a non-negative integer (e.g. --summary-tail 50, =50, :50).
```

The reason text is specific:
- `--summary-tail -1` -> "negative integers are not allowed (got '-1')"
- `--summary-tail abc` -> "value 'abc' is not numeric"
- `--summary-tail 3.5` -> "decimals are not allowed (got '3.5'); use an integer"
- `--summary-tail` (missing value) -> "no value supplied after the flag"

### Implementation

- **`scripts/shared/registry-trace.ps1`** -- 4 new helpers:
  - `Get-SummaryTailRaw` -- inspects `$Argv` and returns `@{Present, RawValue, Form}` so dispatchers can distinguish "flag absent" from "flag present with bad value"
  - `Test-SummaryTailWarnSwitch` / `Remove-SummaryTailWarnSwitch` -- mirror the existing summary-json switch helpers
  - `Write-SummaryTailWarning` -- emits the yellow `[ WARN ]` line with a precise reason
- **`scripts/os/run.ps1`** -- dispatcher detects the warn switch first, strips it, then warns if `Get-SummaryTailArg` returned `$null` while the flag was actually present
- **`scripts/os/helpers/clean-runner.ps1`** -- same wiring at the per-category dispatcher level so `os clean-<name>` invocations also honour the flag
- **Help updated** in both `Show-OsHelp` and the `registry-trace.ps1` comment-based help, with a new "Opt-in surfacing" subsection and worked example

Behavior with the flag absent is **unchanged** -- silent fallback to default 20 remains the default.

## [v0.53.5] -- 2026-04-21

### Documented: comprehensive `--summary-tail` syntax reference

Expanded help text now documents all accepted argument forms with clear valid/invalid examples, eliminating guesswork about which separators and casing work.

- **`scripts/shared/registry-trace.ps1`** comment-based help:
  - New "Accepted forms (case-insensitive)" subsection lists all 9 valid syntax variants: space/equals/colon separators with double-dash, single-dash, and Windows slash prefixes
  - New "Valid vs invalid values" table covering negatives, non-numeric strings, decimals, and missing values

- **`scripts/os/run.ps1`** `Show-OsHelp` REGISTRY TRACE FLAGS section:
  - Expanded syntax list with 6 color-coded examples showing space, equals, colon, single-dash, PascalCase, and slash styles
  - New "VALID vs INVALID examples" block with 8 lines showing exactly which forms parse correctly vs fall back to 20

## [v0.53.4] -- 2026-04-21

### Added: "Try it" copy-paste examples for `--summary-tail`

New hands-on examples in help text let users immediately test `--summary-tail` behavior with `-1`, `abc`, `0`, and `50` values, showing the exact JSON `tail[]` output for each case.

- **`scripts/shared/registry-trace.ps1`** comment-based help: new "Try it" subsection with 4 copy-pasteable command lines and their expected JSON output snippets.
- **`scripts/os/run.ps1`** `Show-OsHelp`: new "TRY IT (copy-paste examples)" section under REGISTRY TRACE FLAGS with color-coded PowerShell examples and explanatory comments.

## [v0.53.3] -- 2026-04-21

### Documented: invalid `--summary-tail` value handling

Expanded help to spell out exactly what happens when users pass invalid values like `--summary-tail -1` or `--summary-tail abc`. Behavior is unchanged from v0.53.0 -- this is a documentation clarification only.

- **`scripts/shared/registry-trace.ps1`** comment-based help: edge case 3 now traces the full fallback chain (Get-SummaryTailArg returns `$null` -> dispatcher skips setting env var -> Close-RegistryTrace resolves to module default 20 -> both outputs use 20). Includes a worked-examples table covering `-1`, `abc`, `3.5`, `""`, missing value, `0`, and `50`.
- **`scripts/os/run.ps1`** `Show-OsHelp`: REGISTRY TRACE FLAGS parity block now lists `--summary-tail -1`, `--summary-tail abc`, and `--summary-tail 0` as separate one-liners showing exact fallback behavior.

Key clarification: invalid args are SILENTLY ignored (no warning printed) to keep CI pipelines deterministic. Both human summary and JSON `tail[]` use the same fallback value of 20.

## [v0.53.2] -- 2026-04-21

### Documented: parity behavior between human summary and `--summary-json` tail

Following a parity audit (no code drift found), the help text now explicitly documents how the two output channels behave under edge conditions, so users running CI scrapers know what to expect.

- **`scripts/shared/registry-trace.ps1`** comment-based help: new "Parity guarantees" subsection covering three edge cases:
  1. Zero recorded operations -- human notice vs `tail: []`, both 0 lines.
  2. `REGTRACE_SUMMARY_TAIL` greater than the 20-line internal buffer cap -- both outputs clamp to `min(request, buffer)`.
  3. Negative or non-numeric values -- both fall back to default of 20.
- **`scripts/os/run.ps1`** `Show-OsHelp`: condensed parity note added under the REGISTRY TRACE FLAGS block (3 bullet points covering the same edge cases).

No behavioral changes -- documentation only.

## [v0.53.1] -- 2026-04-21

### Added: `--summary-tail` usage documentation

- Added comprehensive help section to `scripts/os/run.ps1` `Show-OsHelp` documenting the `--summary-tail N` flag.
- Documented all six accepted flag formats: `--summary-tail N`, `--summary-tail=N`, `-summary-tail N`, `-summary-tail:N`, `-SummaryTail N` (PascalCase), `--tail-lines N`.
- Explained the special value `N=0` ("totals only" -- no tail lines, just OK/FAIL/SKIP counts).
- Documented companion flags `-Verbose` and `--summary-json` in the same "REGISTRY TRACE FLAGS" help section.
- Extended comment-based help in `scripts/shared/registry-trace.ps1` with detailed `.DESCRIPTION` covering activation, log file naming, end-of-run summary behavior, `--summary-tail` formats, and `--summary-json` machine-readable output.

## [v0.53.0] -- 2026-04-21

### Added: `--summary-tail N` flag to control end-of-run trace tail size

The end-of-run registry-trace summary (introduced in v0.51) and the JSON summary line (v0.52) both defaulted to printing the last 20 trace lines. Users debugging a 200-op registry sweep wanted more; users running CI grep loops wanted less. New global flag `--summary-tail N` lets the caller pick any non-negative integer.

```
.\run.ps1 os clean-explorer-mru --verbose --summary-tail 50    # show last 50
.\run.ps1 os flp --verbose --summary-tail 0                    # totals only
.\run.ps1 os clean --bucket B --summary-json --summary-tail 5  # tiny CI line
```

`0` is honoured (totals + JSON counts only, empty `tail[]` array). Negative or non-numeric values are ignored and the default of 20 is kept.

#### Implementation: `scripts/shared/registry-trace.ps1`

- New `Get-SummaryTailArg -Argv $argv` -- parses six accepted forms (`--summary-tail N`, `-summary-tail N`, `/summary-tail N`, plus `=`-joined variants). Returns `$null` on absent / invalid value so the caller can fall through to the default.
- New `Remove-SummaryTailArg -Argv $argv` -- strips the flag **and** its value when the value is the next token, defensively leaving non-numeric next tokens alone so we don't accidentally swallow an unrelated arg.
- `Close-RegistryTrace` gained a `[Nullable[int]]$TailLines` parameter and an env-var fallback `REGTRACE_SUMMARY_TAIL`. Resolution order: explicit `-TailLines` param > env var > module default `$script:_RegTraceTailMax` (20). The resolved value is then passed to **both** `Show-RegistryTraceSummary` (human box) and `Show-RegistryTraceSummaryJsonOutput` (JSON line) so the two stay in sync. Negative values are clamped to 0.

#### Wiring: same dispatcher pattern as `--summary-json`

- `scripts/os/run.ps1` -- after the existing `--summary-json` block: `Get-SummaryTailArg` / `Remove-SummaryTailArg`, then `$env:REGTRACE_SUMMARY_TAIL = "$N"`.
- `scripts/os/helpers/clean-runner.ps1` -- same block alongside the `-Verbose` and `--summary-json` parsers, so direct `clean-<name>` invocations also work.

The env-var propagation means **zero leaf-helper changes** -- `longpath.ps1` and all 36 `clean-categories\*.ps1` files already call `Close-RegistryTrace`, which now reads `REGTRACE_SUMMARY_TAIL` automatically. Same architectural rationale as v0.52: avoiding 37+ touch points of `[switch]$SummaryTail` boilerplate.

#### Files touched

- `scripts/shared/registry-trace.ps1` -- 2 new functions, `Close-RegistryTrace` updated with `[Nullable[int]]$TailLines` + env-var fallback.
- `scripts/os/run.ps1` -- 7-line block after the `--summary-json` parser.
- `scripts/os/helpers/clean-runner.ps1` -- matching 8-line block alongside the `--summary-json` parser.
- `scripts/version.json` -- `0.52.0` -> `0.53.0`.

## [v0.52.0] -- 2026-04-21

### Added: `--summary-json` machine-readable run summary on stdout

Every script that already prints the human-readable registry-trace summary (`os flp`, every `os clean-<name>`) now also accepts a global `--summary-json` flag. When present, `Close-RegistryTrace` writes one extra line to **stdout** at the end of the run -- a single-line JSON object with the OK/FAIL/SKIP counts and the same tail lines that the boxed summary block prints. Designed for CI wrappers, `jq`, and quick `grep` filters.

```
$ .\run.ps1 os flp --summary-json
  ... (normal human output)
REGTRACE_SUMMARY_JSON {"script":"os-fix-long-path","logfile":null,"verbose":false,"counts":{"ok":2,"fail":0,"skip":1,"total":3},"tail":["[2026-04-21 14:32:11.482] [SET         ] [OK  ] HKLM:\\..."],"tailShown":3,"tailMax":20,"timestamp":"2026-04-21T14:32:11.5012345+08:00"}
```

The `REGTRACE_SUMMARY_JSON ` prefix lets a caller `grep ^REGTRACE_SUMMARY_JSON` to pluck exactly one line from mixed stdout, strip the prefix, and pipe into `jq`. The JSON itself is emitted with `ConvertTo-Json -Compress` so it always fits on a single line regardless of tail size.

#### Implementation: `scripts/shared/registry-trace.ps1`

- New module-scoped flag `$script:_RegTraceSummaryJson` (default `$false`).
- New `Set-RegistryTraceSummaryJson [-Enabled $true]` -- explicit toggle for callers that have already parsed the flag themselves.
- New `Test-SummaryJsonSwitch -Argv $argv` -- mirrors `Test-VerboseSwitch`. Recognises `--summary-json`, `-summary-json`, `/summary-json`.
- New `Remove-SummaryJsonSwitch -Argv $argv` -- returns a copy of `$Argv` with the flag tokens stripped. Required because the leaf helpers (`longpath.ps1`, `clean-categories\*.ps1`) use `[CmdletBinding()]` and would throw on the unknown switch if it reached them.
- New `Show-RegistryTraceSummaryJsonOutput [-TailLines 20]` -- builds an `[ordered]` payload `{ script, logfile, verbose, counts{ok,fail,skip,total}, tail[], tailShown, tailMax, timestamp }` and emits `Write-Output "REGTRACE_SUMMARY_JSON <json>"`. Always emits, even on a zero-op run, so a CI consumer can rely on **exactly one** prefixed line per script invocation.
- `Close-RegistryTrace` now consults both the module flag and the env-var fallback `REGTRACE_SUMMARY_JSON=1` (accepted: `1|true|yes|on`). The env-var path is what makes the flag travel across the splat boundary into `[CmdletBinding()]` children we don't want to add a `[switch]$SummaryJson` parameter to.
- The existing `-NoSummary` switch suppresses both the human and the JSON output, preserving the escape hatch.

#### Wiring: dispatchers strip the flag and propagate via env

- `scripts/os/run.ps1` -- dot-sources `registry-trace.ps1`, then early-checks `$Rest` with `Test-SummaryJsonSwitch`. On hit: strips it via `Remove-SummaryJsonSwitch`, sets `$env:REGTRACE_SUMMARY_JSON = "1"`, calls `Set-RegistryTraceSummaryJson -Enabled $true`. The cleaned `$Rest` is then splatted to whichever helper handles the action (`flp`, `clean`, `clean-<name>`, `temp-clean`, `hibernate`, `add-user`).
- `scripts/os/helpers/clean-runner.ps1` -- same treatment on `$Argv` right after the existing `Test-VerboseSwitch` block, so direct invocations of `clean-<name>` (which bypass the outer dispatcher) also work. The env var carries the flag into the spawned category helper's own `Close-RegistryTrace` call.

#### Why env var instead of a `[switch]` parameter on every helper

Adding `[switch]$SummaryJson` to all 36 `clean-categories\*.ps1` helpers plus `longpath.ps1` would have been 37+ touch points of boilerplate. The env-var fallback inside `Close-RegistryTrace` keeps the change to two dispatchers and one shared helper, and gracefully degrades: if a future helper is invoked completely standalone (no dispatcher), `--summary-json` simply won't be parsed and the env var won't be set -- no error, just no JSON line. Callers who need it from a standalone script can call `Set-RegistryTraceSummaryJson -Enabled $true` directly before exit.

#### Files touched

- `scripts/shared/registry-trace.ps1` -- 4 new functions, `Close-RegistryTrace` updated.
- `scripts/os/run.ps1` -- dot-source registry-trace and a 6-line strip/propagate block at top.
- `scripts/os/helpers/clean-runner.ps1` -- 6-line strip/propagate block alongside the existing `-Verbose` parser.
- `scripts/version.json` -- `0.51.0` -> `0.52.0`.

No leaf helpers, no log-message JSON files, and no spec docs needed changes.

## [v0.51.0] -- 2026-04-21

### Added: end-of-run registry-trace summary (last 20 lines + OK/FAIL/SKIP totals)

Every script that uses the verbose registry-trace helper (`os flp`, `os clean-explorer-mru`, plus any future caller) now ends with a one-command summary block printed to the host **and** appended to the trace logfile:

```
  Registry trace summary
  ----------------------
    last 20 of 47 trace line(s):
      [2026-04-21 14:32:11.482] [SET         ] [OK  ] HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem :: LongPathsEnabled  old=<null>  new=1
      [2026-04-21 14:32:11.501] [GET         ] [OK  ] HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem :: LongPathsEnabled  value=1  reason=post-write verification
      ...

    totals: OK=44  FAIL=1  SKIP=2  (total 47)
    full log: C:\dev\.logs\os-fix-long-path-registry-trace.log
```

#### Implementation: `scripts/shared/registry-trace.ps1`

- New module-scoped state: `$script:_RegTraceCounts = @{ OK; FAIL; SKIP }` and a `Queue[string]` ring buffer `$script:_RegTraceTail` capped at `$script:_RegTraceTailMax = 20`. Both are reset inside `Initialize-RegistryTrace` so each run starts clean.
- `Write-RegistryTrace` now tallies the `Status` and pushes the formatted line onto the tail queue **before** the disk write. Counters survive even if the disk write fails and the trace then disables itself -- the summary still reflects what was attempted.
- New `Get-RegistryTraceCounts` -- returns `@{ OK; FAIL; SKIP; Total }` for programmatic callers.
- New `Show-RegistryTraceSummary [-TailLines 20]` -- prints the boxed summary to host with per-status colouring (`OK`=green, `FAIL`=red, `SKIP`=yellow), then mirrors the same block into the trace logfile so the file stays self-describing. Safe when `-Verbose` was never set: prints a single dim-grey "pass `-Verbose` to enable" notice and returns.
- `Close-RegistryTrace` now invokes `Show-RegistryTraceSummary` automatically before the existing footer write. Adds a `-NoSummary` switch for the rare caller that wants to suppress it. **No changes required in `longpath.ps1` or `explorer-mru.ps1`** -- they already call `Close-RegistryTrace` at every exit point, so the summary fires for free on every code path including the early-return / verify-mismatch / exception branches.

#### Files changed

- **Updated**: `scripts/shared/registry-trace.ps1`, `scripts/version.json` (0.50.0 -> 0.51.0)

## [v0.50.0] -- 2026-04-21

### Added: `run.ps1 scan <path>` -- VS Code Project Manager projects.json sync

New top-level dispatcher command that walks a directory tree, discovers project folders, and **upserts** them into the VS Code Project Manager extension's (`alefragnani.project-manager`) `projects.json` file. The command **never opens VS Code** -- it only mutates the JSON file so projects show up in the extension's sidebar on the next VS Code launch / reload.

#### Command surface

```powershell
.\run.ps1 scan <root-path>                  # walk + upsert (default depth 5)
.\run.ps1 scan <root-path> --depth 4        # custom recursion depth
.\run.ps1 scan <root-path> --dry-run        # preview, write nothing
.\run.ps1 scan <root-path> --json <file>    # override target projects.json (testing)
.\run.ps1 scan <root-path> --include-hidden # walk into folders starting with '.'
.\run.ps1 scan --help
```

If `<root-path>` is omitted, the current working directory is used.

#### New module: `scripts/scan/`

- `run.ps1` -- dispatcher: argument parsing, banner, walk -> upsert -> atomic write -> summary.
- `config.json` -- `defaultDepth`, `skipDirs` (`.git`, `node_modules`, `vendor`, `dist`, `build`, `target`, `.next`, `.venv`, `venv`, `__pycache__`, `.gradle`, `bin`, `obj`, ...), `markers` (files: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`, `pom.xml`, `Gemfile`, ...; patterns: `*.csproj`, `*.sln`; dirs: `.git`, `.lovable`).
- `log-messages.json` -- banner, help text, every status string.
- `helpers/walker.ps1` -- iterative DFS with depth cap. `Test-IsProjectFolder` checks marker files, glob patterns, and marker dirs; `Find-Projects` returns project paths and **does not descend into** a folder once it qualifies (kills nested `node_modules` noise).
- `helpers/vscode-projects.ps1` -- five exported functions:
  - `Get-VSCodeProjectsJsonPath` resolves the per-OS path: Windows `%APPDATA%\Code\User\globalStorage\alefragnani.project-manager\projects.json`, macOS `~/Library/Application Support/Code/User/globalStorage/.../projects.json`, Linux `$XDG_CONFIG_HOME/Code/User/.../projects.json` (defaults to `~/.config/Code/...`).
  - `Initialize-VSCodeProjectsJson` creates the parent directory and seeds the file with `[]` (UTF-8, no BOM) when missing. CODE RED: file/path failures log the exact path via `Write-FileError`.
  - `Read-VSCodeProjects` parses the JSON; tolerates an empty file; normalises a single-object document into a 1-element array.
  - `Add-OrUpdateVSCodeProject` upserts in-memory by `rootPath`. **Match key** is `ConvertTo-RootPathKey` (lowercase + trailing-slash strip on Windows; trailing-slash strip only on Unix). Returns `"added"` for new entries; returns `"noop"` when the `rootPath` already exists -- existing `name`, `paths`, `tags`, `enabled`, `profile` are **never overwritten** by `scan` so user aliases survive.
  - `Save-VSCodeProjects` performs the **atomic write**: serialise -> write to `projects.json.tmp-<pid>-<ticks>` in the same directory -> `Move-Item -Force` over the original. Temp file is removed on any failure; the original is left untouched.

#### Project detection markers

A folder is treated as a project when it contains any of: `.git/`, `package.json`, `pyproject.toml`, `requirements.txt`, `setup.py`, `Cargo.toml`, `go.mod`, `composer.json`, `pom.xml`, `build.gradle`, `build.gradle.kts`, `*.csproj`, `*.sln`, `Gemfile`, `.lovable/`. All markers configurable via `scripts/scan/config.json`.

#### Schema (locked from user-supplied sample)

```json
{ "name": "...", "rootPath": "...", "paths": [], "tags": [], "enabled": true, "profile": "" }
```

On insert: `name = folder basename`, all other fields default. On any subsequent run: existing entry is left alone -- `scan` is purely additive for the user-managed fields.

#### Dispatcher wiring (`run.ps1`)

Added `$isBareScanCommand = $normalizedCommand -eq "scan"` next to the existing `$isBarePathCommand`, plus a routing branch that forwards `$Install` (the `ValueFromRemainingArguments` string array) into `scripts/scan/run.ps1`. Behaves identically to the existing `path` / `doctor` / `os` / `git-tools` bare-command branches.

#### Spec + memory

- Spec: `spec/01-vscode-project-manager-sync/readme.md` -- full command surface, schema, atomic-write algorithm, acceptance criteria.
- Memory: `.lovable/memory/features/vscode-projects-sync.md` -- per-OS target paths, hard rules (match by `rootPath`, atomic writes, never opens VS Code, `git map` with a space is forbidden anywhere), file layout.

#### Hard rules enforced

1. Match key is `rootPath` (case-insensitive on Windows).
2. `scan` never opens VS Code.
3. Atomic writes only -- aborted runs cannot corrupt `projects.json`.
4. Existing entries / fields not added by us are preserved verbatim.
5. The string `git map` (with a space) appears nowhere in the new code, help, or logs.

#### Out of scope (deferred)

- `gitmap code <alias>` CLI subcommand
- SQLite storage (user opted for JSON-only)
- Auto-deriving `tags`
- Multi-root (`paths`) authoring

#### Files added/changed

- **Added**: `scripts/scan/run.ps1`, `scripts/scan/config.json`, `scripts/scan/log-messages.json`, `scripts/scan/helpers/walker.ps1`, `scripts/scan/helpers/vscode-projects.ps1`, `spec/01-vscode-project-manager-sync/readme.md`, `.lovable/memory/features/vscode-projects-sync.md`
- **Updated**: `run.ps1` (added `$isBareScanCommand` + routing branch), `scripts/version.json` (0.49.0 -> 0.50.0)

## [v0.49.0] -- 2026-04-21

### Added: verbose registry-trace mode for both registry-touching scripts (`os flp` + `os clean-explorer-mru`)

Pass `-Verbose` (PowerShell CommonParameter) to either script and every registry read, write, value delete, and key delete is appended to a dedicated plain-text sidecar log under `.logs/`, independent of the structured JSON log produced by `logging.ps1`. The trace captures the exact `HK*:\...` path, value name, old value, new value, outcome (`OK` / `FAIL` / `SKIP`), and the verbatim exception message on failure.

#### New shared helper: `scripts/shared/registry-trace.ps1`

Four exported functions, all StrictMode-clean, all module-scoped state:

- `Initialize-RegistryTrace -ScriptName <name> -VerboseEnabled <bool>` -- called once near the top of a host script (after `Initialize-Logging`). Sanitises the script name into `<sanitised>-registry-trace.log` under `.logs/` (repo root, parent of `scripts/`, matching the logging memory) and writes a header block: timestamp, user, host, PID, PSVersion, log path. **No-op when `-VerboseEnabled` is `$false`** -- the file is never created. Failures to create `.logs/` or write the header disable the trace gracefully and emit a single yellow `[ WARN ]` (CODE RED: the failing path is included verbatim).
- `Write-RegistryTrace -Op <SET|GET|REMOVE-VALUE|REMOVE-KEY|READ-ONLY> -Path <regPath> [-Name <valName>] [-OldValue <obj>] [-NewValue <obj>] [-Status <OK|FAIL|SKIP>] [-Reason <text>]` -- one trace line. Format: `[2026-04-21 14:32:11.482] [SET         ] [OK  ] HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem :: LongPathsEnabled  old=<null>  new=1`. For `FAIL` the reason carries the exception message verbatim. Disables itself on a write failure (after a single warn) so a borked SD card doesn't spam the host stream.
- `Close-RegistryTrace [-Status <text>]` -- appends a footer with finish timestamp + final status.
- `Test-VerboseSwitch -Argv <string[]>` -- mirrors `Test-DryRunSwitch` / `Test-YesSwitch` from `_sweep.ps1`. Recognises `--verbose`, `-verbose`, `/verbose`. Used by `clean-runner.ps1` to detect the flag before splatting it into a category helper.

#### Wiring: `scripts/os/helpers/longpath.ps1` (`os flp`)

Now declares `[CmdletBinding()]` so PowerShell's built-in `-Verbose` parameter is honoured. Initialises the trace as `os-fix-long-path` immediately after `Initialize-Logging`. Records the pre-flight `Get-ItemProperty`, the early-exit when already enabled (`READ-ONLY` + `SKIP`), the `Set-ItemProperty` write itself (`SET`, with `old=` from the pre-flight and `new=1`), the post-write verification (`GET`, reason `post-write verification`), and the verification-mismatch path (`READ-ONLY` + `FAIL`). Both `$PSBoundParameters.ContainsKey('Verbose')` and the inherited `$VerbosePreference` are checked, so the trace fires whether the user types `os flp -Verbose` directly or `run.ps1` forwards the flag through `@Rest`.

#### Wiring: `scripts/os/helpers/clean-categories/explorer-mru.ps1` (`os clean-explorer-mru`)

Now declares `[CmdletBinding()]` and initialises the trace as `os-clean-explorer-mru`. Records each of the three top-level keys (`RunMRU`, `RecentDocs`, `TypedPaths`) as `READ-ONLY` + `SKIP` when missing or `GET` with the enumerated value count when present, each value deletion as `REMOVE-VALUE` with the old value (best-effort `Get-ItemProperty` before deletion) and `OK` / `FAIL` + exception message, and each `RecentDocs` per-extension subkey deletion as `REMOVE-KEY` + `OK` / `FAIL`. Dry-run mode logs every would-be deletion as `REMOVE-VALUE` + `SKIP` + reason `dry-run`, so the trace doubles as a preview. `Close-RegistryTrace` is called with the final result `Status`.

#### Wiring: `scripts/os/helpers/clean-runner.ps1`

Parses `--verbose` from `$Argv` via `Test-VerboseSwitch`, then forwards `-Verbose` to the category helper **only when the helper declares `[CmdletBinding()]`** (detected by grepping the first 12 lines of the helper for `[CmdletBinding()]`). Splatting an empty hashtable into the other 58 non-cmdlet helpers keeps them untouched -- no risk of "A parameter cannot be found that matches parameter name 'Verbose'" on the bun/cargo/chrome/etc. cleaners.

Both invocation paths work:

```
.\run.ps1 os flp -Verbose
.\run.ps1 os clean-explorer-mru --verbose
.\run.ps1 os clean-explorer-mru --dry-run --verbose
```

#### Log file location + naming

Per the `logging.ps1` memory rule, traces live in `.logs/` at repo root (parent of `scripts/`), **never** `scripts/logs/`. Sanitisation is `lowercase -> [^a-z0-9]+ collapsed to '-' -> trimmed`, identical to the JSON log convention:

- `.logs/os-fix-long-path-registry-trace.log`
- `.logs/os-clean-explorer-mru-registry-trace.log`

Tail in a second terminal:

```
Get-Content .logs\os-fix-long-path-registry-trace.log -Wait -Tail 20
```

#### What was *not* changed

- The structured JSON log under `.logs/<script>.json` is untouched. The trace is a sidecar, not a replacement.
- The other 58 cleaners do not get `[CmdletBinding()]`. They don't touch the registry; adding the trace would be noise. The infrastructure is in place to extend later -- a new registry-touching helper just needs `[CmdletBinding()]`, the two `Initialize-RegistryTrace` lines at the top, and `Write-RegistryTrace` calls around its registry writes.
- No `os flp` / `os clean-explorer-mru` behaviour changes when `-Verbose` is **not** passed: zero new files, zero new host output, zero performance impact (the `Write-RegistryTrace` early-out is a single boolean check).

#### Files changed

```
NEW     scripts/shared/registry-trace.ps1                       (~190 lines)
MOD     scripts/os/helpers/longpath.ps1                         ([CmdletBinding] + 6 trace calls)
MOD     scripts/os/helpers/clean-categories/explorer-mru.ps1    ([CmdletBinding] + 8 trace calls)
MOD     scripts/os/helpers/clean-runner.ps1                     (verbose detection + cmdlet-binding-gated splat)
MOD     scripts/version.json                                    (0.48.1 -> 0.49.0)
MOD     changelog.md                                            (this entry)
```

> **Version note:** the user requested v0.47.1 for this change, but v0.47.1 was
> already published (the starship local-wrapper release on 2026-04-21). To keep
> the version chain monotonic this entry ships as **v0.48.1**.

## [v0.48.1] -- 2026-04-21

### Added: doctor `--self-check` section (e) -- live SHA256 pin verification + new `--skip-network` flag

Section (e) closes the last gap in the CODE RED integrity chain. Sections (a)-(d) verify that the project is internally consistent (files exist, version matches, catalog wired up, keywords resolve). Section (e) goes further and verifies that **the bytes pinned in `install-keywords.json` still match the bytes the dispatcher will actually execute** -- catching the case where an upstream installer (e.g. `get.scoop.sh`, `ohmyposh.dev/install.ps1`) silently published a new release and the local pin has gone stale, or where a maintainer rebumped a hash without re-fetching the body.

A new `--skip-network` flag turns off both sections (d) and (e) for offline / air-gapped use; sections (a)-(c) always run because they only touch the filesystem.

### What section (e) does, exactly

For every `remote.<key>` entry in `scripts/shared/install-keywords.json`:

1. **Skip if `sha256` is empty or absent** -- prints `[ OK ] sha256  remote:<key>  (unpinned -- skipped, no sha256 to verify)`. This keeps unpinned entries from blocking a green run; section (d) already warns about them via the dispatcher's yellow `(not pinned ...)` banner at install time.
2. **Resolve the source** -- `path` (repo-relative, v0.47.1+) wins over `url` (HTTP). `path` entries are read from disk via `Get-Content -LiteralPath -Raw`; `url` entries are fetched via `Invoke-RestMethod -UseBasicParsing -TimeoutSec 30` (full GET, **not** HEAD -- HEAD doesn't return a body, so it cannot be hashed).
3. **Hash identically to `run.ps1` dispatcher** -- `[System.Text.Encoding]::UTF8.GetBytes("$body")` -> `SHA256.Create().ComputeHash(...)` -> hex via `BitConverter.ToString -replace '-', ''` -> `ToLowerInvariant()`. This is byte-for-byte the same code path as the dispatcher's pre-exec verification at `run.ps1:~2400`, so a green doctor row is a hard guarantee that `install <key>` will pass the runtime hash check.
4. **Compare and report**:
   - **Match**: `[ OK ] sha256  remote:<key>  pinned=<hex>  source=<url-or-path>  (<KB> KB)`
   - **Mismatch**: `[FAIL] sha256  remote:<key>  MISMATCH  expected=<pinned-hex>  actual=<live-hex>  source=<url-or-path>  pin=remote.<key>.sha256 in <abs-path-to-install-keywords.json>`
   - **Fetch error** (HTTP 404, timeout, DNS fail, missing local file): `[FAIL] sha256  remote:<key>  GET failed for <url> (HTTP 404) -- <exception message>` -- includes HTTP status code when available.
   - **Empty body**: `[FAIL] sha256  remote:<key>  Empty body from <source>  (pin source: ...)`.

### What `--skip-network` does

When passed to `doctor --self-check`, the dispatcher skips both sections (d) (HEAD probes for keyword resolution) and (e) (full GETs for hash verification). Each prints a single green `[ OK ]` row noting the skip:

```
  -- (d) install-keywords.json: keyword resolution
    [ OK ] keywords  (skipped -- --skip-network)         Section (d) requires HEAD probes to remote URLs; skipped per flag.

  -- (e) remote SHA256 pins still match upstream body
    [ OK ] sha256    (skipped -- --skip-network)         Section (e) requires full GET of every remote URL; skipped per flag.
```

Aliases accepted: `--skip-network`, `-skip-network`, `skipnetwork`, `--skipnetwork`, `skip-network`, `--offline`, `-offline`, `offline`.

### Files updated

- `run.ps1`
  - **`Invoke-DoctorSelfCheck`** -- added `[switch]$SkipNetwork` parameter; updated function comment to document section (e); section (d) now wrapped in `if (-not $SkipNetwork) { ... }`; section (e) added immediately before the Summary block. Both skipped sections still emit one green row each so the summary tally remains meaningful.
  - **Section (e) implementation** -- ~70 new lines. Iterates `kwData.remote.*`, handles `path` AND `url` sources symmetrically, mirrors the dispatcher's exact UTF-8 + SHA256 byte sequence, never crashes on a single bad entry (per-entry try/catch), reports KB size on success.
  - **Bare-doctor command dispatcher** -- now also detects `--skip-network` (and aliases) in `$Install` args alongside `--self-check`, then forwards via `Invoke-DoctorSelfCheck -SkipNetwork:$isSkipNetwork`.
  - **`Show-RootHelp`** -- replaced the single `doctor --self-check` line with two: one for the full audit, one demonstrating `--skip-network`.
- `scripts/version.json` -- bumped `0.48.0` -> `0.48.1` (patch: new audit + new flag are additive; sections (a)-(d) behaviour unchanged when invoked without `--skip-network`).
- `changelog.md` -- this entry. Includes the version-note caveat that v0.47.1 was already taken, so the requested patch ships as v0.48.1.

### Verification on Windows

```powershell
.\run.ps1 doctor --self-check
# expect: 5 sections rendered (was 4); section (e) prints one row per remote.* entry.
# Today's expected output for the 4 pinned entries (v0.48.0 baseline):
#   [ OK ] sha256  remote:clean-code   pinned=c045f55132171ba170c60af0d3b1671059c571bfcc293a7674c2e6a2635b8c42  source=https://raw.githubusercontent.com/.../install.ps1  (~ KB)
#   [ OK ] sha256  remote:starship     pinned=1315b9372510257bad6c5b823c4101f71abd0f4a4d8004f5f15b35076e7a9959  source=local: <repo>\scripts\shared\remote-installers\starship.ps1  (5.73 KB)
#   [ OK ] sha256  remote:oh-my-posh   pinned=eae09e2ff6a7312b59507d26a5335550580fd8f8ea59334dc2a0a6026ae225ba  source=https://ohmyposh.dev/install.ps1  (~ KB)
#   [ OK ] sha256  remote:scoop        pinned=48f6ea398b3a3fa26fae0093d37bd85b13e7eaa5d1d4a3e208408768408e35ae  source=https://get.scoop.sh  (~ KB)
# Final summary tally now includes the 4 new rows.

.\run.ps1 doctor --self-check --skip-network
# expect: sections (a), (b), (c) run normally; sections (d) and (e) print one green
#         "(skipped -- --skip-network)" row each. Final summary: ~60-something OK
#         (a)+(b)+(c) rows + 2 skip rows, 0 FAIL, no HTTP traffic in netstat.

.\run.ps1 doctor --self-check --offline
# expect: identical to --skip-network (alias).
```

### Negative tests

1. **Stale pin test**: edit `remote.scoop.sha256` in `install-keywords.json` -- flip the leading `4` to `5`. Run `.\run.ps1 doctor --self-check` -> expect `[FAIL] sha256  remote:scoop  MISMATCH  expected=5...  actual=48f6...  source=https://get.scoop.sh  pin=remote.scoop.sha256 in <abs-path>`. Revert -> green again. CRUCIALLY, the same edit causes the dispatcher's runtime check (`run.ps1 install scoop`) to refuse with the EXACT same expected vs actual hashes, because both code paths share the identical UTF-8 + SHA256 sequence.
2. **Upstream drift simulation**: temporarily change `remote.scoop.url` from `https://get.scoop.sh` to `https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1` (a different but real installer body). Section (e) prints `[FAIL] sha256  remote:scoop  MISMATCH  expected=48f6...  actual=<new-hex>  source=<new-url>  pin=...`. This is what would happen organically if the upstream maintainers published a new release without us re-pinning.
3. **404 test**: change `remote.starship.path` from `scripts/shared/remote-installers/starship.ps1` to `scripts/shared/remote-installers/starship-MISSING.ps1`. Section (e) prints `[FAIL] sha256  remote:starship  Local wrapper not found: <abs>  (referenced by remote.starship.path in <kw-file>)`. CODE RED satisfied: failure includes both the path AND the reason.
4. **Network outage test**: disable WiFi, run `.\run.ps1 doctor --self-check`. Sections (d) and (e) cascade-fail with HTTP error rows. Then run `.\run.ps1 doctor --self-check --skip-network` -> all-green again. This is the supported workflow for offline CI / air-gapped runners.
5. **Unpinned-entry test**: temporarily set `remote.scoop.sha256 = ""`. Section (e) row becomes `[ OK ] sha256  remote:scoop  (unpinned -- skipped, no sha256 to verify)` instead of attempting verification. The green-on-skip behaviour matches the dispatcher's existing "yellow warning, but continue" stance for unpinned entries.

### Why this matters

Before v0.48.1, the only way to detect a stale pin was to actually run `install <key>` and watch for the dispatcher's `[ FAIL ] SHA256 mismatch` block. That meant the failure surfaced once a user tried to install -- typically on a fresh machine, mid-bootstrap, when failure is most disruptive. After v0.48.1, `doctor --self-check` is a single command that surfaces drift proactively, before any install attempt, with the exact pin location to edit. Run it on a schedule (cron / task scheduler) or in CI to detect upstream releases the moment they happen.


## [v0.48.0] -- 2026-04-21

### Added: OS Clean Phase 7 -- 5 more dev-tool cache categories (Bucket F, total = 59)

Continues the cache-only Bucket F expansion from v0.47.0 (Phase 6 added conda/poetry/pnpm/deno/rustup). Phase 7 focuses on **version managers** -- the tools that themselves manage other tool installs. All 5 helpers honour the same `_sweep.ps1` primitives, the same `--dry-run` / `--yes` / `--days N` flags, and the same `New-CleanResult` / `Set-CleanResultStatus` result contract. Total catalog now stands at **59 categories** (was 54).

### New categories

| Cat | Bucket | What it cleans | What stays SAFE |
|---|---|---|---|
| `pyenv-cache` | F | `~/.pyenv/pyenv-win/cache`, `~/.pyenv/pyenv-win/install_cache`, and any **per-version redirected pip caches** at `~/.pyenv/pyenv-win/versions/<v>/.cache/pip`. Invokes `pyenv rehash` AFTER sweep when CLI is on PATH. | Every installed Python interpreter (`versions/<v>/python.exe` + `Lib/site-packages/<pkg>`), pyenv shims (`pyenv-win/shims`), `.python-version` files in projects. The global pip cache (`%LOCALAPPDATA%\pip\Cache`) is **not** touched -- that is `pip-cache`'s job (no double-count). |
| `nvm-cache` | F | `$env:NVM_HOME\tmp` (download staging) + per-version redirected npm caches at `$NVM_HOME\v<X.Y.Z>\node_cache` and `$NVM_HOME\v<X.Y.Z>\.npm`. Invokes `nvm cache clear` first when CLI is on PATH. | Every installed Node version (`v<X.Y.Z>\node.exe` + `npm/`), the active version (`nvm\nodejs` symlink), `settings.txt`, project `.nvmrc` files. The global npm cache is `npm-cache`'s job. Targets **nvm-windows** (coreybutler) -- POSIX `nvm.sh` is not Windows-native. |
| `volta-cache` | F | `$env:VOLTA_HOME\cache` and `$env:VOLTA_HOME\tmp` (defaulting to `%LOCALAPPDATA%\Volta\{cache,tmp}`). | Every pinned tool under `VOLTA_HOME\tools\image` (Node/npm/yarn/pnpm runtimes), `VOLTA_HOME\bin` shims, `hooks.json`, project `package.json` `volta` pins. Volta has **no** native `volta cache clear` subcommand (as of v1.x), so the sweep is the only mechanism. |
| `asdf-cache` | F | `~/.asdf/downloads` (always swept -- pure tarball cache) **plus** age-gated `~/.asdf/installs/<plugin>/<version>` (only when LastWriteTime older than `--days N`, default 30, AND not the active version per `asdf current <plugin>`). Invokes `asdf reshim` AFTER sweep when CLI is on PATH. | `~/.asdf/shims` (regenerated by reshim), `~/.asdf/plugins`, `~/.tool-versions`, every project `.tool-versions`, the active version of every plugin, any install touched within the `--days` window. |
| `mise-cache` | F | `$env:MISE_CACHE_DIR` (defaulting to `%LOCALAPPDATA%\mise\cache`) + `$env:MISE_DATA_DIR\downloads` (defaulting to `%LOCALAPPDATA%\mise\downloads`). Invokes `mise cache clear` first when CLI is on PATH. | Every installed tool under `MISE_DATA_DIR\installs\<plugin>\<version>`, shims under `MISE_DATA_DIR\shims`, `.mise.toml` / `.tool-versions` in projects. Per-tool installs are **not** swept here -- use `mise prune` / `mise uninstall` for that (mise has its own age policy). |

### Files added

- `scripts/os/helpers/clean-categories/pyenv-cache.ps1`
- `scripts/os/helpers/clean-categories/nvm-cache.ps1`
- `scripts/os/helpers/clean-categories/volta-cache.ps1`
- `scripts/os/helpers/clean-categories/asdf-cache.ps1`
- `scripts/os/helpers/clean-categories/mise-cache.ps1`

### Files updated

- `scripts/os/helpers/clean.ps1` -- added 5 catalog rows (Bucket F, inserted directly after `rustup-toolchains` and before `npm-cache` so existing global-cache categories stay at the bottom of the bucket); bumped header to "v0.48.0 -- 59 categories".
- `scripts/os/run.ps1` -- added 5 rows to `$script:CleanCatalog` in the same position; updated help banner from "all 54" to "all 59".
- `scripts/version.json` -- bumped `0.47.1` -> `0.48.0` (minor: new categories = new public surface).
- `changelog.md` -- this entry.

### Conventions honoured (carried over from Phase 6)

- **Env-var precedence first**: every helper that respects an env var (`NVM_HOME`, `VOLTA_HOME`, `MISE_CACHE_DIR`, `MISE_DATA_DIR`) resolves it first and only falls back to the `%LOCALAPPDATA%` / `%USERPROFILE%` default when unset. The resolved path is logged in `Notes` so the user always knows which root was hit.
- **CLI-first sweep where possible**: `nvm cache clear`, `mise cache clear` invoked **before** the path sweep; `pyenv rehash`, `asdf reshim` invoked **after** (because they refresh metadata that the sweep just invalidated). `volta-cache` has no equivalent CLI -- pure path sweep. Failures from any CLI are logged at `warn` and never abort.
- **Age-gated installs are opt-in by default**: only `asdf-cache` walks per-version installs (mirroring `rustup-toolchains` from Phase 6). `pyenv-cache` and `nvm-cache` only sweep their **own** download tmp + per-version *redirected* caches -- they never touch the interpreters/runtimes themselves. `volta-cache` and `mise-cache` skip per-tool installs entirely (they have their own policy via `volta` / `mise prune`).
- **No double-counting**: `pyenv-cache` skips the global `%LOCALAPPDATA%\pip\Cache` (owned by `pip-cache`); `nvm-cache` skips the global `%APPDATA%\npm-cache` (owned by `npm-cache`); `mise-cache` skips installs (owned by `mise prune`). The doctor self-check sees 59 distinct catalog rows with 59 distinct helper files; no helper writes into another helper's domain.
- **CODE RED file-path discipline**: every helper's `Notes` lists the exact paths it considered, marks "not present" cases explicitly with the full path, and routes `Remove-Item` failures through `Get-LockReason` -> `LockedDetails` so the deduped `[ LOCKED FILES ]` block at the end of `os clean` shows the real path + reason.

### Verification on Windows

```powershell
.\run.ps1 os clean --bucket F --dry-run
# expect: 24 categories listed (was 19 in v0.47.0); the 5 new ones (pyenv-cache,
#         nvm-cache, volta-cache, asdf-cache, mise-cache) appear AFTER
#         rustup-toolchains and BEFORE npm-cache.

.\run.ps1 os clean-pyenv-cache --dry-run
# expect on a machine WITH pyenv-win:  Notes "Scanned N installed Python version(s) ..." +
#                                      sweep rows for pyenv-win\cache (and per-version
#                                      .cache\pip rows only when redirected).
# expect WITHOUT pyenv-win:            single Notes "pyenv-win not present (no <path>)".

.\run.ps1 os clean-nvm-cache --dry-run
# expect: "NVM_HOME resolved to: <path>" Notes line, then sweep row for nvm\tmp,
#         then per-version node_cache/.npm rows ONLY when those exist (rare -- most
#         users keep the global %APPDATA%\npm-cache, swept by npm-cache instead).

.\run.ps1 os clean-volta-cache --dry-run
# expect: "VOLTA_HOME resolved to: <path>" + at most 2 sweep rows (cache, tmp).
#         VOLTA_HOME\tools\image\ MUST stay untouched -- pinned Node/npm/yarn shims live there.

.\run.ps1 os clean-asdf-cache --days 7 --dry-run
# expect: sweep row for ~/.asdf/downloads (always),
#         then "Active versions resolved for N plugin(s)" Notes,
#         then KEEP: <plugin>/<v> (active|touched <date>) for in-window versions,
#         then STALE candidate: <plugin>/<v> (... N days ago) + sweep for old ones.
# Then '--days 0': everything except active goes for every plugin.
# Then '--days 99999': nothing goes; every version gets a KEEP row.

.\run.ps1 os clean-mise-cache --dry-run
# expect: "MISE_CACHE resolved to: <path>" + "MISE_DOWNLOADS resolved to: <path>",
#         then up to 2 sweep rows. installs\ + shims\ MUST stay untouched.

.\run.ps1 doctor --self-check
# expect: section (c) now prints 59 green rows; all helpers found at the exact
#         paths declared in clean.ps1 catalog; sections (a)+(b)+(d) still pass.
```

### Negative tests

1. With **no** version manager installed: every Phase 7 helper produces a single `[ <name> not present (no <path>) ]` Note line, status `dry-run` / `ok`, exit 0. No false positives, no scary warnings, no path-error spam.
2. `--days 0` on `asdf-cache`: removes EVERY non-active per-tool install for EVERY plugin (every directory is older than "0 days ago"). Active version per plugin still preserved -- if it isn't, that's a bug, file an issue.
3. `--days 99999` on `asdf-cache`: removes nothing under `installs/`, prints `KEEP: <plugin>/<version> (touched ... -- within 99999-day window)` for every version. The `downloads/` cache is still swept (it is **not** age-gated).
4. **Env-var override smoke test**: `$env:VOLTA_HOME = 'D:\custom-volta'; .\run.ps1 os clean-volta-cache --dry-run` -> Notes line confirms `VOLTA_HOME resolved to: D:\custom-volta`, sweep walks `D:\custom-volta\cache` + `D:\custom-volta\tmp`. Repeat for `MISE_CACHE_DIR`, `MISE_DATA_DIR`, `NVM_HOME`.
5. **Locked-file path-error test**: open a file under `~/.pyenv/pyenv-win/cache` in Notepad++, run `.\run.ps1 os clean-pyenv-cache` -> the file appears in the deduped `[ LOCKED FILES ]` block at the end of `os clean` with both its full path AND the lock reason from `Get-LockReason` (e.g. "in use by Notepad++ (PID 12345)"). CODE RED satisfied: every file-path failure includes both the path and the reason.


## [v0.47.1] -- 2026-04-21

### Fixed: replace broken `remote.starship` URL with a pinned local wrapper

The `https://starship.rs/install.ps1` endpoint has been 404 since v0.46.2 (Starship publishes only `install.sh`; on Windows users are directed to winget / scoop / cargo). v0.46.2 worked around this by leaving `remote.starship.sha256` empty and emitting an `_sha256_note`. v0.47.1 replaces the dead URL entirely with a curated local wrapper that is checked into this repo, SHA256-pinned, and routed through the same CODE RED integrity guard as every other remote installer.

### Files added

- `scripts/shared/remote-installers/starship.ps1` -- 5,865-byte wrapper. Resolution order: `winget install --id Starship.Starship -e` -> `scoop install starship` -> `cargo install starship --locked`. Each attempt logs the exact CLI it ran and the exact reason it skipped. Refreshes `$env:Path` from Machine + User scopes after install so the new `starship.exe` is discoverable in the same session. SHA256 (UTF-8 bytes of body, LF line endings): `1315b9372510257bad6c5b823c4101f71abd0f4a4d8004f5f15b35076e7a9959`.

### Files updated

- `scripts/shared/install-keywords.json`
  - `remote.starship` -- removed `url` + `_sha256_note`; added `path: "scripts/shared/remote-installers/starship.ps1"` + the pinned `sha256` above.
  - `_pinLastVerified` -- bumped `2026-04-20` -> `2026-04-21`.
  - Added `_pathComment` documenting the new `path` field semantics.
  - Updated `_remoteComment` to mention `path` as an alternative to `url` (v0.47.1+).
  - Aliases `install starship`, `install ss`, `install starship-prompt` now all resolve to the local wrapper. No keyword changes required.
- `run.ps1`
  - **Resolver** (`Resolve-InstallKeywords`): a `remote.<key>` entry may now supply `path` (repo-relative) **OR** `url` (HTTP). At least one is required; SHA256 pinning behaves identically for both. The resolved `LocalPath` is carried on the entry alongside `Url`.
  - **Dispatcher** (remote branch): when `LocalPath` is set, the body is read via `Get-Content -LiteralPath -Raw` instead of `Invoke-RestMethod`. The SHA256 verification, `Invoke-Expression`, and `[ FAIL ]` reporting paths are otherwise byte-for-byte unchanged. The status banner now prints `Source : local: <path>` and `Command: Get-Content '<path>' -Raw | iex` for path-based remotes (vs. `Source : <url>` / `Command: irm <url> | iex` for URL-based ones).
  - **Doctor `--self-check` section (d)**: `path`-based remotes are validated by `Test-Path -LiteralPath <abs>` instead of an HTTP `HEAD` probe. The detail column shows `local-OK` (green) or `local file MISSING: <abs>` (red). URL-based remotes still get the existing one-shot `HEAD` probe with HTTP status code reporting.
- `scripts/version.json` -- bumped `0.47.0` -> `0.47.1` (patch: bug fix only, no new surface).
- `changelog.md` -- this entry.

### Why this matters

Before v0.47.1, the only entry in `remote.*` without a SHA256 pin was `starship`, and the dispatcher would: (1) attempt `Invoke-RestMethod https://starship.rs/install.ps1`, (2) catch the HTTP 404, (3) print a generic `[ FAIL ]`. The user had no path forward without manually running winget. After v0.47.1: `install starship` deterministically runs the curated wrapper, the wrapper's hash is locked at the version committed in this repo, and any tampering with the wrapper file (intentional or otherwise) trips the same `SHA256 mismatch -- refusing to execute unverified body` guard that protects the three external installers.

### Tamper-test confidence

The local wrapper is byte-identical to the body the dispatcher will hash because it is read from disk with `-Raw` (no line-ending normalization on a file that is already LF-only). If you edit the wrapper without rebumping the pin, `install starship` immediately refuses to run with the exact expected vs. actual hex, the file path on disk, and the JSON pin source. To rebump after an intentional edit:

```powershell
$body = Get-Content -LiteralPath scripts/shared/remote-installers/starship.ps1 -Raw
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$hash  = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
($hash | ForEach-Object { $_.ToString("x2") }) -join ""
# Paste the lowercase hex into install-keywords.json -> remote.starship.sha256, then bump version.json patch.
```

### Verification on Windows

```powershell
.\run.ps1 install starship
# expect: ----- Remote: starship -----
#         Source : local: C:\...\scripts\shared\remote-installers\starship.ps1
#         Command: Get-Content '...' -Raw | iex
#         SHA256 : 1315b9372510257bad6c5b823c4101f71abd0f4a4d8004f5f15b35076e7a9959 (pinned -- verified before exec)
#         [  OK  ] SHA256 verified (1315b937...)
#         [ STEP ] winget install --id Starship.Starship -e --source winget ...
#         [  OK  ] Starship installed: C:\Users\...\AppData\Local\Microsoft\WinGet\Packages\...\starship.exe
#         [  OK  ] Remote installer 'starship' completed.

.\run.ps1 install ss            # alias -- identical output
.\run.ps1 install starship-prompt   # alias -- identical output

.\run.ps1 doctor --self-check
# expect: section (d) -- 'remote:starship local-OK' (green); 3 of 4 remote rows still HTTP-probed; 0 FAILs.
```

### Negative tests

1. **Tamper test**: append a single space to `scripts/shared/remote-installers/starship.ps1`, then `.\run.ps1 install starship` -> expect `[ FAIL ] SHA256 mismatch -- refusing to execute unverified body. Expected: 1315b937...  Actual: <new hash>  Source: local: <path>  Pin source: install-keywords.json -> remote.starship.sha256`. Revert the edit -> green again.
2. **Missing-file test**: rename the wrapper to `.bak`, run `.\run.ps1 install starship` -> expect `[ FAIL ] Remote installer 'starship' failed. ... Reason: Local wrapper not found on disk. Path: <abs>  (referenced by install-keywords.json -> remote.starship.path)`. Doctor section (d) prints `remote:starship -> local file MISSING: <abs>` for every keyword that resolves to it (`starship`, `ss`, `starship-prompt`).
3. **Already-installed test**: with `starship.exe` already on PATH, the wrapper short-circuits to `[ SKIP ] starship is already installed at: <path>` + version line, exit 0.


## [v0.47.0] -- 2026-04-20

### Added: OS Clean Phase 6 -- 5 more dev-tool cache categories (Bucket F, total = 54)

Continues the cache-only Bucket F expansion from v0.46.0 (Phase 5 added yarn/bun/cargo/go/maven). Phase 6 brings 5 more language-runtime caches under the same `_sweep.ps1` primitives, the same `--dry-run` / `--yes` / `--days N` flags, and the same `New-CleanResult` / `Set-CleanResultStatus` result contract. Total catalog now stands at **54 categories** (was 49).

### New categories

| Cat | Bucket | What it cleans | What stays SAFE |
|---|---|---|---|
| `conda-pkgs` | F | `~/anaconda3/pkgs`, `~/miniconda3/pkgs`, `~/.conda/pkgs/cache`. Invokes `conda clean --all --yes` first when CLI is on PATH. | All conda envs under `envs\`, base interpreter, `.condarc`, `environment.yml` files in projects. |
| `poetry-cache` | F | `%LOCALAPPDATA%\pypoetry\Cache`, `~/.cache/pypoetry`. Invokes `poetry cache clear --all PyPI --no-interaction` first. | Project `pyproject.toml` / `poetry.lock`, project-local `.venv`, the Poetry installer itself. |
| `pnpm-store` | F | `~/.pnpm-store`, `%LOCALAPPDATA%\pnpm\store`, `%LOCALAPPDATA%\pnpm-cache`. Invokes `pnpm store prune` first (removes only unreferenced content). | pnpm runtime under `LOCALAPPDATA\pnpm\` (outside `\store\`), pnpm-global shims, project lockfiles. |
| `deno-cache` | F | `$env:DENO_DIR` (resolved via `deno info --json` first, then `%LOCALAPPDATA%\deno` fallback) -- specifically the `deps\`, `gen\`, `npm\`, `registries\` subfolders. | The DENO_DIR root itself (so any user-installed shims stay), `deno.json` / `deno.lock`, `deno.exe` runtime, `DENO_INSTALL_ROOT` scripts. |
| `rustup-toolchains` | F | **Age-gated** -- `~/.rustup/toolchains/<name>` whose directory `LastWriteTime` is older than `--days N` (default 30) AND is NOT the active toolchain reported by `rustup show active-toolchain`. Each kept toolchain is logged as `KEEP: <name> (...)`. | The active default toolchain (always), any toolchain touched within the `--days` window, `~/.rustup/settings.toml`, `~/.cargo/bin` (handled by `cargo-registry`). |

### Files added

- `scripts/os/helpers/clean-categories/conda-pkgs.ps1`
- `scripts/os/helpers/clean-categories/poetry-cache.ps1`
- `scripts/os/helpers/clean-categories/pnpm-store.ps1`
- `scripts/os/helpers/clean-categories/deno-cache.ps1`
- `scripts/os/helpers/clean-categories/rustup-toolchains.ps1`

### Files updated

- `scripts/os/helpers/clean.ps1` -- added 5 catalog rows (Bucket F), bumped header to "v0.47.0 -- 54 categories".
- `scripts/os/run.ps1` -- added 5 rows to `$script:CleanCatalog`, updated help banner from "all 49" to "all 54".
- `scripts/version.json` -- bumped `0.46.2` -> `0.47.0` (minor: new categories = new surface).
- `changelog.md` -- this entry.

### Conventions honoured (carried over from Phase 5)

- **CLI-first sweep**: each helper that has a native cache-clean command (`conda clean`, `poetry cache clear`, `pnpm store prune`) invokes it before the path sweep, so the upstream tool gets to apply its own integrity rules. Failures are logged at `warn` and never abort the sweep.
- **DENO_DIR resolution precedence**: `$env:DENO_DIR` -> `deno info --json` -> `%LOCALAPPDATA%\deno`. Logged in `Notes` so the user always knows which path was hit.
- **`rustup-toolchains` is the first age-gated Bucket F category**: it follows the same `--days N` semantic as `obs-recordings` (Bucket G), but does NOT need consent because the deletion is a pure cache (rustup re-downloads on demand). Active toolchain is hard-pinned even when stale.
- **CODE RED file-path discipline**: every helper's `Notes` lists the exact paths it considered, marks "not present" cases explicitly, and routes Remove-Item failures through `Get-LockReason` -> `LockedDetails` so the deduped `[ LOCKED FILES ]` block at the end of `os clean` shows the real path + reason.

### Verification on Windows

```powershell
.\run.ps1 os clean --bucket F --dry-run
# expect: 19 categories listed (was 14 in v0.46.0); each prints a
#         would-items / would-free MB row; the 5 new ones at the bottom
#         of Bucket F before npm-cache / pip-cache / docker-dangling / wsl.

.\run.ps1 os clean-conda-pkgs --dry-run
# expect: Notes line "Conda not present ..." OR three sweep rows
#         (anaconda3\pkgs, miniconda3\pkgs, .conda\pkgs\cache).

.\run.ps1 os clean-poetry-cache --dry-run
# expect: at most 2 sweep rows (Cache + .cache\pypoetry); never touches pyproject.

.\run.ps1 os clean-pnpm-store --dry-run
# expect: 'pnpm store prune' note (if pnpm CLI present) + sweep rows for
#         .pnpm-store / LOCALAPPDATA\pnpm\store / LOCALAPPDATA\pnpm-cache.

.\run.ps1 os clean-deno-cache --dry-run
# expect: Notes "DENO_DIR resolved to: <path>" line, then sweep rows for
#         deps/gen/npm/registries subfolders only -- DENO_DIR root untouched.

.\run.ps1 os clean-rustup-toolchains --days 7 --dry-run
# expect: "Active toolchain (preserved): stable-x86_64-pc-windows-msvc"
#         then KEEP: ... rows for each in-window toolchain
#         then STALE candidate: ... rows + sweep for each old toolchain.

.\run.ps1 doctor --self-check
# expect: section (c) now prints 54 rows; all green; sections (a)+(b) still pass.
```

### Negative tests

1. With no relevant tool installed (e.g. no Conda):
   `.\run.ps1 os clean-conda-pkgs --dry-run` -> single "Conda not present (...)" note, status `dry-run`, exit 0.
2. `--days 0` on rustup-toolchains: removes EVERY non-active toolchain (every directory is older than "0 days ago"). Active default still preserved -- if it isn't, that's a bug, file an issue.
3. `--days 99999` on rustup-toolchains: removes nothing, prints `KEEP: <name> (touched ... -- within 99999-day window)` for every toolchain.

---

## [v0.46.2] -- 2026-04-20

### Pinned: SHA256 integrity hashes for the 4 existing remote installers

Followed the v0.45.2 CODE RED integrity guard end-to-end and committed pinned `sha256` values into `scripts/shared/install-keywords.json` for every working `remote.*` entry. From this release onward, `.\run.ps1 install <pinned-keyword>` will refuse to execute the streamed body unless its hash matches the value below.

### Pinned values (verified 2026-04-20, Malaysia time)

| Key | URL | SHA256 (lowercase hex) | Body size |
|---|---|---|---|
| `clean-code` | `https://raw.githubusercontent.com/alimtvnetwork/coding-guidelines-v15/main/install.ps1` | `c045f55132171ba170c60af0d3b1671059c571bfcc293a7674c2e6a2635b8c42` | 14 672 B |
| `oh-my-posh` | `https://ohmyposh.dev/install.ps1` | `eae09e2ff6a7312b59507d26a5335550580fd8f8ea59334dc2a0a6026ae225ba` | 2 194 B |
| `scoop` | `https://get.scoop.sh` (-> `https://raw.githubusercontent.com/scoopinstaller/install/master/install.ps1`) | `48f6ea398b3a3fa26fae0093d37bd85b13e7eaa5d1d4a3e208408768408e35ae` | 26 292 B |

All three bodies are LF-only ASCII / UTF-8, so the raw-byte hash and the `[Encoding]::UTF8.GetBytes((Invoke-WebRequest).Content)` hash that `run.ps1` computes at line ~2359 produce identical digests. No byte-order-mark or line-ending normalization to worry about.

### Starship -- intentionally left UNPINNED

`remote.starship` was added in v0.45.0 with `url = https://starship.rs/install.ps1`. **That URL currently returns HTTP 404** -- Starship ships only `install.sh` (POSIX bash) in their repo (`install/install.sh` at `github.com/starship/starship`), and the official Windows install path documented at starship.rs is `winget install starship` / `scoop install starship`, not a piped PowerShell installer.

Rather than:
- pin a hash for a 404 (every future run would `[ FAIL ]` with "URL returned an empty body"), or
- silently rewrite the URL to point at a third-party `.ps1` we can't audit,

we set `remote.starship.sha256 = ""` and added a `_sha256_note` field explaining the situation. An empty pin disables the integrity check for that one entry only (run.ps1 already prints a yellow `(not pinned -- add 'sha256' to remote.starship in install-keywords.json to enable integrity check)` warning), and `doctor --self-check` section (d) will continue to flag the URL as `HTTP 404` until upstream is fixed or the entry is rewritten.

**Action item for future maintenance**: either replace `remote.starship` with a `winget install starship` wrapper script in this repo, or remove the entry. Tracking via `_sha256_note`.

### Maintenance procedure (also embedded in `install-keywords.json` -> `_pinMaintenanceNote`)

Refresh the pins **whenever an upstream installer publishes a new release, or at least quarterly**:

1. Download the body fresh:
   ```bash
   curl -fsSL <remote.<key>.url> -o /tmp/<key>.ps1
   ```
2. Compute the hash **exactly the way `run.ps1` does** -- UTF-8 bytes of the decoded text body:
   ```powershell
   $body  = (Invoke-WebRequest <url>).Content
   $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
   ([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes) `
     | ForEach-Object { $_.ToString("x2") }) -join ""
   ```
3. Paste the lowercase hex into the matching `remote.<key>.sha256` field in `scripts/shared/install-keywords.json`.
4. Update `_pinLastVerified` to today's date (`yyyy-MM-dd`, Malaysia time).
5. Bump `scripts/version.json` (patch).
6. Run `.\run.ps1 doctor --self-check` to confirm pins resolve and URLs return 200.

> **CODE RED rule**: Never commit a hash you didn't verify in the same session. A stale or guessed hash makes the integrity guard refuse every future run of that installer with `SHA256 mismatch -- refusing to execute unverified body`, and the user has no way to recover except editing the JSON.

### Files touched

- `scripts/shared/install-keywords.json` -- added `sha256` (3 pinned + 1 empty), `_pinMaintenanceNote`, `_pinLastVerified`, and `_sha256_note` for starship.
- `scripts/version.json` -- bumped `0.46.1` -> `0.46.2`.
- `changelog.md` -- this entry.

No PowerShell logic was changed; this release is data-only. The integrity guard at `run.ps1:2355-2380` and the unpinned-warning path at `run.ps1:2342` were both shipped in v0.45.2 and need no modification.

### Verification on Windows

```powershell
.\run.ps1 install clean-code   # expect: [  OK  ] SHA256 verified (c045f55...)
.\run.ps1 install oh-my-posh   # expect: [  OK  ] SHA256 verified (eae09e2...)
.\run.ps1 install scoop        # expect: [  OK  ] SHA256 verified (48f6ea3...)
.\run.ps1 install starship     # expect: yellow "(not pinned ...)" warning, then HTTP 404
.\run.ps1 doctor --self-check  # expect: section (d) -- 3 of 4 remote URLs green, starship FAIL HTTP 404
```

A negative test (tamper detection): edit any character of the upstream body locally, point the URL at a file://, or temporarily change the pinned hex by one nibble -- run.ps1 must abort with `SHA256 mismatch -- refusing to execute unverified body. Expected: <pinned>  Actual: <computed>  URL: <url>  Pin source: install-keywords.json -> remote.<key>.sha256`.

---

## [v0.46.1] -- 2026-04-20

### Added: `.\run.ps1 doctor --self-check` -- deep self-audit

> **Versioning note:** user requested `v0.45.2`, but the project is already at `v0.46.0`. Per the monotonic-version rule we ship as **v0.46.1** to preserve forward-only history.

A new `--self-check` flag on the existing `doctor` command runs four deep audits and prints a green/red `[ OK ]` / `[FAIL]` row per item, grouped by section, with a final tally. The original quick `doctor` (10 sanity checks, < 2 sec) is unchanged -- the flag opts into the deeper audit.

### Surface

```powershell
.\run.ps1 doctor                # 10 quick sanity checks (unchanged)
.\run.ps1 doctor --self-check   # deep audit (4 sections below)
```

Aliases accepted: `--self-check`, `-self-check`, `--selfcheck`, `selfcheck`, `self-check`.

### Audits performed

| # | Section | What it checks | How |
|---|---|---|---|
| (a) | `changelog` | Every `` `path/to/file.ext` `` reference in `changelog.md` resolves to a real file on disk | Regex `` `([A-Za-z0-9_./\\-]+\.(ps1|json|md|psm1|psd1))` ``, skips URLs / `%VAR%` / `~`-rooted paths, normalizes `/` -> `\` and joins with `$RootDir`. Each path becomes one row. |
| (b) | `version` | `scripts/version.json` matches the latest `## [vX.Y.Z]` header in `changelog.md` | Parses both, single row showing `version.json=vA.B.C  changelog=vX.Y.Z` -- green only when identical. |
| (c) | `clean` | Every `@{ Cat = ...; Bucket = ...; Helper = ... }` entry in `scripts/os/helpers/clean.ps1` has a matching `.ps1` file in `scripts/os/helpers/clean-categories/` | Regex-parses the catalog (no `Import-Module` needed), `Test-Path` each helper. One row per category. With v0.46.0's 49 categories, this section prints 49 rows. |
| (d) | `keyword` | Every entry in `install-keywords.json` -> `keywords` resolves to either a real registry script ID, an `os:<action>`, a `profile:<name>`, or a `remote:<key>` whose URL responds HTTP 200 | Builds a `validIds` set from `registry.json`, HEAD-probes every `remote.*` URL **once** with a 10s timeout (cached), then walks every keyword. `os:` and `profile:` targets are accepted by shape (resolved at runtime). Detail column shows `id 5, remote:starship 200, os:clean-vscode-cache`. |

### CODE RED file-path discipline

Every failure row includes the **exact path** that's missing or unreachable, e.g.:

```
[FAIL] clean    yarn-cache                              [F] MISSING: D:\proj\scripts\os\helpers\clean-categories\yarn-cache.ps1
[FAIL] keyword  starship                                remote:starship -> HTTP 503 for https://starship.rs/install.ps1
[FAIL] version  monotonic match                         version.json=v0.46.0  changelog=v0.45.2
```

### Output shape

```
  Doctor -- Self-Check (deep audit)
  =================================

  -- (a) Claimed files in changelog.md exist on disk
    [ OK ] changelog scripts/os/helpers/clean-categories/yarn-cache.ps1
    [ OK ] changelog scripts/os/run.ps1
    ...

  -- (b) version.json matches latest changelog header
    [ OK ] version  monotonic match                         version.json=v0.46.1  changelog=v0.46.1

  -- (c) os clean-categories: catalog vs helper files
    [ OK ] clean    recycle                                 [A] recycle.ps1
    [ OK ] clean    yarn-cache                              [F] yarn-cache.ps1
    ... (49 rows total)

  -- (d) install-keywords.json: keyword resolution
    [ OK ] keyword  vscode                                  id 1
    [ OK ] keyword  starship                                remote:starship 200
    ...

  Self-Check Summary: 187/187 OK

  All self-check rows green. Project is internally consistent.
```

### Why HEAD probes are run only once

The cache (`$remoteCache`) is built before walking the keywords list -- so `starship`, `ss`, and `starship-prompt` (3 keywords pointing at `remote:starship`) only generate one HTTP request, not three. Total network cost: 4 HEAD requests today (one per `remote.*` entry).

### Help surface

`.\run.ps1 -Help` now lists both modes:

```
    .\run.ps1 doctor                Quick health check of project setup
    .\run.ps1 doctor --self-check   Deep audit: changelog files, version match, clean catalog, keyword resolution
```

### Files

- `run.ps1`: new `Invoke-DoctorSelfCheck` function (~180 LOC) inserted directly after `Invoke-DoctorCommand`. Doctor dispatch block parses `--self-check` from `$Install` and routes accordingly. `Show-RootHelp` gains one extra line.
- `scripts/version.json`: 0.46.0 -> 0.46.1
- `changelog.md`: this entry

## [v0.46.0] -- 2026-04-20

### Added: OS Clean Phase 5 -- 5 dev-tool cache categories (49 total)

All five are **non-destructive cache-only** under Bucket F. Settings, projects, source code, installed CLIs, lockfiles, and credentials are NEVER touched. Each accepts `--dry-run` / `--yes` / `--days N` and uses the shared `_sweep.ps1` primitives (`Invoke-PathSweep`, `New-CleanResult`, `Set-CleanResultStatus`) -- zero duplication.

| Category | Targets | What it KEEPS | CLI invoked first |
|---|---|---|---|
| `yarn-cache` | `%LOCALAPPDATA%\Yarn\Cache\*`, `~\.yarn\berry\cache`, `~\.cache\yarn` | Project `node_modules`, lockfiles, `.yarnrc`, `yarn global add` packages | `yarn cache clean --all` (best effort, when CLI on PATH and not dry-run) |
| `bun-cache` | `~\.bun\install\cache`, `%LOCALAPPDATA%\bun-cache` | `~\.bun\bin` (the bun runtime + globally-linked CLIs), `bun.lockb` | `bun pm cache rm` (best effort) |
| `cargo-registry` | `~\.cargo\registry\cache`, `~\.cargo\registry\src`, `~\.cargo\git\checkouts`, `~\.cargo\git\db` | `~\.cargo\bin`, `config.toml`, `credentials.toml`, **registry\index** (re-syncing it costs minutes -- intentionally left alone) | none -- Cargo has no equivalent built-in command |
| `go-buildcache` | `GOCACHE` (default `%LOCALAPPDATA%\go-build`), `GOMODCACHE\cache\download` (default `~\go\pkg\mod\cache\download`) | `~\go\bin`, project source, `go.mod` / `go.sum`. Resolves paths via `go env GOCACHE` / `go env GOMODCACHE` when the CLI is on PATH (more accurate than guessing). | `go clean -cache` + `go clean -modcache` (best effort) |
| `maven-repo` | `~\.m2\repository`, `~\.m2\wrapper\dists` | `settings.xml`, `settings-security.xml`, project `pom.xml` / `target\`, the wrapper script itself | none -- Maven offers no whole-cache flush |

### CLI-first design

Where the upstream tool ships its own cache-cleaning command (Yarn, Bun, Go), we **invoke the official command first**, then run the path sweep to mop up anything the CLI missed (orphaned dirs, broken layouts, partial downloads). This is gated behind `if (-not $DryRun)` and `Get-Command <tool>` so the helpers stay safe on machines where the tool isn't installed and silent on dry-runs.

Cargo and Maven get pure path sweeps because their official tooling has no equivalent ("cargo doesn't ship a cache flush, Maven's `dependency:purge-local-repository` is per-project not global").

### Catalog wiring

- `scripts/os/run.ps1`: 5 entries appended to `$script:CleanCatalog` under Bucket F. Help banner now reads "Run all **49** cleanup categories".
- `scripts/os/helpers/clean.ps1`: catalog grew from 44 to 49; orchestrator synopsis bumped to `v0.46.0 -- 49 categories`.

### Subcommand surface

```powershell
.\run.ps1 os clean-yarn-cache --dry-run
.\run.ps1 os clean-bun-cache --dry-run
.\run.ps1 os clean-cargo-registry --dry-run
.\run.ps1 os clean-go-buildcache --dry-run
.\run.ps1 os clean-maven-repo --dry-run
.\run.ps1 os clean --bucket F --dry-run        # all 14 dev-tool categories now (was 9)
```

### Files

- `scripts/os/helpers/clean-categories/yarn-cache.ps1` (new)
- `scripts/os/helpers/clean-categories/bun-cache.ps1` (new)
- `scripts/os/helpers/clean-categories/cargo-registry.ps1` (new)
- `scripts/os/helpers/clean-categories/go-buildcache.ps1` (new)
- `scripts/os/helpers/clean-categories/maven-repo.ps1` (new)
- `scripts/os/run.ps1`: catalog +5, banner 44 -> 49
- `scripts/os/helpers/clean.ps1`: catalog +5, synopsis 44 -> 49
- `scripts/version.json`: 0.45.2 -> 0.46.0

## [v0.45.2] -- 2026-04-20

> **Note on version label:** the user requested "Bump to v0.44.1", but v0.44.1 is in the past (we shipped v0.45.0 + v0.45.1 earlier today). Per project memory ("version must monotonically increase"), this ships as **v0.45.2**. The integrity-check work the user asked for is delivered exactly as specified.

### Added: Optional SHA256 integrity pinning for remote installers

The `remote:` dispatch convention (introduced v0.44.0, expanded v0.45.0) now supports an optional `sha256` field per entry. When present, `run.ps1` **hashes the downloaded body BEFORE `Invoke-Expression` runs** and refuses to execute on mismatch.

#### Schema (in `scripts/shared/install-keywords.json`)

```jsonc
"remote": {
  "clean-code": {
    "url":    "https://raw.githubusercontent.com/alimtvnetwork/coding-guidelines-v15/main/install.ps1",
    "label":  "Coding Guidelines v15 (clean-code)",
    "sha256": "abc123...def"   // optional, lowercase hex, no separators
  },
  "starship":  { "url": "https://starship.rs/install.ps1",   "label": "..." },   // unpinned (existing behavior)
  "scoop":     { "url": "https://get.scoop.sh", "label": "...", "sha256": "..." }
}
```

The `_remoteComment` in the JSON now documents this schema in-place so future contributors don't need to read the changelog.

#### Runtime behavior

For each `remote:<key>` dispatch:

1. **Banner** prints `SHA256 : <hash> (pinned -- verified before exec)` when a hash is configured, or `SHA256 : (not pinned -- add 'sha256' to remote.<key> in install-keywords.json to enable integrity check)` in DarkYellow when it's missing. This makes pin status visible at a glance -- no silent unverified executions.
2. **Body fetched** via `Invoke-RestMethod -UseBasicParsing` (unchanged).
3. **Hash computed** via `[System.Security.Cryptography.SHA256]` over `UTF8.GetBytes($script)`, formatted as lowercase hex (matching `Get-FileHash`/`shasum -a 256` conventions). The SHA256 instance is `Dispose()`d.
4. **On match**: prints `[  OK  ] SHA256 verified (<hash>)` then proceeds to `Invoke-Expression`.
5. **On mismatch**: refuses to exec, prints a `[ FAIL ]` line containing **expected hash + actual hash + URL + the exact JSON path of the pin** (`install-keywords.json -> remote.<key>.sha256`) so the user knows where to update or audit -- CODE RED file-path discipline.
6. **On hash computation error**: also refuses to exec, surfaces the .NET exception message with the same `[ FAIL ]` envelope.

#### What's NOT changed

- Entries WITHOUT `sha256` keep working exactly as before (warning banner only). This is **opt-in pinning** -- breaking every existing call would be hostile when upstream installers (Starship, scoop) update frequently and pinning them requires per-release maintenance from the user.
- Failure paths still increment `$failCount`, success still increments `$successCount`, `Refresh-EnvPath` still runs after each remote dispatch.
- `--dry-run` semantics: remote installers don't have a dry-run mode (they're third-party), so the hash check still triggers on real fetches as before.

#### Why bytes-from-string vs bytes-from-stream

`Invoke-RestMethod` decodes the response body to a string before we see it. We re-encode as UTF-8 bytes for hashing. This matches what would happen if the user piped the same body through `Out-File -Encoding UTF8 | Get-FileHash`. If upstream serves bytes that don't round-trip through UTF-8 (extremely rare for `.ps1` text), the user can switch to `Invoke-WebRequest`+raw bytes -- noted as a future option but out of scope here.

#### Files

- `run.ps1`: `Resolve-InstallKeywords` captures `Sha256` field into the entry; remote dispatch branch now reads it, prints pin status, computes hash, refuses on mismatch.
- `scripts/shared/install-keywords.json`: `_remoteComment` updated to document the new optional `sha256` field. **No existing entries pinned** -- left to the user to populate per their threat model.
- `scripts/version.json`: 0.45.1 -> 0.45.2.

## [v0.45.1] -- 2026-04-20

> **Note on version label:** the user requested "Bump to v0.44.1", but v0.44.1 is in the past (we shipped v0.45.0 earlier today). Per project memory ("Code changes must bump at least minor version" -- treated here as "version must monotonically increase"), the change ships as **v0.45.1** instead. The discoverability work the user asked for is delivered exactly as specified.

### Added: `Show-RootHelp` + `Show-KeywordTable` "Remote installers" sections

The 4 remote installers shipped in v0.44.0 (`clean-code`) and v0.45.0 (`starship`, `oh-my-posh`, `scoop`) now show up in both top-level help surfaces so users can discover them via `.\run.ps1 -Help` and `.\run.ps1 -List`.

#### `.\run.ps1 -Help` (Show-RootHelp)

A new **"Remote installers (irm <url> | iex)"** block was inserted after the "Combine keywords" section and before the keyword table. Format mirrors the Database / Combine sections (Magenta header + DarkGray rows) and explicitly states **"All aliases on each row are EQUIVALENT -- pick whichever you remember."** so the equivalence is unmissable.

```
    Remote installers (irm <url> | iex):
      All aliases on each row are EQUIVALENT -- pick whichever you remember.

    install clean-code                          Coding Guidelines v15 -- alimtvnetwork/coding-guidelines-v15
    install code-guide  (= cg, cc)              Same as 'install clean-code' (4 aliases total)
    install coding-guidelines                   Same as 'install clean-code' (long alias)
    install starship    (= ss)                  Starship cross-shell prompt -- starship.rs/install.ps1
    install oh-my-posh  (= omp, posh)           Oh My Posh prompt -- ohmyposh.dev/install.ps1
    install scoop       (= sc)                  Scoop CLI installer -- get.scoop.sh

    Combine remote + local: install vscode,cg  (VS Code first, then clean-code)
```

#### `.\run.ps1 -List` (Show-KeywordTable)

A new **"Remote installers (irm | iex)"** group was inserted after "DevOps & Containers". The Script ID column reads `remote` (instead of a numeric script id) so users instantly see these dispatch through the `remote:` convention and not a local script.

| Keyword | Description | Script ID |
|---|---|---|
| `clean-code, cg, cc` | Coding Guidelines v15 | `remote` |
| `code-guide` | Coding Guidelines v15 (alias) | `remote` |
| `coding-guidelines` | Coding Guidelines v15 (alias) | `remote` |
| `starship, ss` | Starship cross-shell prompt | `remote` |
| `starship-prompt` | Starship (alias) | `remote` |
| `oh-my-posh, omp, posh` | Oh My Posh prompt theme | `remote` |
| `ohmyposh` | Oh My Posh (alias) | `remote` |
| `scoop, sc` | Scoop CLI installer | `remote` |
| `scoop-installer` | Scoop (alias) | `remote` |

### Files

- `run.ps1`: `Show-RootHelp` -- new "Remote installers" section after the Combine block.
- `run.ps1`: `Show-KeywordTable` -- new "Remote installers (irm | iex)" group after DevOps.
- `scripts/version.json`: 0.45.0 -> 0.45.1.

## [v0.45.0] -- 2026-04-20

Consolidated batch: OS Clean **Phase 4** (4 new dev-cache categories), `logs` subcommand **filter siblings** (`--grep` / `--since` / `--errors` / `--case-sensitive`), and **3 new remote installers** (`starship`, `oh-my-posh`, `scoop`) wired through the `remote:` convention introduced in v0.44.0.

### Added: OS Clean Phase 4 -- 4 dev-tool cache categories (44 total)

All four are **non-destructive cache-only** -- settings, projects, source code, SDK packages, and credentials are NEVER touched. Each accepts `--dry-run` / `--yes` / `--days N` like every other category.

| Category | Targets | What it KEEPS |
|---|---|---|
| `vscode-extensions-cache` | `%USERPROFILE%\.vscode\extensions\<ext>\(cache\|.cache\|logs\|.logs\|tmp)`, `%APPDATA%\Code\(CachedExtensions\|CachedExtensionVSIXs\|logs\exthost*)` | Extension code, settings.json, keybindings, snippets, workspace state |
| `jetbrains-cache` | `%LOCALAPPDATA%\JetBrains\<Product><Ver>\(caches\|log\|tmp)` for IntelliJ/PyCharm/WebStorm/Rider/GoLand/CLion/PhpStorm/RubyMine/DataGrip + Toolbox cache | `config\` (settings, keymaps), project files. Indexes will rebuild on next IDE launch (intentional). |
| `android-studio-cache` | `%LOCALAPPDATA%\Google\AndroidStudio*\(caches\|log\|tmp)`, JetBrains-flavoured AndroidStudio dirs, `~\.android\cache`, `~\.android\avd\*\snapshots\` | SDK packages under `%LOCALAPPDATA%\Android\Sdk`, `config.ini`, `userdata-qemu.img` (only AVD snapshots get nuked, the AVDs themselves stay) |
| `gradle-cache` | `~\.gradle\(caches\|daemon\|.tmp\|native)`. Calls `gradle --stop` first when the CLI is on PATH and we're not in dry-run. | `gradle.properties`, `init.d\` scripts, the wrapper distribution itself, project-local `.gradle\` (left alone) |

#### Catalog wiring

- `scripts/os/run.ps1`: 4 entries added to `$script:CleanCatalog` under Bucket F. Help banner now reads "Run all **44** cleanup categories".
- `scripts/os/helpers/clean.ps1`: catalog grew from 40 to 44; orchestrator synopsis bumped to `v0.45.0 -- 44 categories`.
- Each helper sits next to the others in `scripts/os/helpers/clean-categories/`. The same `_sweep.ps1` primitives (`Invoke-PathSweep`, `New-CleanResult`, `Set-CleanResultStatus`) are reused -- zero duplication.
- `clean-jetbrains-cache` explicitly **skips** AndroidStudio* directories so the work isn't double-done with `clean-android-studio-cache`. Toolbox + Shared are also skipped (settings, not cache).

#### Subcommand surface

```powershell
.\run.ps1 os clean-vscode-extensions-cache --dry-run
.\run.ps1 os clean-jetbrains-cache --dry-run
.\run.ps1 os clean-android-studio-cache --dry-run
.\run.ps1 os clean-gradle-cache --dry-run
.\run.ps1 os clean --bucket F --dry-run        # all 9 dev-tool categories
```

### Added: `logs --grep` / `--since` / `--errors` / `--case-sensitive`

The `logs` subcommand introduced in v0.43.2 now supports four filter flags that **all compose**. `--tail` still defaults to 20.

#### Flags

- `--grep <pattern>` -- filters events whose `.message` matches the regex. Case-**insensitive** by default (typical user intent). The regex is compiled **once up front** with `New-Object System.Text.RegularExpressions.Regex` -- a malformed pattern fails fast with the exact `.NET` message instead of throwing per-event.
- `--case-sensitive` -- toggles `--grep` into case-sensitive mode (`RegexOptions.None`).
- `--since <duration>` -- only events newer than the cutoff. Accepted suffixes: `s`/`sec`/`second(s)`, `m`/`min`/`minute(s)`, `h`/`hr`/`hour(s)`, `d`/`day(s)`, `w`/`wk`/`week(s)`. Examples: `30m`, `1h`, `2d`, `1w`. Invalid duration fails fast with a `[ FAIL ]` listing accepted formats.
- `--errors` -- only `level=fail` / `level=warn` / `level=error`. **Also reads `.logs/*-error.json`** (which were skipped by default to avoid duplicates) so dedicated error logs are surfaced.

All filters apply BEFORE the global tail. The `(default tail 20)` label only appears when `--tail` was NOT passed; otherwise the header reads e.g. `logs --tail 50 --errors --grep 'locked' --since 1h`.

When zero events survive the filters, the empty-result banner echoes the active filter set so you can see what excluded everything (CODE RED visibility).

#### Implementation notes

- Three filters are independent flags but share one event collector loop -- no double-pass over `.logs/*.json`.
- Per-event identity stamping (v0.43.1) is honored: when `--errors` reads from `errors[]` and `warnings[]` arrays, each entry's own `projectVersion` / `invokedFrom` / `scriptName` win over the file header.
- Help block (`logs --help`) now lists every flag with one-line descriptions.

### Added: 3 new remote installers (`starship`, `oh-my-posh`, `scoop`)

Each gets a JSON entry under `remote.*` plus short and long aliases. All five (clean-code already wired in v0.44.0) use the same `irm <url> | iex` dispatch.

| Aliases | URL | Label |
|---|---|---|
| `starship`, `starship-prompt`, `ss` | `https://starship.rs/install.ps1` | Starship cross-shell prompt |
| `oh-my-posh`, `ohmyposh`, `omp`, `posh` | `https://ohmyposh.dev/install.ps1` | Oh My Posh prompt theming engine |
| `scoop`, `scoop-installer`, `sc` | `https://get.scoop.sh` | Scoop -- command-line installer for Windows |

```powershell
.\run.ps1 install starship
.\run.ps1 install omp
.\run.ps1 install scoop
.\run.ps1 install starship,omp,scoop      # chained -- runs in order
```

The dispatcher prints `Source: <url>` and `Command: irm <url> | iex` before executing so the literal one-liner is copy-pasteable for manual reruns. Failures (network down, 404, non-zero exit, empty body) are caught and reported with the URL + reason -- no stack traces.

### Skipped (with reason)

- **Unix `run.sh --version` mirror** -- not applicable: this project has no `run.sh`. `install.sh` already has its own `--version` mode (bootstrap version probe), and the local dispatcher is `run.ps1` only.
- **Windows-runtime verifications for v0.43.1 (per-event identity) and v0.43.2 (`logs --tail`)** -- these need a real Windows shell with populated `.logs/*.json`. The new `--errors` flag gives you a one-command audit: any v0.43.1+ event written under the new identity rule will show up via `.\run.ps1 logs --errors` with its own `projectVersion`/`invokedFrom` per line. See "Manual Windows verification" in the testing suggestions below.

## [v0.44.0] -- 2026-04-20

### Added (`install clean-code` remote installer)

New keyword family `install clean-code`, `install code-guide`, `install cg`, `install cc`, `install coding-guidelines` -- all four resolve to the **same** action: stream and execute the Coding Guidelines v15 installer from GitHub.

```powershell
# All four commands are equivalent:
.\run.ps1 install clean-code
.\run.ps1 install code-guide
.\run.ps1 install cg
.\run.ps1 install cc
```

Equivalent to running directly:

```powershell
irm https://raw.githubusercontent.com/alimtvnetwork/coding-guidelines-v15/main/install.ps1 | iex
```

#### Implementation

- New `remote` block in `scripts/shared/install-keywords.json` maps each remote key to a `{ url, label }` pair. Source of truth -- new remote installers are added by editing JSON, not code.
- `Resolve-InstallKeywords` (in `run.ps1`) now recognises `remote:<key>` string entries alongside the existing `os:<action>` / `profile:<name>` subcommand convention. Missing URLs fail loudly with the exact JSON path (CODE RED file-path discipline).
- New `Kind = "remote"` entries are sorted to run **after** script installs and subcommands -- so `install vscode,clean-code` installs VS Code first, then streams the remote guide.
- Dispatch uses `Invoke-RestMethod -UseBasicParsing` + `Invoke-Expression` (the canonical `irm | iex` pattern) wrapped in `try/catch`. Failures report URL + reason; empty bodies and non-zero `$LASTEXITCODE` are both treated as failures.
- Each remote dispatch prints `Source: <url>` and `Command: irm <url> | iex` before executing -- users can copy the literal one-liner for manual reruns.
- After execution `Refresh-EnvPath` is called so any tool the remote installer added to PATH is picked up by subsequent chained steps.

#### Notes

- Banner avoids em dashes / wide Unicode (terminal-banners memory rule).
- Aliases use the `is`/`has` boolean prefix convention throughout the new branch.

## [v0.43.2] -- 2026-04-20

### Added (`logs --tail` subcommand)

New root subcommand `.\run.ps1 logs --tail [N]` that prints the last N events (default 20) from every `.logs/*.json` file, grouped by `invokedFrom`, with `projectVersion` shown per group. Exits before any git pull or script dispatch -- safe in restricted shells.

#### Behaviour

- **Source**: scans `.logs/*.json` (skips `*-error.json` -- those events are duplicates already present in the main file).
- **Sort**: every event is parsed for `timestamp`, normalised to a sortable `[datetime]`, and the global tail is taken across ALL files (not per-file). This ensures the actual chronological tail is shown even when multiple scripts ran in parallel.
- **Grouping**: after tailing, events are grouped by `invokedFrom` and groups are ordered by their most-recent event timestamp (most recent group last).
- **Per-group header**: shows the invoking script path + the `projectVersion` of the latest event in the group. If the group spans multiple versions (e.g. logs from before and after a bump), the header reads `v<latest> (mixed: v0.43.0, v0.43.1)` so version drift is visible.
- **Per-event line**: `<timestamp 19-char>  [<level>]  <message>`, color-coded by level (ok=Green, fail=Red, warn=Yellow, skip=DarkGray, info=Cyan).
- **Backward compat**: events written before v0.43.1 (no per-event identity) fall back to the file-level `projectVersion` / `invokedFrom` / `scriptName` from the JSON header. Files older than v0.42.2 (no header identity either) fall back to `"unknown"` and the log filename.

#### Flags

- `--tail [N]` -- explicit tail length. `N` must parse as a positive int; otherwise default 20 is used.
- `--help` / `-h` / `help` -- prints usage and exits 0.
- Bare `.\run.ps1 logs` (no `--tail`) is treated as `--tail 20` and labelled `(default tail 20)`.

#### Implementation

- Added a `logs` short-circuit in `run.ps1` immediately after the `--version` short-circuit. Reads `Install` (the catch-all `ValueFromRemainingArguments`) for flag parsing.
- Wraps each `ConvertFrom-Json` in `try/catch`; corrupt or partial files emit a `[ WARN ]` line with the exact path + parse error reason (CODE RED file-path discipline) and processing continues.
- Missing `.logs/` directory or empty file set exits 0 with a friendly `[ INFO ]` message -- never throws.

### Bumped

- `scripts/version.json`: 0.43.1 -> 0.43.2.

> Note: requested as v0.43.0, but on-disk state is already v0.43.1 (per-event identity stamping landed in v0.43.1). Increment lands as **v0.43.2** (smallest forward step, semver forward-only).


## [v0.43.1] -- 2026-04-20

### Added (per-event identity stamping)

Every event written via `Write-Log` and `Write-FileError` in `scripts/shared/logging.ps1` now carries its own `projectVersion`, `invokedFrom`, and `scriptName` fields inside the `events[]` / `errors[]` / `warnings[]` arrays of `.logs/*.json`. This means a single grepped, split, or concatenated log line is still fully traceable to its origin script and version -- the file-level identity header (added in v0.42.2) is no longer the only source of truth.

#### Mechanism

- New module-scoped cache `$script:_LogIdentity` holds the resolved `{projectVersion, invokedFrom}` for the entire session.
- `Initialize-Logging` populates the cache once via `Get-LogIdentityFields` (wrapped in `try/catch`; falls back to `"unknown"` on resolution failure). The call stack is walked **only once per session** instead of once per event.
- `Write-Log` and `Write-FileError` now use `[ordered]@{}` event hashtables and append three identity fields after the existing payload:
  - `projectVersion` -- e.g. `"0.43.1"` (from `scripts/version.json`)
  - `invokedFrom` -- e.g. `"scripts/os/run.ps1"` (top-of-callstack `.ps1`, project-root-relative, forward slashes)
  - `scriptName` -- the sanitised log name from `Initialize-Logging` (e.g. `"os-clean"`), so events grouped by run are also self-labelled.
- `Save-LogFile` now reuses the cached identity instead of re-resolving it; the file-level header still includes the same fields in the same positions, so existing consumers see no breaking change.
- Both `Write-Log` and `Write-FileError` defensively re-resolve identity if the cache is empty (e.g. an event is logged before `Initialize-Logging` ran). Worst case, both fields read `"unknown"` -- never throws.

#### Backward compatibility

- File-level top fields (`projectVersion`, `invokedFrom`, `scriptName`, `status`, `startTime`, `endTime`, `duration`, `eventCount`, `errorCount`, `warnCount`, `events`, `errors`, `warnings`) keep their existing positions and meanings.
- Existing event fields (`timestamp`, `level`, `message`, plus `type`/`filePath`/`operation`/`reason`/`module`/`fallback` for file-errors) are unchanged. The three new identity fields are appended; consumers that read by name are unaffected.
- Old `.logs/*.json` files are not retroactively rewritten -- only events emitted from this run forward gain the per-event identity.

### Bumped

- `scripts/version.json`: 0.43.0 -> 0.43.1.

> Note: requested as v0.42.3, but on-disk state is already v0.43.0 (after the v0.43.0 audit + re-apply batch). Increment lands as **v0.43.1** (smallest forward step, semver forward-only).


## [v0.43.0] -- 2026-04-20

### Audit + consolidated re-apply

Audit of prior-session features showed the on-disk repo was at v0.42.2 but missing four claimed features. This release re-applies all of them in one batch and bumps to **v0.43.0**.

#### Audit result

| Feature | Claimed in | On disk before v0.43.0 | Action |
|---|---|---|---|
| Consent flags (`--consent-list`, `--consent-reset`) | v0.42.1 | Present | Kept |
| Self-identifying log files (`projectVersion`, `invokedFrom`) | v0.42.2 | Present | Kept |
| OS Clean Phase 3 (zoom, slack, teams, onedrive-cache) | v0.45.0 (claimed) | **Missing** | Added |
| Root `--version` / `-V` flag | v0.44.2 (claimed) | **Missing** | Added |
| Execution-policy bypass docs | v0.44.1 (claimed) | **Missing** | Added |
| Footer + no-warranty disclaimer | v0.43.0 (claimed) | **Missing** | Added |
| Versioned bootstrap installers | v0.43.0/v0.44.0 (claimed) | Present (`install.ps1`, `install.sh` already pin to `scripts-fixer-v8`) | Kept |

#### Added (Phase 3 OS Clean -- 4 new categories, all Bucket E, cache-only)

- **`scripts/os/helpers/clean-categories/zoom.ps1`** -- sweeps `%APPDATA%\Zoom\data\Cache`, `data\Logs`, `logs`, `Temp`, plus `%LOCALAPPDATA%\Zoom\Cache|GPUCache|Code Cache`. **NEVER** touches `data\zoomus.db` (account/contacts), local recordings, or saved chats.
- **`scripts/os/helpers/clean-categories/slack.ps1`** -- probes Squirrel install, MSIX install, and MS Store package (`91750D7E.Slack_8she8kybcnzg4`). Sweeps `Cache`, `Code Cache`, `GPUCache`, `logs`, `Service Worker\CacheStorage`. **NEVER** touches `Local Storage` (login token) or `IndexedDB` (message history).
- **`scripts/os/helpers/clean-categories/teams.ps1`** -- handles **both** Teams Classic (`%APPDATA%\Microsoft\Teams`, Electron) **and** New Teams (`%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\Default`, WebView2). Sweeps cache + GPU + service-worker cache + logs. **NEVER** touches auth or chat IndexedDB.
- **`scripts/os/helpers/clean-categories/onedrive-cache.ps1`** -- cleans `%LOCALAPPDATA%\Microsoft\OneDrive\logs`, `setup\logs`, `cache`, plus `StandaloneUpdater\*.tmp`. **Hard guard**: skips `$env:OneDrive` (synced files) entirely and notes the path in the report. Account binding under `settings\Personal\*.dat` is excluded.
- **Wiring**: catalog in `scripts/os/run.ps1` and `scripts/os/helpers/clean.ps1` updated. Aggregate count is now **40 categories** (was 36). Help banner and synopsis updated to reflect the new total.

#### Added (root `--version` / `-V` flag)

- **`run.ps1`**: short-circuit handler at the top of the dispatch block. Recognizes `--version`, `version`, and `-V` (capital, matched case-sensitively via `$MyInvocation.Line -cmatch '(^|\s)-V(\s|$)'` so it does not collide with the existing lowercase `-v` -> VS Code shortcut).
- Output prints: project version (from `scripts/version.json`), short + full git SHA, current branch, root path, readme URL, and the no-warranty disclaimer. Resolves git fields via `git rev-parse` + `git status --porcelain` inside `Push-Location $RootDir`; wrapped in `try/catch` so non-git checkouts still work (commit reads `no-git`). `(dirty)` tag appended when uncommitted changes are present.
- Exits **before** any git pull or script dispatch -- safe to call in restricted shells.

#### Added (PowerShell execution-policy bypass docs)

- **`readme.md`**: new top-level section between Quick Start and the script catalog. Documents three options the user can copy-paste:
  1. `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` (current session, no admin)
  2. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -d` (single invocation)
  3. `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force` (permanent, user scope, no admin)

#### Added (footer + disclaimer)

- **`readme.md`**: new "Disclaimer / no warranty" section. States the project is shared **AS IS, for fun, to save time on OS setup**, that scripts touch system-level state (registry, services, package managers, browser caches), and that the user is responsible for anything they change. Recommends `--dry-run` and `os clean -h` for inspection. Surfaces `.\run.ps1 --version` as the canonical way to identify the running build.
- The same disclaimer is printed by `.\run.ps1 --version` so the running version + warranty stance is visible in-terminal as well as in the repo.
- Version badge bumped from `v0.41.0` to `v0.43.0`. Quick Start now mentions `--version`.

### Bumped

- `scripts/version.json`: 0.42.2 -> 0.43.0.

### Notes

- Bootstrap installers (`install.ps1`, `install.sh`) already pin to `scripts-fixer-v8` and the version-check mode (`-Version` / `--version`) was already wired in a previous commit; no change needed for this release. Future per-release installers should continue to bump the embedded `$current = N` / `CURRENT=N` literal when the repo is forked into `scripts-fixer-v9`.
- Identity stamping in `.logs/*.json` (added in v0.42.2) is unchanged. New runs of the new categories also produce self-identifying logs.


## [v0.42.2] -- 2026-04-20

### Added (self-identifying log files)

- **`scripts/shared/logging.ps1` `Get-LogIdentityFields`**: new internal helper that resolves two identity fields once per `Save-LogFile` call:
  - **`projectVersion`** -- read from `scripts/version.json`. Falls back to `"unknown"` if the file is missing or unreadable, with a `warn`-level log entry containing the exact path and failure reason (CODE RED file-path discipline).
  - **`invokedFrom`** -- the top-of-callstack `.ps1` (the original script the user ran), resolved via `Get-PSCallStack` and expressed **relative to project root** with forward slashes (e.g. `scripts/os/run.ps1`, `run.ps1`, `scripts/45-install-docker/run.ps1`). Falls back to absolute path if the script lives outside the repo. Skips the logging file itself when walking the stack.
- **`Save-LogFile`** now stamps `projectVersion` and `invokedFrom` as the **first two top-level fields** of every payload it writes:
  - Main log: `.logs/<name>.json`
  - Error log: `.logs/<name>-error.json` (when errors / warnings / overall fail)
- Both payloads switched from `@{}` to `[ordered]@{}` so the identity fields appear at the top of the JSON, making logs scannable without parsing.
- Identity resolution is wrapped in `try/catch` -- failure to resolve never aborts log writing. Worst case the fields read `"unknown"`.

### Behavior

- Existing `.logs/*.json` files are not retroactively rewritten; only new runs gain the fields.
- `eventCount`, `errorCount`, `warnCount`, `events`, `errors`, `warnings` retain their existing positions and contents -- no breaking change for any consumer that reads those fields by name.

### Bumped

- `scripts/version.json`: 0.41.0 -> 0.42.2.

> Note: requested as v0.43.1, but the on-disk project state was actually still at v0.41.0 (prior session bumps had not persisted). Increment lands as **v0.42.2** (smallest forward step from the last published changelog entry v0.42.1, semver forward-only).

## [v0.42.1] -- 2026-04-20

### Added

- `os clean --consent-list` and `os clean --consent-reset` flags (Phase 2 follow-up).

## [v0.42.0] -- 2026-04-20

### Added

- OS Clean Phase 2: `os clean-wsl`, `os clean-office`, `os clean-whatsapp`, `os clean-telegram`. All four wired into aggregate.

## [v0.41.0] -- 2026-04-20

### Added

- OS Clean Expansion: 32 categories total in aggregate; `recycle`, `ms-search`, `obs-recordings`, `windows-update-old` gated by first-run typed-yes consent persisted in `.resolved/os-clean-consent.json`.
