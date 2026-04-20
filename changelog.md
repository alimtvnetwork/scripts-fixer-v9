# Changelog

All notable changes to this project are documented in this file.

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
