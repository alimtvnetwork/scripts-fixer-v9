# Changelog

All notable changes to this project are documented in this file.

## [v0.40.4] -- 2026-04-19

### Added (`gsa --remove`, `gsa --prune`, `gsa --list` audit trio)

- **`gsa --remove <path>`** -- new helper `scripts/git-tools/helpers/remove-safe.ps1`. Idempotent: snapshots `git config --global --get-all safe.directory`, checks if `<path>` is present (`[ SKIP ]` with clear reason if not), then runs `git config --global --unset-all safe.directory ^<regex-escaped-path>$` to nuke only that exact entry. Supports removing the wildcard too: `gsa --remove '*'`. Prints before/after counts and how many entries actually got removed (handles the rare case where the same path was added more than once).
- **`gsa --prune`** -- new helper `scripts/git-tools/helpers/prune-safe.ps1`. Iterates every per-repo entry from global gitconfig, runs `Test-Path -LiteralPath` on each, classifies as alive vs orphan, then unsets every orphan with the same exact-match regex pattern as `--remove`. The wildcard `'*'` is NEVER pruned (it doesn't represent a path -- removing it is an explicit `--remove '*'` action). Lists every orphan path before deleting (always shown, even on live runs) so you can Ctrl+C if something looks wrong.
- **`gsa --prune --dry-run`** -- preview mode. Reports the exact orphan list and counts, performs no `git config` writes. Recommended first run after a big repo cleanup.
- **`gsa --list`** -- finally landed (was speculatively summarized in v0.40.2 but never written). New helper `scripts/git-tools/helpers/list-safe.ps1`. Read-only audit: prints every entry sorted + deduped, splits wildcard vs per-repo, reports duplicates removed, and a one-line summary.

### Changed

- **`scripts/git-tools/run.ps1` rewritten** to a richer dispatcher. New action keywords: `list` / `--list` / `audit` / `safe-list`, `remove` / `--remove` / `unset` / `safe-remove`, `prune` / `--prune` / `safe-prune`. Inline-flag detection: `gsa --list`, `gsa --remove <path>`, `gsa --prune --dry-run` all route correctly without needing to type the action keyword separately. Existing `gsa` (wildcard) and `gsa --scan <path>` paths unchanged.
- **`scripts/git-tools/log-messages.json`** -- added 18 new strings covering list / remove / prune flows. All strings use `{placeholder}` substitution (the helpers do `-replace '\{path\}', $value`-style binding, no string interpolation in JSON).
- **Help text** (`Show-GitToolsHelp` in `run.ps1`) now lists all 4 actions (safe-all, list, remove, prune) with examples and a "WHEN TO USE" matrix that includes audit/cleanup workflows.

### Logging

- Each new action writes to its own log file: `.logs/git-safe-list-<timestamp>.log`, `.logs/git-safe-remove-<timestamp>.log`, `.logs/git-safe-prune-<timestamp>.log`. Status codes:
  - `--remove`: `ok` (entry removed), `skip` (path not present), `fail` (git error)
  - `--prune`: `ok` (0 orphans or all removed), `partial` (some unset failures), `fail` (git missing)
  - `--prune --dry-run`: always `ok` (no writes attempted)

### Safety

- **Wildcard guard on `--prune`**: the `'*'` entry is filtered out of the orphan candidates at classification time, so an accidental prune can never silently revoke wildcard trust.
- **Exact-match regex anchoring on both `--remove` and `--prune`**: the value pattern passed to `git config --unset-all` is `[regex]::Escape($path)` wrapped in `^...$`. This prevents a partial-path collision from nuking unrelated entries (e.g. removing `C:/dev` would NOT also remove `C:/dev/old-repo`).
- **Post-prune count drift check**: `--prune` snapshots before + after, computes expected delta, and prints `[ WARN ]` if git's actual delta doesn't match. Catches concurrent edits to gitconfig.

### Metadata

- `scripts/version.json` -- bumped to `0.40.4`.
- `readme.md` -- Changelog badge `v0.40.3 -> v0.40.4`.

## [v0.40.3] -- 2026-04-19

### Added (registry summary auto-regen wired into release pipeline)

- **`bump-version.ps1` now regenerates `spec/script-registry-summary.md` automatically** after writing the new version. Runs `node scripts/_internal/generate-registry-summary.cjs` if Node is on PATH. Idempotent: produces byte-identical output on unchanged inputs, so version-only bumps don't dirty the summary. Skips with a yellow `[ SKIP ]` (not a failure) when Node is missing -- bump still succeeds, but a warning tells you to regenerate manually before tagging.
- **CI drift detection** in `.github/workflows/release.yml`. New "Drift check" step (runs after version alignment, before ZIP build):
  1. Hashes the committed `spec/script-registry-summary.md`.
  2. Runs `node scripts/_internal/generate-registry-summary.cjs` (overwrites the file in the runner workspace only).
  3. Hashes the regenerated file and compares.
  4. If hashes differ, fails the release with a `::error` annotation pointing at the file, prints the full `git diff` of what changed, and refuses to publish the GitHub Release.
- **`actions/setup-node@v4` step** added to the workflow so `node` is available in the Windows runner for the drift check.

### Changed

- **`scripts/version.json`** -- bumped to `0.40.3`.
- **`readme.md`** -- Changelog badge `v0.40.1 -> v0.40.3`.

### Why

Until now, `spec/script-registry-summary.md` could silently drift from `scripts/registry.json` + `scripts/<folder>/config.json` (it had at v0.30 -- the file claimed 36 scripts when there were already 51). With this change:

- Local dev: every `bump-version.ps1` run refreshes the summary.
- Remote CI: every `git tag v*.*.*` push refuses to release if the committed summary is stale.

Drift is now structurally impossible without bypassing both gates.

### Notes

- This is a release-pipeline / tooling change only -- no runtime behavior change in any installer script.
- The drift check runs on the same Windows runner used to build the ZIP, so no extra job spin-up cost.
- `release.ps1` was deliberately not touched -- the regeneration belongs at version-bump time (where it can be committed), not at packaging time (where the ZIP is already in flight).

## [v0.40.1] -- 2026-04-19

### Added (`spec/script-registry-summary.md` auto-regen)

- **New maintenance script** `scripts/_internal/generate-registry-summary.cjs` -- regenerates `spec/script-registry-summary.md` from the live data in `scripts/registry.json` + each `scripts/<folder>/config.json` + `scripts/shared/install-keywords.json`. Zero deps, plain Node `fs`. Run with `node scripts/_internal/generate-registry-summary.cjs`.
- **`scripts/_internal/readme.md`** -- documents what the generator pulls from each source, when to re-run it, and why it's `.cjs` (the repo is ESM by default).

### Changed

- **`spec/script-registry-summary.md` regenerated** -- was stuck on the v0.30-era snapshot (36 scripts, 114 keywords, 17 mode entries). Current truth: **51 scripts, 329 keywords, 73 mode entries, 47 combo keywords, 25 subcommand keywords (10 groups: os:* and profile:*)**.
- The Overview table now lists every registered script ID 01-51 with accurate keyword + mode counts.
- The Detailed Script Reference now uses the `name` field from each `config.json` as the heading where present (e.g. "Script 16: phpMyAdmin", "Script 36: OBS Studio") and falls back to the folder name otherwise. `chocoPackage` / `chocoPackageName` is surfaced when set.
- New "Subcommand Keywords" section captures the `os:*` / `profile:*` keyword targets that route to dispatchers instead of numeric script IDs (previously hidden -- they were silently dropped from old summaries).
- Statistics block now distinguishes "Total keywords (numeric-target)" from "Subcommand keywords" so the two count categories don't conflict.
- Header note tells maintainers exactly how to regenerate.
- **Readme badge** Scripts count `46 -> 51`, Changelog `v0.32.0 -> v0.40.1`.

### Notes

- The generator is **idempotent** -- re-running it on unchanged inputs produces byte-identical output.
- Future schema additions (e.g. a `tags` field on `config.json`) only need a one-line patch to `scrapeScriptMeta()` to flow into the report.
- This is a maintenance-only release -- no runtime behavior change.

## [v0.40.0] -- 2026-04-19  *(2025-batch capstone release)*

### Added (`07-install-git` default gitconfig refresh -- Group E)

- **`safe.directory='*'` baked into the default gitconfig** -- new `gitConfig.safeDirectoryWildcard` block in `scripts/07-install-git/config.json`. Same effect as `.\run.ps1 gsa` (Group C), but applied automatically the first time you install git via `.\run.ps1 install git`. Idempotent: re-reads `git config --global --get-all safe.directory`, only adds `*` if not already present. New installs no longer hit "fatal: detected dubious ownership" warnings out of the box.
- **Git LFS filters re-asserted globally** -- new `gitConfig.lfsFilters` block. Sets `filter.lfs.clean`, `filter.lfs.smudge`, `filter.lfs.process`, `filter.lfs.required=true`. Normally `git lfs install` already does this, but the explicit re-assertion guarantees the filters survive even if the LFS install step was skipped, the config got wiped, or git-lfs was removed and reinstalled. Per-key idempotent.
- **GitHub + GitLab SSH URL rewrites** -- new `gitConfig.urlRewrites` block with two default rules: `url.git@github.com:.insteadOf = https://github.com/` and `url.git@gitlab.com:.insteadOf = https://gitlab.com/`. Cloning an HTTPS URL pasted from a browser silently uses your SSH key instead of prompting for a password / PAT. Each rule is independently idempotent. Disable the whole block via `gitConfig.urlRewrites.enabled = false`, or remove individual rules from the array.

### Changed (root help -- Group E polish)

- **Root help text** (`Show-RootHelp` in `run.ps1`) now lists `os clean`, `os temp-clean`, and the rest of the `os` subcommands as separate lines so users discover the new `temp-clean` independent code path immediately.
- All three new `gitConfig` blocks (`safeDirectoryWildcard`, `lfsFilters`, `urlRewrites`) are opt-out via `enabled: false`.

### Notes

- This release closed the **2025-batch** scope (specs in `spec/2025-batch/`): Ubuntu font, ConEmu, WhatsApp, OS clean, OneNote, fix-long-path, add-user, Lightshot, hibernate-off, PSReadLine, profiles, **plus `git-safe-all` + the gitconfig refresh**.
- The `gsa` subcommand (added in v0.39.7) is most useful for **existing machines** where you want to add per-repo safe.directory entries for repos that pre-date this gitconfig template. Fresh installs get the wildcard automatically.

## [v0.39.7] -- 2026-04-19

### Added (`git-tools` dispatcher + `gsa` subcommand -- Group C)

- **New top-level subcommand `git-tools`** (`scripts/git-tools/`) with its own dispatcher (`run.ps1`), helper folder, and `log-messages.json`. Routed from root `run.ps1` via the bare command `git-tools` (or alias `gittools`).
- **New action `safe-all`** (`scripts/git-tools/helpers/safe-all.ps1`) -- two-mode helper for fixing `fatal: detected dubious ownership in repository` warnings on Windows:
  - **Wildcard mode** (default, no args): adds `safe.directory='*'` to global gitconfig once. Idempotent -- detects existing wildcard via `git config --global --get-all safe.directory` and skips with `[ SKIP ]` if already present.
  - **Per-repo scan mode** (`--scan <path>`): walks `<path>` recursively to depth 4 (override with `--depth N`), finds every `.git` folder, and adds the parent repo path to global `safe.directory` entries individually. Idempotent -- snapshots existing entries once before scanning to avoid N+1 `git config` reads.
- **Root shortcuts**: `.\run.ps1 gsa`, `.\run.ps1 git-safe-all`, and `.\run.ps1 gittools` all wired into the bare-command dispatcher in root `run.ps1`. `gsa` routes directly to the `safe-all` action; `git-tools` routes to the dispatcher (so `git-tools help`, `git-tools safe-all`, etc. all work).
- **Flag parsing**: supports `--scan <path>`, `--scan=<path>`, `--depth <n>`, `--depth=<n>`, plus the single-dash variants. Help action: `git-tools help`, `git-tools --help`, `git-tools -h`, or bare `git-tools` with no args.
- **Pre-flight check**: bails with a clear error (`git command not found in PATH -- install git first (.\run.ps1 install git)`) if `git` isn't on `PATH`. CODE RED compliance: explicit error message + suggested fix.
- **Logging**: uses `Initialize-Logging -ScriptName "git-safe-all"` and `Save-LogFile -Status ok|fail` like every other script. Log lives under `.logs/`.
- **Spec doc** (`spec/git-tools/readme.md`) -- documents both modes, flags, when to use wildcard vs scan, verification steps, and notes the planned Group E follow-up (bake `safe.directory=*` into the default gitconfig template in `scripts/07-install-git/`).

### Implementation notes

- Repo paths in scan mode are normalized to forward slashes (`C:/Users/.../repo`) to match git's preferred form on Windows.
- Scan summary format: `Added {added} repos, {skipped} already present, scanned {total} .git folders in {seconds}s`.
- Scan mode uses `Get-ChildItem -Filter ".git" -Directory -Recurse -Depth N -Force -ErrorAction SilentlyContinue` -- silently skips permission-denied dirs instead of crashing.
- Existing-entry snapshot is hashtable-backed (`@{}`) for O(1) lookup per repo.

## [v0.39.6] -- 2026-04-19

### Added (`os clean` -- locked-file resilience + independent temp sweep + choco cache cleanup)

- **New subcommand `os temp-clean`** (`scripts/os/helpers/temp-clean.ps1`) -- standalone temp-only sweep, faster alternative to full `os clean` when you only want temp dirs gone (no event logs, no Windows Update cache, no PSReadLine wipe). Targets:
  - `$env:TEMP` (current user)
  - `C:\Windows\Temp` (system)
  - `$env:LOCALAPPDATA\Temp` (skipped if same path as `$env:TEMP` to avoid double-sweep)
  - `C:\Users\<each>\AppData\Local\Temp` -- enumerates all user profiles, skips `Public`/`Default`/`WDAGUtilityAccount` and the current user (already swept via `$env:TEMP`)
  - `$env:TEMP\chocolatey` (suppress with `-NoChoco`)
- **Locked-file resilience** -- every `Remove-Item` failure is caught (not crashed on), classified into a human-readable reason ("in use by another process", "access denied (locked or protected)", "sharing violation (open handle)", "vanished mid-sweep"), accumulated, and reported at the end in a dedicated **`[ LOCKED FILES ]`** section. CODE RED: every locked file logs the exact path + reason in real time AND in the final summary. De-duped by path. Configurable display cap (`lockedFilesMaxReport`, default 50) -- the rest go to the log file.
- **`os clean` and `os temp-clean` are INDEPENDENT code paths (Option B)** -- `clean` contains its own inline temp-sweep (steps 2-5: `%TEMP%`, `C:\Windows\Temp`, `%LOCALAPPDATA%\Temp`, per-user Temp), it does NOT call `temp-clean`. Each helper can be maintained / debugged / extended in isolation. Drift risk is accepted in exchange for zero coupling. The `-NoTemp` flag on `clean` lets you skip its temp sweep if you want to run `os temp-clean` separately first.
- **Chocolatey cache cleanup** as Step 6 (`scripts/os/helpers/choco-clean.ps1`) -- distinguishes **cache artifacts** (deleted) from the **live install** (left alone):
  - DELETES: `C:\ProgramData\chocolatey\lib-bad\*`, `\lib-bkp\*`, `\.chocolatey\*\.backup`, `\lib\*\*.nupkg` (cached package files), `%TEMP%\chocolatey\*`
  - LEAVES ALONE: `\bin`, `\lib\<pkg>\tools` (executables), `\config`, `\logs` -- so installed apps (VS Code, Git, etc.) keep working
  - Runs `choco-cleaner` (community extension) if present; falls back to manual sweep otherwise. Suppress with `-NoChoco`.
- **Expanded help** in `scripts/os/run.ps1` -- `.\run.ps1 os` and `.\run.ps1 os help` now print full per-action descriptions (what `clean` actually wipes step-by-step, the per-user Temp sweep, locked-file handling, the new `temp-clean` subcommand, all flags including `-NoTemp` / `-NoChoco`).
- **Summary table** redesigned: extra `locked` column per row, sub-step numbering (5.1, 5.2, ... for per-user Temp), `TOTAL` row with items + freed (MB / GB) + total locked count.

### Changed

- **`scripts/os/config.json`** -- new `tempClean.*`, `choco.*`, and `clean.{clearChocoCache, lockedFilesMaxReport}` keys. `includeWindowsTemp` is now `true` by default since `clean` always sweeps `C:\Windows\Temp` inline (the legacy `-IncludeWindowsTemp` flag is still accepted for back-compat).
- **`scripts/os/log-messages.json`** -- added `clean.{lockedHeader, lockedRow, lockedTruncated, chocoCleanerFound, chocoCleanerNotFound, chocoCleanerFailed, chocoCleanStart, chocoNotInstalled}`, full `tempClean.*` block, new `lock` status icon.
- **`scripts/os/run.ps1`** dispatcher routes `temp-clean` / `tempclean` / `temp` to the new helper.

### Licensing

- **`LICENSE`** -- replaced previous content with standard **MIT License** text. `Copyright (c) 2026 Alim Ul Karim`.
- **`readme.md`** -- new "License" section with MIT badge + summary near the bottom.
- **`package.json`** -- added `"license": "MIT"` field.


## [v0.39.5] -- 2026-04-19

### Changed (script 50 -- OneNote fallback URL refresh)

- **`scripts/50-install-onenote/config.json`** -- replaced the deprecated Win10 standalone OneNote fwlink (`LinkID=2024522`) with the **Microsoft 365 OneNote (Click-to-Run)** download endpoint (`c2rsetup.officeapps.live.com/c2r/downloadOneNote.aspx`). Microsoft is sunsetting the Win10 standalone OneNote variant, so the fallback now pulls the only OneNote desktop build still being shipped.
- Added `channel` + `notes` keys to `fallbackDownload` so the source/intent is self-documenting.
- **`scripts/50-install-onenote/log-messages.json`** -- updated `fallbackDownload` and `fallbackInstalling` log lines to explicitly mention "Microsoft 365 OneNote (Click-to-Run)" so logs make the choice obvious.
- **`scripts/50-install-onenote/helpers/onenote.ps1`** -- expanded the `Install-OneNoteFallback` doc-comment to explain the URL change + Win10 OneNote sunset rationale.

## [v0.39.4] -- 2026-04-19

### Added (2025 Batch -- Group D: `profile` dispatcher + 6 install profiles + new keyword convention)

- **New dispatcher `scripts/profile/run.ps1`** -- declarative multi-step install pipelines. Subcommands:
  - `profile list` -- print all profiles + step counts
  - `profile <name>` -- expand recursively, print step preview, execute, emit summary table with status + elapsed per step
  - `profile <name> --dry-run` -- show the expanded step list, do not execute (per-step `[DRYRUN]` lines)
  - `profile <name> -Yes` -- skip confirmation prompts inside steps (e.g. SSH keygen passphrase, default user.name)
  - `profile help` -- usage
- **6 profile recipes** in `scripts/profile/config.json` (declarative steps, no PowerShell needed to add a new one):
  1. **minimal** -- choco + git + 7zip + chrome (4 steps; for fresh-Windows bootstrap with nothing extra)
  2. **base** -- choco + git + VLC + 7zip + WinRAR + ubuntu font + XMind + Notepad++ (install+settings) + Chrome + ConEmu (install+settings) + `os hib-off` + PSReadLine latest (12 steps)
  3. **git-compact** -- git + GitHub Desktop + ed25519 SSH key (auto-detect / generate) + default `$HOME\GitHub` dir + opinionated git config (LFS filters, `safe.directory=*`, GitLab SSH rewrite) (5 steps)
  4. **advance** -- `base` + `git-compact` + WordWeb + Beyond Compare + OBS (install+settings) + WhatsApp + VS Code + VS Code settings sync (8 own steps + 17 from recursion = 25 total)
  5. **cpp-dx** -- vcredist-all + DirectX runtime + DirectX SDK (3 steps)
  6. **small-dev** -- `advance` + Go + Python + Node.js + pnpm (4 own + 25 from advance = 29 total)
- **Recursive `{ kind: "profile", name: "<other>" }` expansion** -- profiles can include other profiles. Cycle detection via a visited-set + chain-tracking; cyclic references abort with a CODE RED log line listing the full chain.
- **5 step kinds supported by the executor** (`scripts/profile/helpers/executor.ps1`):
  - `script` -- runs `scripts/<id>-*/run.ps1` via the registry, with optional mode env-var injection (NPP_MODE, OBS_MODE, CONEMU_MODE, etc.)
  - `choco` -- direct `choco install <pkg> -y --no-progress`; auto-skips with `[SKIP]` if choco is missing (so a `minimal` profile can install choco first then proceed)
  - `subcommand` -- dispatches via the root `run.ps1` (e.g. `os hib-off`, `git-tools gsa`)
  - `inline` -- calls a function in `scripts/profile/helpers/inline.ps1` (e.g. `Install-PSReadLineLatest`, `Setup-SshKey`, `Setup-GitHubDir`, `Apply-DefaultGitConfig`)
  - `profile` -- recursive expansion (handled by `scripts/profile/helpers/expand.ps1`)
- **Inline helpers** (`scripts/profile/helpers/inline.ps1`):
  - `Install-PSReadLineLatest` -- trusts PSGallery, `Install-Module PSReadLine -Force -SkipPublisherCheck -AcceptLicense -Scope CurrentUser`
  - `Setup-SshKey` -- skips if `~/.ssh/id_ed25519` already exists; otherwise reads `git config user.email` for the comment, runs `ssh-keygen -t ed25519`, prints the public key + copies to clipboard
  - `Setup-GitHubDir` -- ensures `$HOME\GitHub` exists, prints how to add it to GitHub Desktop manually (no public CLI exists for GHD)
  - `Apply-DefaultGitConfig` -- preserves existing `user.name` / `user.email` if set; otherwise prompts (defaults to "Alim Ul Karim"). Always sets LFS filters (clean / smudge / process / required), `safe.directory=*`, and the `https://gitlab.com/` -> `ssh://git@gitlab.com/` `insteadOf` rewrite.
- **Per-step status**: each step is wrapped in a `Stopwatch` + try/catch -- pass/fail/skip plus elapsed seconds. Final summary table shows the full result; exit code is 0 only when every step succeeded (otherwise `partial` + non-zero exit).
- **PATH refresh between steps** so newly installed tools are discoverable to subsequent steps without restarting the shell.

### Changed (root dispatcher + keyword resolver)

- **`run.ps1`** new bare command: `.\run.ps1 profile <name|list|help|<name> --dry-run>` forwards all remaining args to `scripts/profile/run.ps1`.
- **`Resolve-InstallKeywords` (in `run.ps1`)** now handles two value shapes in `install-keywords.json`:
  - **Numeric IDs** (the existing convention): `"vscode": [1]` -> entry `{ Kind: script, Id: 1 }`
  - **String subcommand entries** (NEW): `"profile-minimal": ["profile:minimal"]` and `"clean": ["os:clean"]` -> entry `{ Kind: subcommand, Dispatcher: "profile", Action: "minimal" }`. The `<dispatcher>:<action>` regex is the discriminator; everything before the colon is treated as a folder under `scripts/`.
- **Install execution loop** now branches on entry kind: subcommand entries are routed to `scripts/<dispatcher>/run.ps1` with `Action` split on whitespace (so `os:add-user alice MyP@ss123` works as a single keyword spec). Subcommand entries are sorted to the END so script-ID installs run first.
- **`scripts/shared/install-keywords.json`** -- added 11 new profile keywords (`profile-minimal`, `profile-base`, `profile-git`, `profile-git-compact`, `profile-advance`, `profile-advanced`, `profile-cpp-dx`, `profile-cppdx`, `profile-small-dev`, `profile-smalldev`) plus their `["profile:<name>"]` array values. The previously-staged Group B `os:` keywords now actually function as installable shortcuts (the resolver was extended to parse them).
- **CONEMU_MODE** added to the `modeEnvVars` map in the install execution loop (was missing from the v0.39.1 ConEmu wiring; profiles now honor `mode: install+settings` for ConEmu).

### Spec & docs

- Implemented per `spec/2025-batch/12-profiles.md` (which was updated last session to include the 6th `minimal` profile). All 6 declarative profiles + recursive expansion + cycle detection + 5 step kinds shipped.
- The `profile:` keyword convention agreed in the previous confirmation round is now wired end-to-end: keyword JSON -> resolver -> dispatcher -> executor.
- Inline functions are isolated in `scripts/profile/helpers/inline.ps1` so adding a new one only requires defining a function with `(-RootDir, -AutoYes, -Step)` signature.

## [v0.39.2] -- 2026-04-19

### Added (2025 Batch -- Group B: `os` subcommand dispatcher)

- **New dispatcher `scripts/os/run.ps1`** wires four Windows-housekeeping subcommands under a single namespace. Routes `os <action>` calls to per-action helpers, shows `os help` when called bare, and exits non-zero on unknown actions.
- **`os clean`** (`scripts/os/helpers/clean.ps1`) -- self-elevates if not Admin, prompts for confirmation (skip via `-Yes` / `-Force`), then runs 5 housekeeping steps with per-step counts + bytes-freed reporting:
  1. Wipe `C:\Windows\SoftwareDistribution\Download\*`
  2. Wipe `%TEMP%` (per-item, errors logged with exact path -- CODE RED rule)
  3. `C:\Windows\Temp` (skipped by default; opt-in via `-IncludeWindowsTemp`)
  4. Clear all event logs via `wevtutil el | wevtutil cl`
  5. Remove PSReadLine history file + `Clear-History` for current session
  Final summary table prints per-step status + total MB/GB freed; exit status `partial` if any step had errors.
- **`os hib-off` / `os hib-on`** (`scripts/os/helpers/hibernate.ps1`) -- self-elevates, captures `hiberfil.sys` size before/after, runs `powercfg.exe /hibernate off|on`, reports GB freed.
- **`os flp`** (alias `os fix-long-path`, `scripts/os/helpers/longpath.ps1`) -- self-elevates, sets `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled = 1` (DWORD), verifies via read-back, recommends reboot.
- **`os add-user <name> <pass> [pin] [email]`** (`scripts/os/helpers/add-user.ps1`) -- per locked decision: password is plain CLI arg (visible in shell history -- accepted risk). Validates args before elevation. Creates user via `New-LocalUser` with `PasswordNeverExpires` + `AccountNeverExpires`, adds to `Users` group. PIN cannot be set non-interactively on modern Windows -- writes a one-time hint file to `%TEMP%\<name>-pin-hint.txt` and logs a `[NOTICE]`. Email is stored as the user's `comment` attribute via `net user /comment` and a `[NOTICE]` explains how to link a real Microsoft account interactively. Console summary masks the password.
- **Shared admin/IO helpers** in `scripts/os/helpers/_common.ps1`: `Test-IsAdministrator`, `Assert-Admin` (re-launches the current PS host -- pwsh or powershell -- with `-Verb RunAs` and forwards original args), `Confirm-Action`, `Format-Bytes`, `Format-Gb`.

### Changed

- **Root dispatcher `run.ps1`** -- new bare command branch: `.\run.ps1 os <action> [args]` forwards everything after `os` to `scripts/os/run.ps1`. Consistent with the existing `models` / `path` / `update` / `export` / `status` / `doctor` dispatch pattern.
- **`scripts/shared/install-keywords.json`** -- added 15 new keywords mapping to the new `"os:<action>"` array convention (e.g. `clean -> ["os:clean"]`, `hib-off -> ["os:hib-off"]`, `flp -> ["os:flp"]`, `add-user -> ["os:add-user"]`). The `os:` prefix is the discriminator the install dispatcher will use (Group D wiring) to route to subcommands instead of script IDs.

### Spec & docs

- Implemented per `spec/2025-batch/04-os-clean.md`, `07-fix-long-path.md`, `08-add-user.md`, `10-hibernate-off.md`. CODE RED file-path error rule applied to every Remove-Item / Set-ItemProperty / file-write failure -- exact path + exception message in every log line.

## [v0.39.1] -- 2026-04-19

### Added (2025 Batch -- Group A: 5 new single-tool installers)

- **Script 47 -- `ubuntu-font`**: installs the Ubuntu font family system-wide via `choco install ubuntu.font -y`. Verifies by counting `Ubuntu*.ttf` in `%WINDIR%\Fonts`. Keywords: `ubuntu-font`, `ubuntu.font`, `ubuntufont`.
- **Script 48 -- `conemu` (+ settings)**: 3-mode pattern (install+settings | settings-only | install-only) plus `export`. Copies `settings/06 - conemu/ConEmu.xml` to `%APPDATA%\ConEmu\ConEmu.xml` with timestamped backup of any existing file. Keywords: `conemu`, `conemu+settings`, `conemu-settings`, `install-conemu`. Settings XML staged from user upload (`07. Alim Desktop workstation 11 - 10 dec 2024.xml`).
- **Script 49 -- `whatsapp`**: WhatsApp Desktop via `choco install whatsapp -y`. Microsoft Store path explicitly skipped per locked decision. Searches 4 candidate install locations for verification. Keywords: `whatsapp`, `wa`.
- **Script 50 -- `onenote` (+ tray + OneDrive)**: OneNote via choco with direct-download fallback (Microsoft fwlink). Post-install: kills `ONENOTEM.EXE` tray helper + removes its autostart, stops `OneDrive` process + disables all `OneDrive*` scheduled tasks + removes HKCU Run autostart. Keywords: `onenote`, `one-note`.
- **Script 51 -- `lightshot` (+ tweaks)**: Lightshot via choco + 4 registry tweaks at `HKCU:\Software\Skillbrains\Lightshot` (`ShowNotifications=0`, `ShowUploadDialog=0`, `JpegQuality=100`, `DefaultAction=0`). Each tweak is verified via read-back. Keywords: `lightshot`, `screenshot-tool`.

### Changed

- `scripts/registry.json` extended with IDs 47-51.
- `scripts/shared/install-keywords.json` extended with 14 new keywords + 4 new mode entries (ConEmu 3-mode mapping).

### Spec & docs

- All 5 scripts implemented per `spec/2025-batch/01-ubuntu-font.md`, `02-conemu.md`, `03-whatsapp.md`, `06-onenote.md`, `09-lightshot.md`.
- CODE RED file/path error rule applied throughout: every Test-Path / Copy-Item / Set-ItemProperty failure logs the exact path + reason via `Write-FileError`.

## [v0.39.0] -- 2026-04-19

### Fixed

- **Resolved unresolved Git merge conflict markers in `scripts/models/`** that broke `.\run models` with PowerShell parser errors (`The '<' operator is reserved for future use.` / `Missing file specification after redirection operator.`). Three files contained `<<<<<<< HEAD` / `=======` / `>>>>>>> lovable-sync-1776538523` blocks left over from a sync merge:

### Fixed

- **Resolved unresolved Git merge conflict markers in `scripts/models/`** that broke `.\run models` with PowerShell parser errors (`The '<' operator is reserved for future use.` / `Missing file specification after redirection operator.`). Three files contained `<<<<<<< HEAD` / `=======` / `>>>>>>> lovable-sync-1776538523` blocks left over from a sync merge:
  - `scripts/models/run.ps1` (3 conflict blocks: helper imports, mode-flag parsing, search-vs-uninstall mode bodies).
  - `scripts/models/log-messages.json` (3 conflict blocks: help.commands, help.examples, messages).
  - `spec/models/readme.md` (3 conflict blocks: CLI table, file layout, narrative section).
- Both feature branches kept: **Ollama Hub `search` mode** AND **`uninstall` / `rm` / `remove` mode** now coexist. CSV-mode reserved-word list expanded to `("list","search","uninstall","remove","rm")` so a slug with one of those prefixes won't be misclassified.

## [v0.38.1] -- 2026-04-19

### Added

- **`install.sh` mirrors the v0.38.0 PowerShell bootstrap.** Bash now uses the same CWD-aware target resolution decision tree:
  1. `basename "$PWD" == "scripts-fixer"` → target = `$PWD` itself (`Reason = cwd-is-target`).
  2. `$PWD/scripts-fixer` exists → target = that subfolder (`Reason = cwd-has-sibling`).
  3. `$PWD` is **safe** (writable, not `/`, `/usr`, `/etc`, `/var`, `/bin`, `/sbin`, `/boot`, `/sys`, `/proc`, `/System`, `/Library`, `/Applications` and not a write-probe failure) → target = `$PWD/scripts-fixer` (`Reason = cwd-safe`).
  4. Otherwise → fallback to `$HOME/scripts-fixer` (`Reason = fallback-home`).
- **`--dry-run` flag for `install.sh`** -- prints every `[LOCATE]` / `[CD]` / `[CLEAN]` / `[GIT]` / `[TEMP]` / `[COPY]` step the bootstrap would take, without cloning, removing, copying, or executing `run.ps1`. Skipped operations tagged `[DRYRUN] <action>  (skipped)`.
- New helpers in `install.sh`:
  - `test_cwd_is_safe <path>` — returns 0 only when path is writable, not protected (`/`, `/usr`, `/etc`, `/var`, `/bin`, `/sbin`, `/boot`, `/sys`, `/proc`, `/System`, `/Library`, `/Applications`), passes a `touch` write-probe.
  - `resolve_target_folder <cwd> <fallback>` — sets `TARGET`, `REASON`, `IS_INSIDE` globals.
- New `[LOCATE]` reason lines mirror the PowerShell ones:
  - `cwd-is-target` → "You are INSIDE a 'scripts-fixer' folder -- cloning back into the same path."
  - `cwd-has-sibling` → "A 'scripts-fixer' subfolder exists in CWD -- cloning into it."
  - `cwd-safe` → "CWD is writable -- cloning into <CWD>/scripts-fixer."
  - `fallback-home` → "CWD is a protected/system path -- falling back to \$HOME."

### Changed

- `install.sh` final `echo "    pwsh ./run.ps1 -d"` is now `pwsh ./run.ps1` (no `-d`), matching PowerShell behaviour so the dispatcher menu shows up rather than auto-launching script 12.
- The hardcoded `FOLDER="$HOME/scripts-fixer"` is gone; `FOLDER` is now computed dynamically from `resolve_target_folder`. `$HOME/scripts-fixer` is retained only as the safe fallback.

### Documentation

- Memory entry `mem://features/install-target-resolution` updated: bash mirror is no longer a follow-up; the 4-step decision tree is now implemented in both `install.ps1` and `install.sh`.
- Spec `spec/install-bootstrap/readme.md` § "Target Folder Resolution" expanded with a Bash sub-table listing the protected-path list and the `--dry-run` flag.

## [v0.38.0] -- 2026-04-19

### Fixed

- **`install.ps1` no longer ignores the user's current drive when picking the clone target.** Previously, running `irm .../install.ps1 | iex` from `D:\scripts-fixer` cloned into `C:\Users\Administrator\scripts-fixer`, dragging the install onto the system drive and away from where the user explicitly invoked it. The bootstrap now resolves the target **CWD-aware** with a 4-step decision tree:
  1. If CWD's leaf is `scripts-fixer` → target = CWD itself (clone back into the same path on the same drive).
  2. Else if CWD has a `scripts-fixer` subfolder → target = that subfolder.
  3. Else if CWD is **safe** (writable, not `$env:WINDIR` / `Program Files` / `ProgramData` / a drive root) → target = `<CWD>\scripts-fixer`.
  4. Else → fallback to `$env:USERPROFILE\scripts-fixer` (only triggers when CWD is a system/protected path).
- **No more auto-launch of "Install All Dev Tools".** The bootstrap previously ended with `& .\run.ps1 -d`, which dispatched straight into script 12 and stole the user's choice. It now ends with `& .\run.ps1` (no args) so the dispatcher's own menu/help is shown and the user picks what to do.

### Added

- New helpers in `install.ps1`:
  - `Test-CwdIsSafe -Path <p>` — returns `$true` only when path is writable, not protected (`%WINDIR%`, `Program Files`, `Program Files (x86)`, `ProgramData`), and not a drive root. Includes a write-probe.
  - `Resolve-TargetFolder -Cwd <c> -Fallback <f>` — returns `[pscustomobject]@{ Path; Reason; IsInside }` driving every downstream decision.
- New `[LOCATE]` reason lines so the user always sees **why** a target was chosen:
  - `cwd-is-target` → "You are INSIDE a 'scripts-fixer' folder -- cloning back into the same path."
  - `cwd-has-sibling` → "A 'scripts-fixer' subfolder exists in CWD -- cloning into it."
  - `cwd-safe` → "CWD is writable -- cloning into <CWD>\scripts-fixer."
  - `fallback-userprofile` → "CWD is a protected/system path -- falling back to USERPROFILE."

### Documentation

- New memory entry: `mem://features/install-target-resolution` documenting the decision tree, "unsafe" CWD list, and final-action change.
- New spec section: `spec/install-bootstrap/readme.md` § "Target Folder Resolution".
- `.lovable/plan.md` updated with v0.38.0 completion + bash mirror tracked as follow-up (still hardcoded to `$HOME/scripts-fixer`).
- Memory index `Core` rules updated to reflect new bootstrap behaviour.

## [v0.37.1] -- 2026-04-19

### Added

- **`-DryRun` flag for `install.ps1`** -- prints every `[LOCATE]` / `[CD]` / `[CLEAN]` / `[GIT]` / `[TEMP]` / `[COPY]` step the bootstrap would take, without cloning, removing, copying, or executing `run.ps1`. Banner shows magenta `[DRYRUN]` notice; skipped operations tagged `[DRYRUN] <action>  (skipped)`.
- `Invoke-GitClone` and `Remove-FolderSafe` gained an `-IsDryRun` switch so gating is centralized.

### Documentation

- `spec/install-bootstrap/readme.md` CLI control table gained a `-DryRun` row.

## [v0.37.0] -- 2026-04-19

### Fixed

- **`install.ps1` no longer prints red `NativeCommandError` noise on a successful clone.** Git writes `Cloning into '...'` to stderr; previous `2>&1` merge promoted those lines to PowerShell `RemoteException` records (rendered as fatal errors) even on exit 0. Bootstrap now captures stderr to a temp file with `2>$errFile`, runs `git clone --quiet`, and only surfaces stderr on `$LASTEXITCODE -ne 0`.
- **`install.sh` mirrors the same stderr fix** via `mktemp`, `--quiet`, and `sed`-indented stderr only on non-zero exit.

### Added

- **Self-relocation clone flow in `install.ps1` and `install.sh`** -- when re-running from inside `scripts-fixer` (or a parent containing it), the bootstrap `cd`s out, attempts safe removal (clears RO bits on Windows), and falls back to TEMP staging + recursive copy if removal fails. Every step logged with `[LOCATE]`/`[CD]`/`[CLEAN]`/`[GIT]`/`[TEMP]`/`[COPY]` tags including exact paths.
- **Pre-clone URL log** -- `[GIT] Cloning from : <repo URL>` and `[GIT] Cloning into : <target path>` so the user sees exactly which `-vN` repo is being pulled.
- New helpers: `Invoke-GitClone` + `Remove-FolderSafe` (PowerShell), `invoke_git_clone` + `remove_folder_safe` (bash).

### Documentation

- `spec/install-bootstrap/readme.md` § "Self-Relocation Clone Flow" with PS↔bash equivalence table and 6-row test matrix.
- New memory entry: `mem://features/install-self-relocation`.

## [v0.36.0] -- 2026-04-18

### Added

- **`-Version` / `--version` flag for install scripts** -- prints the current bootstrap version, probes for the latest available repo version, reports what would be installed, then exits without cloning. Useful for debugging which version a user would get before running the actual install.
  - **PowerShell**: `irm .../install.ps1 | iex -Version` or `... | iex -Version`
  - **Bash**: `curl .../install.sh | bash -s -- --version`
  - Output shows: `[VERSION] Bootstrap vN`, `[SCAN] Probing...`, `[FOUND] Newer version available: vX` or `[OK] You're on the latest`, and `[RESOLVED] Would redirect to ...` or `(current)`.
  - Added test case to the spec's testing checklist.

## [v0.35.0] -- 2026-04-18

### Changed

- **`install.ps1` and `install.sh` now always remove the existing `scripts-fixer` folder and re-clone fresh** instead of pulling. This guarantees every bootstrap run produces a clean, up-to-date checkout with no local drift, stale untracked files, or merge conflicts blocking the pull.
  - **Windows (`install.ps1`)**: detects existing `$env:USERPROFILE\scripts-fixer`, clears read-only attributes on all children (handles git pack files), then `Remove-Item -Recurse -Force`. On failure logs the exact path + reason and tells the user to close any open terminal/editor in that folder before retrying. Then runs `git clone` fresh and verifies `.git` exists before continuing.
  - **Unix/macOS (`install.sh`)**: detects existing `$HOME/scripts-fixer` (any entry, not just a git repo), runs `rm -rf`, on failure logs the exact path + reason and suggests `sudo rm -rf` as the recovery step. Then runs `git clone` fresh and verifies `.git` exists.
  - Error messages on both sides include the exact failing folder path per the project's CODE RED file-path-error rule.

## [v0.34.1] -- 2026-04-17

### Added

- **`-Force` flag for `models uninstall`** -- skips the interactive `yes` confirmation prompt so CI pipelines and cleanup scripts can run unattended. Example: `.\run.ps1 models uninstall -Force` or scoped: `.\run.ps1 models uninstall ollama -Force`.
  - When `-Force` is passed, the orchestrator logs `-Force flag set: skipping confirmation prompt.` (level `warn`) before proceeding to delete the selected targets.
  - Selection step is unchanged -- you still pass indices via the same `1,3 | 1-5 | all` syntax (or the upstream picker). `-Force` only short-circuits the final yes/no gate.
- `scripts/models/log-messages.json`: new `uninstallForceSkip` string + help row for `-Force` + new example.

## [v0.34.0] -- 2026-04-17

### Added

- **`.\run.ps1 models search <query>`** -- live search against `ollama.com/search?q=<query>` so users can discover and pull any model on Ollama Hub, not just the ~3 defaults baked into `scripts/42-install-ollama/config.json`.
  - New `scripts/models/helpers/ollama-search.ps1` contains `Invoke-OllamaHubSearch` (HTTP GET with friendly error handling, never throws), `ConvertFrom-OllamaHubHtml` (regex parser anchored on stable `x-test-*` markers the site exposes for tests -- handles absolute and relative hrefs), `Show-OllamaHubResults` (numbered table with sizes / capabilities / pull counts / truncated description), and `Read-OllamaHubSelection` (same `1,3 | 1-5 | all | q` syntax as the other pickers, plus a `:tag` suffix per pick e.g. `2:7b` to pull a specific size).
  - Selected slugs are joined CSV-style and dispatched to script 42 via the existing `OLLAMA_PULL_MODELS` env-var handoff added in v0.33.0 -- so search results flow through the exact same non-interactive pull path as `.\run.ps1 models <csv>`. No new code paths in script 42.
  - Help text, `log-messages.json`, and `spec/models/readme.md` updated to document the new subcommand and parser contract.
- Validated the parser against live results for `phi`, `llama` -- 15/20 and 25/25 valid `library/<slug>` resolutions respectively (the misses are user-namespace results without a library href, correctly skipped).
- **`.\run.ps1 models uninstall`** -- new orchestrator subcommand (aliases: `remove`, `rm`) that lists every locally installed model across BOTH backends, multi-select with the same `1,3 | 1-5 | all` syntax used by the install pickers, asks for explicit `yes` confirmation, then deletes via each backend's natural removal path.
  - llama.cpp side: scans `.installed/model-*.json`, cross-references `43-install-llama-cpp/models-catalog.json` to recover `fileName`/`displayName`/`fileSizeGB`, resolves the GGUF folder from `.resolved/43-install-llama-cpp.json` (falls back to `$env:DEV_DIR/llama-models`), shows whether the file is still on disk, then removes the GGUF + drops the `.installed/` tracking record.
  - Ollama side: shells out to `ollama list`, parses the column-padded output (`NAME / ID / SIZE / MODIFIED`), then deletes via `ollama rm <id>`. Gracefully handles missing daemon / `ollama` binary -- never throws.
  - Optional scoping: `.\run.ps1 models uninstall llama` or `.\run.ps1 models uninstall ollama` (also works via `-Backend`).
  - All logic in new `scripts/models/helpers/uninstall.ps1` (Get-InstalledLlamaCppModels, Get-InstalledOllamaModels, Show-UninstallList, Read-UninstallSelection, Confirm-Uninstall, Invoke-ModelUninstall). `run.ps1` stays a thin dispatcher.

### Changed

- `scripts/models/log-messages.json` adds `uninstallScanning / uninstallNothing / uninstallAborted / uninstallSkipped / uninstallPartial / uninstallComplete` strings; help section gains the three uninstall variants and two new examples.
- `spec/models/readme.md` updated with the new CLI rows, file layout entry, and an "Uninstall" section describing data sources and deletion semantics.

## [v0.33.0] -- 2026-04-17

### Added

- **Env-var handoff for non-interactive CSV installs** -- scripts 42 (Ollama) and 43 (llama.cpp) now honor the env vars set by `scripts/models/helpers/picker.ps1`, completing the orchestrator contract documented in `spec/models/readme.md`.
  - `Pull-OllamaModels` reads `OLLAMA_PULL_MODELS` (CSV of slugs), resolves each against `defaultModels` first then falls back to ad-hoc `ollama pull <slug>` for unknown ids (so users can request anything from ollama.com/library), and forces non-interactive mode -- no per-model yes/no prompt.
  - `Invoke-ModelInstaller` (llama.cpp) reads `LLAMA_CPP_INSTALL_IDS` (CSV), matches each id against the catalog (exact then `-like *id*`), skips the RAM/size/speed/capability filter prompts entirely, re-indexes the matched subset, and goes straight to download. Unmatched ids are logged and skipped; an empty match list aborts cleanly.
- Result: `.\run.ps1 models qwen2.5-coder-3b,llama3.2,deepseek-r1:8b` is now end-to-end non-interactive across both backends.

## [v0.32.0] -- 2026-04-17

### Added

- **`scripts/models/` orchestrator** -- new entry point that unifies both AI model backends (llama.cpp + Ollama) under a single command. Thin `run.ps1` (~120 lines) delegates to `helpers/picker.ps1` for backend selection, catalog loading, CSV id resolution (exact + partial match), and dispatch.
- **`run.ps1` dispatch** -- `models` / `model` / `-M` all open the orchestrator. Supports interactive (backend prompt → existing picker), direct CSV install (`.\run.ps1 models qwen2.5-coder-3b,llama3.2`), `-Backend` to skip the prompt, and `models list [llama|ollama]` to browse catalogs without installing.
- **`spec/models/readme.md`** -- documents the algorithm, file layout, dispatcher contract (env vars `LLAMA_CPP_INSTALL_IDS` / `OLLAMA_PULL_MODELS`), and how to add a third backend without touching `picker.ps1`.

## [v0.31.0] -- 2026-04-17

### Added

- **`spec/install-bootstrap/readme.md`** -- new spec documenting the bootstrap auto-discovery algorithm: how `install.ps1` / `install.sh` probe `<base>-vN` repos in parallel (current+1..current+20) and transparently redirect to the newest published generation. Covers algorithm, env-var controls (`SCRIPTS_FIXER_NO_UPGRADE`, `SCRIPTS_FIXER_PROBE_MAX`, `SCRIPTS_FIXER_REDIRECTED`), redirect-loop guard, edge cases, and reference implementations for both PowerShell (`Start-ThreadJob`) and bash (`xargs -P`).
- **Auto-discovery in `install.ps1`** -- parses current `-vN` repo, fires 20 parallel `HEAD` probes via `Start-ThreadJob` (sequential fallback for Windows PowerShell 5.1), picks highest responding version, re-invokes that repo's `install.ps1` and exits. Friendly `[SCAN]`/`[FOUND]`/`[REDIRECT]`/`[OK]` logging. Loop-safe via `SCRIPTS_FIXER_REDIRECTED=1`. Disable with `-NoUpgrade`.
- **Auto-discovery in `install.sh`** -- mirror of the PowerShell behaviour using `curl -fsI` + `xargs -P 20` for parallel HEAD probes. Disable with `--no-upgrade`.

## [v0.30.1] -- 2026-04-16

### Fixed

- **Dynamic dev-dir banner in `run.ps1`** -- help banner no longer hardcodes `E:\dev-tool`; now resolves the actual default at runtime using priority order (saved path → E: → D: → best fixed drive ≥ 10GB → system drive). Quiet detection prevents `Write-Log` noise in the help screen.

### Added

- **`spec/ci-cd/readme.md`** -- comprehensive CI/CD pipeline spec with root-cause analysis for 8 known release-pipeline issues (version drift, missing ZIP smoke tests, no automated tagging, etc.) and proposed remediations including a GitHub Actions workflow blueprint.
- **`.github/workflows/release.yml`** -- automated release workflow (Issue #7 from `spec/ci-cd`). Triggers on `v*.*.*` tag pushes (and `workflow_dispatch`), verifies tag alignment with `.gitmap/release/latest.json`, warns on `scripts/version.json` drift, builds the ZIP via `release.ps1`, smoke-tests it by extracting and running `run.ps1 -h`, computes SHA256, then uploads the ZIP + `.sha256` to the matching GitHub Release.

## [v0.30.0] -- 2026-04-16

### Added

- **Version detection in help display** -- `Show-ScriptHelp` now probes installed tool versions via `versionDetect` array in log-messages.json; installed versions show in green, missing tools in gray
- **versionDetect config** -- added to scripts 44 (rustc, cargo, rustup), 45 (docker, docker-compose), and 46 (kubectl, minikube, helm)
- Multi-word flag support in version probing (flags split via splatting)

## [v0.29.0] -- 2026-04-16

### Added

- **Orchestrator groups w/x** -- added DevOps (07,45-46) and Container Dev (45-46) group shortcuts to script 12 config
- **Scripts 44-46 in orchestrator** -- Rust, Docker, Kubernetes now appear in interactive install-all menu, sequence, and Everything group

## [v0.28.0] -- 2026-04-16

### Added

- **Script 44 -- Install Rust** -- installs Rust toolchain via rustup-init.exe, configures components (clippy, rustfmt, rust-analyzer), optional WASM target, cargo packages, adds `~/.cargo/bin` to PATH
- **Script 45 -- Install Docker** -- installs Docker Desktop via Chocolatey, checks WSL2 backend, verifies daemon, shows Docker Compose version, adds to PATH
- **Script 46 -- Install Kubernetes** -- installs kubectl, minikube, and Helm via Chocolatey with optional Lens IDE, adds tools to PATH
- **Install keywords** -- `rust`, `rustup`, `cargo`, `docker`, `docker-desktop`, `containers`, `kubernetes`, `kubectl`, `k8s`, `minikube`, `helm`
- **Combo shortcuts** -- `devops` (7+45+46), `container-dev` (45+46), `systems-dev` (9+44)

### Changed

- **Script count** -- 43 to 46 scripts
- **Registry updated** -- entries 44, 45, 46 added to `scripts/registry.json`

### Fixed

- **spec/43 model count** -- corrected 69-model references to 81 in spec/43-install-llama-cpp/readme.md

---

## [v0.26.0] -- 2026-04-16

### Added

- **81-model catalog** -- expanded from 69 to 81 models with 12 new small/fast entries: Gemma 3 (1B, 4B, 12B), Llama 3.2 (1B, 3B), SmolLM2 1.7B, Phi-4 Mini 3.8B, Phi-4 14B, Granite 3.1 (2B, 8B), Qwen3 1.7B, Functionary Small 8B
- **Download size filter** -- new `Read-SizeFilter` step in model picker with 5 tiers: Tiny (<1 GB), Small (<3 GB), Medium (<6 GB), Large (<12 GB), XLarge (12+ GB)
- **Speed filter** -- new `Read-SpeedFilter` step between Size and Capability filters with 4 tiers: Instant (<1 GB), Fast (<3 GB), Moderate (<8 GB), Slow (8+ GB); supports multi-select
- **Speed tier column** -- catalog display now shows computed speed tier (instant/fast/moderate/slow) based on file size
- **4-filter chain** -- interactive model picker now chains RAM → Size → Speed → Capability filters sequentially with re-indexing after each step

### Changed

- **Catalog version** -- bumped to 4.0.0
- **Model picker spec** -- updated `spec/model-picker/readme.md` with complete 4-filter chain documentation, new model table, speed tier spec, and updated dependencies
- **Script 43 spec** -- updated `spec/43-install-llama-cpp/readme.md` with RAM/Size/Capability filter steps and 81-model count

---


### Added

- **Script 42 -- Install Ollama** -- downloads Ollama from ollama.com, silent install, configures `OLLAMA_MODELS` env var, prompts for models directory, pulls starter models (Llama 3.2, Qwen 2.5 Coder, DeepSeek R1)
- **Script 43 -- Install llama.cpp** -- downloads all llama.cpp binary variants (CUDA 12.4 b7709, CUDA b6869, CUDA+runtime, AVX2 CPU, KoboldCPP CUDA, KoboldCPP CPU), extracts ZIPs, adds bin folders to user PATH, downloads GGUF models from Hugging Face
- **AI install keywords** -- `ollama`, `llama-cpp`, `llama`, `koboldcpp`, `gguf`, `ai-tools` (42+43), `local-ai` (42+43), `ai-full` (05+41+42+43)
- **Ollama version detection** -- `.\run.ps1 -Help` shows `[vX.Y.Z]` for Ollama via `ollama --version` CLI lookup
- **Dev directory entries** -- `llama-cpp\`, `llama-models\`, `ollama\` added to dev-tool structure

### Changed

- **Script count** -- 41 to 43 scripts in README
- **Registry updated** -- entries 42 and 43 added to `scripts/registry.json`

---

## [v0.22.1] -- 2026-04-12

### Fixed

- **Help display alignment** -- all keyword tables, combo shortcuts, and Available Scripts section now use consistent PadRight column widths (28/36/44) for perfect alignment
- **Missing scripts in help** -- added Flutter (38), .NET SDK (39), Java/OpenJDK (40), Windows Terminal (37), PowerShell Context Menu (31) to Available Scripts listing
- **Installed tool versions shown** -- Available Scripts section now detects and displays `[vX.Y.Z]` in green next to each tool that is already installed on the machine
- **`pylibs` keyword in help** -- added `pylibs` to Install by Keyword, Available Keywords, and Combo Shortcuts sections
- **`backend` combo updated** -- now includes .NET (39) and Java (40) alongside Python, Go, PHP, PostgreSQL
- **`full-stack` combo updated** -- now includes .NET (39) and Java (40)
- **Desktop Tools category** -- renamed from "Database Tools" to include non-DB desktop apps (OBS, WT, GitMap, Sticky Notes)
- **`data-dev` and `mobile-dev` combos** -- added to Combo Shortcuts in keyword table

## [v0.22.0] -- 2026-04-12

### Added

- **`pylibs` install keyword** -- `.\run.ps1 install pylibs` installs Python (script 05) + all pip libraries (script 41) in one command
- **Smart drive detection for Python install** -- when no `-Path` is provided, the installer automatically picks the drive with the most free space (E: > D: > best non-system drive > user prompt) instead of hardcoding `E:\dev-tool`

### Changed

- **config.json uses `installDirSubfolder`** -- replaced hardcoded `installDir` with a relative subfolder name (`Python313`); the full path is resolved dynamically at runtime from the dev directory

---

### Fixed

- **Script 05 parse error resolved** -- replaced invalid PowerShell quoting in the Python installer `TargetDir` argument so `install python` no longer fails with `Unexpected token '$('`

---

## [v0.21.0] -- 2026-04-12

### Fixed

- **Python direct install now persists to the correct env scope** -- all-users installs write `PYTHON_EXE`, `PYTHON_HOME`, `PYTHON_SCRIPTS`, and runtime PATH entries to Machine scope so new terminals can resolve Python immediately
- **Installer PATH bootstrap is now more reliable** -- script 05 enables `PrependPath=1`, refreshes the current session PATH, accepts installer reboot code `3010`, and no longer uses `Start-Process -NoNewWindow` for the GUI installer
- **Library bootstrapping now runs full Python setup** -- script 41 calls script 05 `all` so Python, pip site config, and PATH are ready before pip packages install
- **Uninstall now cleans User + Machine scope path/env entries** -- direct installs remove stale Python variables and PATH entries from both scopes

---

## [v0.20.0] -- 2026-04-12

### Fixed

- **Python now installs from the official python.org installer** -- script 05 downloads `python-3.12.9-amd64.exe`, installs to `C:\Python312`, and no longer depends on Chocolatey shims to resolve `python.exe`
- **Python runtime PATH + env are now persisted explicitly** -- `PYTHON_EXE`, `PYTHON_HOME`, and the Python/Scripts directories are written so new terminals and chained scripts can resolve Python immediately
- **Script 41 now bootstraps script 05 automatically** -- pip/library installs attempt a real Python install first instead of failing immediately when Python is missing
- **Resolver now probes persisted Python env vars before PATH scanning** -- `Resolve-PythonExe` checks saved `PYTHON_EXE` / `PYTHON_HOME` values before command aliases and wildcard fallbacks

---

## [v0.19.2] -- 2026-04-11

### Fixed

- **Python resolution now resets `$LASTEXITCODE` before probing** -- stale exit codes from choco install caused `Test-PythonExecutable` to reject valid Python executables
- **Added Chocolatey lib/tools fallback paths** -- `lib\python3\tools\python.exe` and variants are now probed when PATH-based resolution fails
- **Post-install retry loop (3 attempts, 2s delay)** -- choco shims may not be immediately available; resolver now retries with PATH refresh between attempts
- **Install summary now shows mode labels** -- duplicate script IDs display as e.g. `41[jupyter]` instead of raw `41`

---

## [v0.19.1] -- 2026-04-11

### Fixed

- **`Add-UniquePath` no longer rejects empty `List[string]`** -- removed `[Parameter(Mandatory)]` that caused PowerShell to reject a valid but empty list, added null guard instead

---

## [v0.19.0] -- 2026-04-11

### Fixed

- **Shared Python resolver now loads reliably under StrictMode**
  - Script 05 and script 41 explicitly dot-source `scripts/shared/tool-version.ps1` before calling `Resolve-PythonExe`
  - Added exact-path file error logging if the shared helper is missing
  - Replaced the StrictMode-fragile `$script:_ResolvedPythonInfo` cache with a global resolver cache helper so chained scripts can reuse the verified Python executable without unbound variable errors

---

## [v0.18.2] -- 2026-04-11

### Added

- **Python+group combo keywords** that chain script 05 (install Python) + script 41 (specific group)
  - `python+viz`, `python+web`, `python+scraping`, `python+db`, `python+cv`, `python+data`, `python+ml`
  - Each installs Python first if missing, then runs the specific library group
  - All help sections updated with "With Python" sub-header

---

## [v0.18.1] -- 2026-04-11

### Added

- **Per-group Python library keywords** for standalone install via root dispatcher
  - `viz-libs` -- visualization (matplotlib, seaborn, plotly)
  - `web-libs` -- web frameworks (django, flask, fastapi, uvicorn)
  - `scraping-libs` -- scraping (requests, beautifulsoup4)
  - `db-libs` -- database (sqlalchemy)
  - `cv-libs` -- computer vision (opencv-python)
  - `data-libs` -- data tools (pandas, polars)
  - `jupyter-libs` -- jupyter group (alias for jupyter+libs)
  - Each keyword maps to script 41 with the appropriate `group <name>` mode
  - Combinable: `install viz-libs,web-libs` runs script 41 twice with separate groups

---

## [v0.18.0] -- 2026-04-11

### Fixed

- **Real Python executable resolution for scripts 05 and 41**
  - Shared resolver now scans all command hits, skips `Microsoft\WindowsApps` aliases, and validates `python --version` before accepting a candidate
  - Script 05 now exports a verified `PYTHON_EXE`, syncs the current session, and stops reporting success when Chocolatey finishes but no working interpreter can be resolved
  - Script 41 now reuses the shared resolver, rechecks `ensurepip` against the verified executable, and works immediately after chained installs like `install pip+jupyter+libs`
  - `PYTHONUSERBASE` is now pushed into the current session even when it was already configured in user scope

## [v0.17.7] -- 2026-04-11

### Changed

- **Root dispatcher supports multi-mode same-script execution**
  - `install jupyter,ml-libs` now runs script 41 twice: once with `group jupyter`, once with `group ml`
  - Previously, duplicate script IDs were merged -- only the last mode survived
  - Entries with different modes (e.g. `group ml` vs `group jupyter`) are kept as separate runs
  - Standard install modes (`install+settings`, `install-only`, `settings-only`) still merge by priority
  - Enables `install pip,jupyter,ml-libs` to install Python (05), then Jupyter group (41), then ML group (41)

---

## [v0.17.6] -- 2026-04-11

### Fixed

- **Python/pip detection in chained installs** -- script 41 now finds pip after script 05 installs Python
  - Root dispatcher calls `Refresh-EnvPath` after each chained script so PATH updates propagate
  - `Resolve-PythonExe` tries `py`, `python3`, `python` in order, validates each with `--version`
  - Falls back to `ensurepip` if pip missing, then retries with `RequirePip` flag
  - All hardcoded `& python` calls replaced with resolved `$pyExe` variable

### Added

- **Mode env var wiring** for scripts 32, 38, 39, 40, 41 in root dispatcher
  - `PYTHON_LIBS_MODE` -- enables `jupyter+libs`, `data-science`, `ai-dev` keyword modes
  - `DBEAVER_MODE`, `FLUTTER_MODE`, `DOTNET_MODE`, `JAVA_MODE` now also wired
- **`jupyter` keyword** -- standalone keyword to install Jupyter group via script 41
- Script 41 `run.ps1` reads `PYTHON_LIBS_MODE` env var for mode override (e.g. `group jupyter`)

---

## [v0.17.5] -- 2026-04-11

### Changed

- **Python help section reorganized** with proper sub-groupings in all help views
  - Quick-start section: "Quick install", "By purpose", "By group", "Utilities" sub-headers
  - Added missing groups to help: `scraping`, `cv`, `db` alongside existing `ml`, `jupyter`, `viz`, `data`, `web`
  - Added `uninstall` commands to help utilities section
  - Keyword tables now use "Python & Libraries" and "Languages & Runtimes" group headers
  - Combo Shortcuts section uses "Python & Libraries" and "General" group headers
  - All four help locations (Show-RootHelp keywords, combos; Show-KeywordTable keywords, combos) consistent

---

## [v0.17.4] -- 2026-04-11

### Added

- **Data-science & AI combo keywords** in `install-keywords.json` and help output
  - `data-science` / `datascience` -- Python + data/viz group (05, 41)
  - `ai-dev` / `aidev` -- Python + ML group (05, 41)
  - `deep-learning` -- Python + ML group (05, 41)
  - `ml-full` -- Python + ML group (05, 41)

---

## [v0.17.3] -- 2026-04-11

### Added

- **Jupyter & pip combo keywords** in `install-keywords.json`
  - `jupyter+libs` -- installs Jupyter group only (jupyterlab, notebook, ipykernel, ipywidgets)
  - `pip+jupyter+libs` -- installs Python (05) + all pip libraries (41)
  - `python+jupyter` -- installs Python (05) + all pip libraries (41)

---

## [v0.17.2] -- 2026-04-11

### Added

- **Python Libraries in help** -- script 41 now fully visible in `.\run.ps1 -Help`
  - New "Python & pip libraries" section in Install by Keyword with all group commands
  - Keywords added to Available Keywords table: `python-libs`, `pip-libs`, `ml-libs`, `python+libs`, `ml-dev`
  - Script 41 listed in Available Scripts under Core Tools
  - Combo shortcut: `python+libs` / `ml-dev` installs Python + all libraries (05, 41)
  - Per-group commands shown: `group ml`, `group jupyter`, `group viz`, `group web`, `group data`
  - Custom install: `add <pkg>`, `list`, `installed` commands documented

---

## [v0.17.1] -- 2026-04-11

### Added

- **Doctor command** -- `.\run.ps1 doctor`
  - Quick health-check of project setup (runs in < 2 seconds)
  - 10 checks: scripts dir, version.json, registry.json, folder existence, .logs/, .installed/, Chocolatey, admin rights, shared helpers, install-keywords.json
  - Color-coded PASS/FAIL/WARN output with summary
- **Shared `Assert-ToolVersion` helper** (`scripts/shared/tool-version.ps1`)
  - Reusable function: run `--version`, guard empty, check .installed/ tracking
  - Returns structured result: `Exists`, `Version`, `HasVersion`, `IsTracked`, `Raw`
  - Optional `ParseScript` parameter for custom version parsing
  - Auto-loaded by logging.ps1 (available in all scripts)
- **Shared `Refresh-EnvPath` helper** -- refreshes `$env:Path` from registry

---

## [v0.17.0] -- 2026-04-11

### Added

- **VSCode settings export** (script 11) -- `.\run.ps1 -I 11 -- export`
  - Exports `settings.json`, `keybindings.json` from `%APPDATA%\Code\User\` back to the script folder
  - Exports installed extensions list via `code --list-extensions` into `extensions.json`
  - Auto-detects first available edition (Stable or Insiders)
  - Saves resolved export state with timestamp
  - New help entry and example added

---

## [v0.16.2] -- 2026-04-11

### Added

- **Install Python Libraries** (script 41) -- `.\run.ps1 -I 41` or `.\run.ps1 install python-libs`
  - Installs common Python/ML libraries via pip into PYTHONUSERBASE
  - 7 library groups: ml, data, viz, web, scraping, cv, db
  - `.\run.ps1 -I 41 -- all` installs all 17 default packages
  - `.\run.ps1 -I 41 -- group ml` installs ML group (numpy, scipy, scikit-learn, torch, tensorflow, keras)
  - `.\run.ps1 -I 41 -- add jupyterlab streamlit` installs custom packages
  - `.\run.ps1 -I 41 -- list` shows available groups
  - `.\run.ps1 -I 41 -- installed` shows pip package list
  - `.\run.ps1 -I 41 -- uninstall` removes all tracked libraries
  - Respects `PYTHONUSERBASE` -- uses `--user` flag when set
  - New keywords: `python-libs`, `pip-libs`, `ml-libs`, `python-packages`, `python+libs`, `ml-dev`

---

## [v0.16.1] -- 2026-04-11

### Added

- **Status command** -- `.\run.ps1 status`
  - Dashboard-style table showing all tracked tools with version, status, and install source
  - Reads from `.installed/` tracking files
  - Flags tools with recorded errors (`error`) or unverified versions (`unverified`)
  - Optional `choco outdated` check shows available upgrades
  - `.\run.ps1 status --no-choco` skips the outdated check for faster output
- **Defensive empty-version guards** across all install helpers
  - Wraps `--version` calls in `try/catch` with `$hasVersion` guard before `Test-AlreadyInstalled`
  - Prevents empty strings from being passed to tracking functions
  - Applied to: nodejs, pnpm, yarn, bun, git, git-lfs, gh CLI, golang, mingw, php, powershell, flutter

---

## [v0.16.0] -- 2026-04-11

### Added

- **Install .NET SDK** (script 39) -- `.\run.ps1 install dotnet`
  - Version selection: latest, .NET 6 LTS, .NET 8 LTS, .NET 9 STS
  - `.\run.ps1 -I 39 -- install 8` installs a specific version
  - Installs to dev directory (`<devDir>\dotnet`)
  - Adds dev dir to User PATH
  - Full uninstall support with PATH cleanup and tracking purge
- **Install Java (OpenJDK)** (script 40) -- `.\run.ps1 install java`
  - Version selection: latest, OpenJDK 17 LTS, OpenJDK 21 LTS
  - `.\run.ps1 -I 40 -- install 21` installs a specific version
  - Sets JAVA_HOME environment variable automatically
  - Installs to dev directory (`<devDir>\java`)
  - Full uninstall support with JAVA_HOME cleanup and tracking purge
- **Audit Check 12 -- Export Coverage** -- verifies settings-capable scripts (32, 33, 36, 37) have:
  - `Export-*` function in helpers/
  - `"export"` command handler in run.ps1
  - Export-related messages in log-messages.json
- **Root export command** -- `.\run.ps1 export`
  - Batch-export all app settings (DBeaver, NPP, OBS, Windows Terminal)
  - `.\run.ps1 export npp,obs` -- export specific apps only
  - Keyword support: dbeaver, npp, obs, wt
- **Install location logging** -- all new scripts log the target install directory at startup

### Keywords

- `dotnet`, `.net`, `dotnet-sdk`, `csharp`, `c#`, `dotnet-6`, `dotnet-8`, `dotnet-9`
- `java`, `openjdk`, `jdk`, `jre`, `jdk-17`, `jdk-21`

---

## [v0.15.4] -- 2026-04-11

### Fixed

- **PATH refresh after Chocolatey upgrades** -- all upgrade blocks now refresh `$env:Path` from Machine + User immediately after `Upgrade-ChocoPackage`
  - Prevents stale PATH causing `--version` to return empty after an upgrade
  - Applied to: VSCode (01), Node.js (03), Golang (06), Git + LFS + GH CLI (07), GitHub Desktop (08), MinGW/C++ (09), Flutter (38)
- **Empty-version guard in upgrade blocks** -- version capture wrapped in `try/catch` with fallback to `"(version pending)"` when unresolvable
- **Python installer duplicate save** -- removed second `Save-InstalledRecord` call that wrote empty `$newVersion`, causing the `"Warning: empty version"` warning

---

## [v0.15.3] -- 2026-04-11

### Fixed

- **Python installer** -- `pip` not recognized after install due to stale PATH
  - Added Machine + User PATH refresh before version verification
  - `pip --version` and `python --version` now use `try/catch` with `"unknown"` fallback
- **Python empty-version guard** -- `--version` returning empty no longer crashes the installer

---

## [v0.15.2] -- 2026-04-11

### Fixed

- **Python install empty-version crash** (script 05) -- `Test-AlreadyInstalled` now only called when `python --version` returns a non-empty string, preventing `Cannot bind argument to parameter 'CurrentVersion'` error

---

## [v0.15.1] -- 2026-04-11

### Added

- **Notepad++ settings export** (script 33) -- `.\run.ps1 -I 33 -- export`
  - Exports config files (.xml, .json, .ini) from `%APPDATA%\Notepad++\`
  - Exports subdirectories (themes, userDefineLangs) recursively
  - Skips runtime folders (backup, session, plugins) and files > 512 KB
  - Saves to `settings/01 - notepad++/`

### Fixed

- **Typo in `Uninstall-NotepadPP`** -- `$$NppConfig` corrected to `$NppConfig`

---

## [v0.15.0] -- 2026-04-11

### Added

- **Enhanced choco update command** -- extracted to `scripts/shared/choco-update.ps1`
  - `.\run.ps1 update` now shows only outdated packages (via `choco outdated`) instead of listing all
  - `.\run.ps1 update nodejs,git` -- selective package updates
  - `.\run.ps1 update --check` -- check-only mode (list outdated, no upgrade)
  - `.\run.ps1 update -y` -- auto-confirm mode (skip [Y/n] prompt)
  - `.\run.ps1 update --exclude=pkg1,pkg2` -- upgrade all except listed packages
  - Root `-Y` switch also honored for auto-confirm

---

## [v0.14.1] -- 2026-04-11

### Added

- **OBS settings export** (script 36) -- `.\run.ps1 -I 36 -- export`
  - Exports scene collections (.json) and profile folders from `%APPDATA%\obs-studio\basic\`
  - Saves to `settings/02 - obs-settings/`
  - Skips files > 512 KB
- **Windows Terminal settings export** (script 37) -- `.\run.ps1 -I 37 -- export`
  - Exports `settings.json` and extra config files from LocalState
  - Saves to `settings/03 - windows-terminal/`
  - Excludes `state.json` (runtime state)

### Fixed

- **Typo in `Uninstall-OBS`** -- `$$ObsConfig` corrected to `$ObsConfig`
- **Typo in `Uninstall-WindowsTerminal`** -- `$$WtConfig` corrected to `$WtConfig`

---

## [v0.14.0] -- 2026-04-11

### Added

- **DBeaver settings export** (script 32) -- `.\run.ps1 -I 32 -- export`
  - Copies settings FROM `%APPDATA%\DBeaverData\workspace6\General\.dbeaver\` TO `settings/04 - dbeaver/`
  - Exports `.json` config files and subdirectories (drivers, templates)
  - Skips files > 512 KB (cache, not config)
  - Preserves existing `readme.txt` in target

### Fixed

- **Typo in `Uninstall-Dbeaver`** -- `$$DbConfig` corrected to `$DbConfig`

---

## [v0.13.1] -- 2026-04-11

### Added

- **Uninstall coverage audit check** (Check 11) -- Verifies every script has:
  - An `Uninstall-*` function in its helper file
  - An `uninstall` command handler in `run.ps1`
  - Uninstall help entries in `log-messages.json`
  - Exempt scripts: 02 (Chocolatey), 12 (orchestrator), audit, databases

### Fixed

- **Stale `\dev` path references** in audit symlink check (`checks.ps1` lines 457, 472) -- now correctly uses `\dev-tool`

---

## [v0.13.0] -- 2026-04-11

### Added

- **`path` command** -- Persistently set, view, or reset the default dev directory
  - `.\run.ps1 path D:\devtools` -- save custom dev directory
  - `.\run.ps1 path` -- show current saved path
  - `.\run.ps1 path --reset` -- clear saved path, revert to smart detection
  - Saved to `scripts/dev-path.json`; all scripts pick it up automatically via `Resolve-DevDir`
  - Priority: `-Path` param > `$env:DEV_DIR` > saved path > smart detection

---

## [v0.12.1] -- 2026-04-11

### Fixed

- **Default dev directory references** -- Updated all remaining `\dev` path references to `\dev-tool` across configs, specs, memory files, and shared helpers (43 files total)

---

## [v0.12.0] -- 2026-04-11

### Added

- **`uninstall` subcommand rolled out to all 34 scripts** (01-38, excluding 02-Chocolatey)
  - Each script now supports `.\run.ps1 uninstall` with full cleanup logic
  - Chocolatey packages removed via `Uninstall-ChocoPackage`
  - Environment variables and PATH entries cleaned up
  - Dev directory subfolders deleted
  - Tracking records purged (`.installed/` and `.resolved/`)
  - Special handling: registry cleanup (10, 31), dotnet tool (29), tracking-only (14, 15)
- **Batch uninstall in script 12 orchestrator**
  - Interactive: `[U] Uninstall` option in quick menu with checkbox picker
  - Flag-based: `-Uninstall`, `-Uninstall -All`, `-Uninstall -Only 03,05,07`
  - Dry run: `-Uninstall -DryRun` to preview without changes
  - Safety: Chocolatey (02) always skipped, reverse execution order, YES confirmation required
- **Batch uninstall in databases orchestrator** (`scripts/databases/run.ps1`)
  - `.\run.ps1 -Uninstall` -- interactive picker
  - `.\run.ps1 -Uninstall -All` -- uninstall all databases
  - `.\run.ps1 -Uninstall -Only mysql,redis` -- uninstall specific databases
  - `.\run.ps1 -Uninstall -DryRun` -- preview mode
  - Reverse order execution with YES confirmation
- **`-Path` parameter rolled out to all 38 `run.ps1` scripts**
  - Consistent `[Parameter(Position = 1)] [string]$Path` across all scripts
  - Overrides `$env:DEV_DIR` and smart drive detection
  - Orchestrators propagate `-Path` to child scripts via `$env:DEV_DIR`

### Changed

- **Default dev directory** changed from `\dev` to `\dev-tool` (e.g. `E:\dev-tool`)
  - Updated `Get-SafeDevDirFallback`, `Resolve-SmartDevDir`, user prompts
  - All help text and spec docs updated to reflect new default
  - GitMap fallback path updated from `C:\DevTools\GitMap` to `C:\dev-tool\GitMap`
- **Help output** now shows `-Path` override example and smart detection info

---

## [v0.11.0] -- 2026-04-11

### Added

- **`-Path` parameter** -- Script 05 (Install Python) now accepts `-Path` to override dev directory
  - `.\run.ps1 all F:\dev` installs and configures pip to `F:\dev\python`
  - Overrides both smart drive detection and `$env:DEV_DIR`
  - Pattern to be rolled out to all scripts
- **`uninstall` subcommand** -- Script 05 (Install Python) reference implementation
  - Runs `choco uninstall python3 --remove-dependencies`
  - Removes `PYTHONUSERBASE` environment variable
  - Removes `Scripts\` from User PATH
  - Deletes `<devDir>\python` subfolder
  - Purges `.installed/python.json` and `.resolved/05-install-python/`
- **Shared uninstall helpers** for all scripts to use:
  - `Uninstall-ChocoPackage` in `choco-utils.ps1`
  - `Remove-FromUserPath` in `path-utils.ps1`
  - `Remove-InstalledRecord` in `installed.ps1`
  - `Remove-ResolvedData` in `resolved.ps1`
- **Help system upgrade** -- `help.ps1` now auto-injects `-Path` parameter in help output for all scripts
  - Reads `help.parameters` block from `log-messages.json`
  - Renamed "Flags:" section to "Parameters:" for clarity
- **Install keywords documentation** -- added Install Keywords section to all 35+ spec readmes
  - Each spec now documents direct keywords, mode overrides, and group shortcuts
  - Consistent formatting with tables and PowerShell usage examples
- **`data-dev` group shortcut** -- bundles PostgreSQL (20), Redis (24), DuckDB (28), DBeaver (32)
  - Also aliased as `datadev`
- **`mobile-dev` group shortcut** -- bundles Flutter-related scripts
- **Flutter mode overrides** -- `flutter-only`, `flutter+android`, `flutter-extensions` keywords

---

## [v0.10.0] -- 2026-04-10

### Added

- **Script 38 -- Install Flutter** -- complete Flutter development environment setup
  - Installs Flutter SDK (includes Dart) via Chocolatey
  - Installs Android Studio via Chocolatey
  - Installs Google Chrome for Flutter web development
  - Installs VS Code Flutter and Dart extensions (`Dart-Code.dart-code`, `Dart-Code.flutter`)
  - Runs `flutter doctor` post-install and auto-accepts Android licenses
  - Subcommands: `all`, `install`, `android`, `chrome`, `extensions`, `doctor`
- Registered script 38 in `registry.json` and orchestrator config
- Added to "Everything" group and execution sequence
- Created spec at `spec/38-install-flutter/readme.md`

---

## [v0.9.1] -- 2026-04-10

### Fixed

- Fixed `Test-KeywordModes` audit check crash when config.json has no top-level `validModes` -- replaced direct property access with safe `PSObject.Properties.Name -contains` check to avoid strict-mode errors

---

## [v0.9.0] -- 2026-04-10

### Added

- **DBeaver settings sync** -- Script 32 now supports 3 modes: `install+settings`, `settings-only`, `install-only`
- New `Sync-DbeaverSettings` function syncs config files from `settings/04 - dbeaver/` to `%APPDATA%\DBeaverData\workspace6\General\.dbeaver\`
- Created `settings/04 - dbeaver/` folder with readme explaining usage
- Added keywords: `dbeaver+settings`, `dbeaver-settings`, `install-dbeaver` with mode mappings
- Settings-only mode does not require admin privileges
- Updated spec/32 readme with full mode documentation

---

## [v0.8.9] -- 2026-04-10

### Fixed

- Changed `ghDesktopNotFound` log level from `warn` to `info` in Script 08 -- "not found, installing" is expected install flow, not a warning

---


## [v0.8.8] -- 2026-04-09

**Maintenance release -- verified v0.8.7 changes**

### Verified

- GitHub Desktop folder scanning (`Add-ReposToGitHubDesktop`) tested end-to-end
- Simple Sticky Notes SSN keyword and custom data folder confirmed working
- OBS/WT settings sync `$PSScriptRoot` path fix confirmed
- `Install-OBS` return value propagation confirmed
- PS 5.1 `Join-Path` compatibility confirmed across all scripts

---

## [v0.8.7] -- 2026-04-09

**GitHub Desktop: post-install folder scanning for Git repos**

### Added

- `scanFolders` config block in Script 08 (`config.json`) with `paths`, `maxDepth`, and `excludePatterns`
- `Add-ReposToGitHubDesktop` function -- scans configured folders for `.git` directories and adds discovered repos to `%APPDATA%\GitHub Desktop\repositories.json`
- `Find-GitRepos` helper -- breadth-first search for `.git` folders with depth limit and exclusion patterns
- Log messages for scan progress, discovery, and summary

---

## [v0.8.6] -- 2026-04-09

**Simple Sticky Notes: SSN keyword + custom data folder**

### Added

- `ssn` keyword shortcut for Script 34 in `install-keywords.json`
- Custom data folder support for Simple Sticky Notes: redirects `%APPDATA%\Simple Sticky Notes` to a configurable path (default `D:\notes`) via directory symlink
- New `Set-StickyNotesDataFolder` function in `helpers/sticky-notes.ps1` -- creates target folder, migrates existing data, creates symlink
- `dataFolder` config block in `config.json` with `enabled`, `path`, and `createIfMissing` fields

---

## [v0.8.5] -- 2026-04-09

**Fix Join-Path PS 5.1 compatibility in Get-ScriptVersion**

### Fixed

- `Get-ScriptVersion` in `run.ps1` used 3-argument `Join-Path` which only works in PowerShell 7+; PS 5.1 threw "positional parameter cannot be found that accepts argument 'version.json'" -- nested to `Join-Path (Join-Path ...) "version.json"`

---

## [v0.8.4] -- 2026-04-09

**Install-OBS return value fix**

### Fixed

- `Install-OBS` now correctly returns `$false` when `Sync-OBSSettings` fails -- previously returned `$true` after a successful install even if settings sync failed, causing the root dispatcher to report `1 of 1` instead of `0 of 1`

---

## [v0.8.3] -- 2026-04-09

**PSScriptRoot path fix for OBS and WT settings sync**

### Fixed

- OBS settings sync (`Sync-OBSSettings`) now uses `$PSScriptRoot` instead of `$MyInvocation.ScriptName` to resolve the repo root -- fixes incorrect path when dot-sourced from `run.ps1`
- WT settings sync (`Sync-WTSettings`) updated with the same `$PSScriptRoot` path resolution fix for consistency
- Added `37 = "WT_MODE"` to `$modeEnvVars` in `run.ps1` so WT mode keywords (`wt-settings`, `wt+settings`) pass the mode correctly

---

## [v0.8.2] -- 2026-04-08

**Version header, self-update on update command, WT keywords, OBS path fix**

### Added

- Version header (`Scripts Fixer vX.Y.Z`) displayed at top of `run.ps1` output (no-params, `-Help`, `update`)
- `Get-ScriptVersion` and `Show-VersionHeader` helpers in `run.ps1` reading from `scripts/version.json`
- WT keywords added to `Show-RootHelp` and `Show-KeywordTable`: `wt`, `windows-terminal`, `wt+settings`, `wt-settings`, `install-wt` (script 37)
- All missing keywords (scripts 31-37) added to `spec/root-dispatcher/readme.md` keyword table

### Changed

- `update` command now performs git pull (self-update) before running `choco upgrade all`
- Updated `spec/root-dispatcher/readme.md` with version header docs, separate execution flow sections, and self-update behaviour

### Fixed

- OBS settings sync path traversal bug -- `Sync-OBSSettings` was resolving to `scripts/settings/` instead of project root `settings/` (added missing `Split-Path -Parent` level)

---

## [v0.8.1] -- 2026-04-08

**Orchestrator config fix, repo URL update to v6**

### Fixed

- Added scripts 34 (Sticky Notes), 36 (OBS Studio), 37 (Windows Terminal) to orchestrator config (`scripts/12-install-all-dev-tools/config.json`) -- scripts block, execution sequence, and "Everything (01-37)" group

### Changed

- Repository clone URL updated from `scripts-fixer-v5` to `scripts-fixer-v6` in `readme.md`

---

## [v0.7.4] -- 2026-04-07

**Windows Terminal 3-mode installer, golangci-lint + go vet, combo keywords in summary, GitMap URL update**

### Added

- Script 37: **Windows Terminal** installer via winget (`Microsoft.WindowsTerminal`) with 3-mode support
  - `install+settings` (default) -- install WT + sync settings
  - `settings-only` -- sync settings only (restore/fix config)
  - `install-only` -- install without touching settings
  - Mode resolution: `-Mode` param > `$env:WT_MODE` > default
- Settings sync copies from `settings/03 - windows-terminal/` to `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\`
- Keywords: `wt`, `windows-terminal`, `wt+settings`, `wt-settings`, `install-wt` with mode mappings
- **golangci-lint** install support in script 06 (Go) -- installs via `go install` with version pinning
- **go vet** integration in script 06 -- runs `go vet ./...` after Go install for verification
- Combo keywords section in `spec/script-registry-summary.md` -- lists multi-script keywords (e.g. `web-dev`, `full-stack`, `essentials`) with mapped script IDs

### Changed

- GitMap install URL updated from `alimtvnetwork/git-repo-navigator` to `alimtvnetwork/gitmap-v2` in `scripts/35-install-gitmap/config.json`
- Updated `spec/35-install-gitmap/readme.md` to reflect new gitmap-v2 repo URL
- Mode env var dispatcher in `run.ps1` now includes `37 = WT_MODE`

---

## [v0.7.3] -- 2026-04-07

**OBS settings sync rework, keyword modes audit check**

### Changed

- OBS settings sync reworked: extract zip to `%TEMP%`, copy `.json` scene collections to `basic\scenes\`, profile folders to `basic\profiles\`
- Settings source changed from script-local folder to `settings/02 - obs-settings/` (shared settings directory)
- OBS picks up scenes and profiles automatically on startup -- no CLI import needed

### Added

- Audit Check 10: **Keyword modes vs config validModes** -- verifies every mode in `install-keywords.json` maps to a valid entry in the target script's `config.json` `validModes` array
- Added `validModes` arrays to `config.json` for scripts 16 (PHP), 33 (NPP), 36 (OBS)

---

## [v0.7.2] -- 2026-04-07

**OBS Studio 3-mode installer script**

### Added

- Script 36: **OBS Studio** installer via Chocolatey (`obs-studio`) with 3-mode support
  - `install+settings` (default) -- install OBS + sync settings
  - `settings-only` -- sync settings only (restore/fix config)
  - `install-only` -- install without touching settings
  - Mode resolution: `-Mode` param > `$env:OBS_MODE` > default
- Settings sync extracts zip from `settings/02 - obs-settings/` to `%APPDATA%\obs-studio\`
- Keywords: `obs`, `obs-studio`, `obs+settings`, `obs-settings`, `install-obs`

### Changed

- Mode env var dispatcher in `run.ps1` now includes `36 = OBS_MODE`

---

## [v0.7.1] -- 2026-04-07

**Combo keywords, Simple Sticky Notes, Choco update, PHP+phpMyAdmin modes**

### Added

- Script 34: **Simple Sticky Notes** installer via Chocolatey (`simple-sticky-notes`)
- `.\run.ps1 update` command -- lists all installed Chocolatey packages, prompts for confirmation, runs `choco upgrade all -y`
  - Aliases: `update`, `upgrade`, `choco-update`
- PHP + phpMyAdmin 3-mode support in script 16:
  - `php+phpmyadmin` (default) -- install both
  - `php-only` -- PHP only
  - `phpmyadmin-only` -- phpMyAdmin only
  - Mode resolution: `-Mode` param > `$env:PHP_MODE` > default
- Combo shortcut keywords:
  - `vscode+settings` / `vscode+s` -- VSCode + Settings Sync (01, 11)
  - `vscode+menu+settings` / `vms` -- VSCode + Menu Fix + Sync (01, 10, 11)
  - `git+desktop` / `git+gh` -- Git + GitHub Desktop (07, 08)
  - `node+pnpm` -- Node.js + pnpm (03, 04)
  - `frontend` -- VSCode + Node + pnpm + Sync (01, 03, 04, 11)
  - `backend` -- Python + Go + PHP + PostgreSQL (05, 06, 16, 20)
  - `web-dev` / `webdev` -- VSCode + Node + pnpm + Git + Sync (01, 03, 04, 07, 11)
  - `essentials` -- VSCode + Choco + Node + Git + Sync (01, 02, 03, 07, 11)
  - `full-stack` / `fullstack` -- Everything for full-stack dev (01-09, 11, 16)
- Help tables updated with "Combo Shortcuts" section

### Fixed

- **OrderedDictionary ArgumentOutOfRangeException** -- `[int]` keys in `[ordered]@{}` were treated as positional indexes; changed to string keys
- Generic mode env var dispatcher (`$modeEnvVars` map) replaces hardcoded `$env:NPP_MODE`

---

## [v0.7.0] -- 2026-04-07

**Code Red: Mandatory file-path error logging with Write-FileError helper**

### Added

- `Write-FileError` centralised helper in `scripts/shared/logging.ps1` -- enforces exact file path, operation, reason, and module in every file/path error log
- Structured `file-error` event type in JSON logs with fields: `filePath`, `operation`, `reason`, `module`, `fallback`
- Auto-detects calling module from PowerShell call stack when `-Module` is not provided
- Spec document: `spec/02-app-issues/error-management-file-path-and-missing-file-code-red-rule.md`

### Improved

- `Import-JsonConfig` -- now calls `Write-FileError` when config file is missing
- `Backup-File` -- file copy failures include exact source and destination paths
- `New-DbSymlink` -- unresolved install directory and junction creation failures include full paths
- `Clear-ResolvedData` -- edition clear and full wipe failures include resolved directory path
- `Save-ResolvedData` -- read and write failures include resolved.json path
- `Add-ToUserPath` / `Add-ToMachinePath` -- PATH update failures include target directory
- `Install-NotepadPP` -- post-install EXE verification logs all checked paths on failure
- `Sync-NotepadPPSettings` -- zip extraction, missing source dir, and empty settings all log exact paths
- `Install-Gitmap` -- remote installer failure logs install directory
- `Resolve-SourceFiles` -- profile parse failure logs profile path
- `Apply-Settings` / `Apply-Keybindings` -- copy failures log source and destination paths
- `Invoke-Edition` -- missing settings.json after apply logs expected target path

### Rule

- **CODE RED**: Every file-related or path-related error MUST include exact file path and failure reason. Generic "file not found" without path is forbidden.

---

## [v0.6.9] -- 2026-04-07

**Keyword mode-merging fix -- duplicate script runs prevented**

### Fixed

- `Resolve-InstallKeywords` now merges multiple keywords targeting the same script ID into a single entry using highest-priority mode (e.g. `npp,npp-settings` → one run with `install+settings` instead of two separate runs)
- Mode priority system: `install+settings` (3) > `install-only` (2) > `settings-only` (1)

### Improved

- Keyword resolver deduplicates by script ID before execution loop, preventing redundant Chocolatey installs
- Execution loop applies per-entry `$env:NPP_MODE` correctly for merged mode

---

## [v0.6.8] -- 2026-04-07

**Notepad++ 3-variant installation modes with bundled settings zip**

### Added

- Three installation modes for script 33 (`NPP` = Notepad++):
  - **NPP + Settings** (`install+settings`) -- install Notepad++ and extract settings (default)
  - **NPP Settings** (`settings-only`) -- extract settings zip only, no install
  - **Install NPP** (`install-only`) -- install only, no settings sync
- Bundled `notepadpp-settings.zip` in `scripts/33-install-notepadpp/settings/` -- extracted to `%APPDATA%\Notepad++\` (full replace)
- New keywords: `npp+settings`, `npp-settings`, `install-npp` with dedicated mode mappings
- `modes` map in `install-keywords.json` -- keyword resolver sets `$env:NPP_MODE` per script invocation
- Mode resolution chain: `-Mode` param > `$env:NPP_MODE` > default `install+settings`

### Improved

- `run.ps1` keyword resolver (`Resolve-InstallKeywords`) now reads `modes` map and injects env vars
- Help tables and Available Scripts section updated with all NPP variant keywords
- `spec/33-install-notepadpp/readme.md` rewritten with full 3-mode documentation

---

## [v0.6.7] -- 2026-04-07

**Notepad++ installer with settings sync**

### Added

- Script 33 (`33-install-notepadpp`) -- installs Notepad++ via Chocolatey and syncs custom settings to `%APPDATA%\Notepad++\`
- `Sync-NotepadPPSettings` helper copies all files from script's `settings/` folder, replacing existing config
- `npp`, `notepad++`, `notepadpp`, `notepad-plus-plus` install keywords mapping to script ID 33
- Notepad++ added to Everything group preset and registry
- `spec/33-install-notepadpp/readme.md` with full usage documentation

---

## [v0.6.6] -- 2026-04-07

**Install target path now logged prominently before drive detection**

### Improved

- Install target path logged immediately with `success` level and visual spacing so it stands out
- Changed "GitMap not found" from `warn` to `info` level (expected during first install, no longer pollutes error log)
- Updated log message to "Install target: {path}" for clarity

---

## [v0.6.5] -- 2026-04-07

**Fixed logging: warnings no longer cause false fail status + improved drive detection + one-line summary**

### Fixed

- `_LogErrors` was tracking both warnings and errors, causing scripts with harmless warnings to report `overallStatus: "fail"` -- now only actual errors trigger fail
- Split warning tracking into separate `_LogWarnings` collection in `logging.ps1`
- Drives reporting 0 GB free (phantom/card reader drives) now logged as `info` instead of `warn`, preventing false warning noise

### Added

- One-line copy-paste-friendly summary printed at end of every script run (e.g. `[install-gitmap] Status: ok | Duration: 1.7s`)
- Error details printed with `>>` prefix for quick scanning when failures occur
- `warnCount` field added to main log JSON output

---

## [v0.6.4] -- 2026-04-07

**Updated root-dispatcher spec with -List flag documentation**

### Docs

- Added `-List` flag to parameters table in `spec/root-dispatcher/readme.md`
- Updated execution flow to include `-List` check before `-Help` and `-Clean`
- Added `-List` usage example to spec

---

## [v0.6.3] -- 2026-04-07

**Added -List flag to run.ps1**

### Added

- `-List` flag on `run.ps1` that prints only the keyword-to-script-ID table for quick reference
- `Show-KeywordTable` function for compact keyword listing

---

## [v0.6.2] -- 2026-04-07

**GitMap folder-specific install via devDir integration**

### Changed

- GitMap installer now resolves install directory via `Resolve-DevDir` (smart drive detection, `$env:DEV_DIR`, config override)
- Passes `-InstallDir <resolved-path>` to the remote installer from GitHub
- `run.ps1` now dot-sources `dev-dir.ps1` and passes `$config.devDir` to the helper
- Detection also checks `$env:DEV_DIR\GitMap\gitmap.exe`
- Resolved state now includes `installDir` field
- Added `installDir` log message to `log-messages.json`
- Updated spec with devDir resolution priority, remote installer flags, and detection paths

---

## [v0.6.1] -- 2026-04-07

**GitMap added to Everything group preset**

### Changed

- Added script 35 (GitMap) to the Everything group preset (letter `n`) in `scripts/12-install-all-dev-tools/config.json`
- Updated group label from `Everything (01-32)` to `Everything (01-35)`

---

## [v0.6.0] -- 2026-04-07

**GitMap installer, global -Defaults/-Y flags, and run.ps1 enhancements**

### Added

- Script 35 (`35-install-gitmap`) -- installs GitMap CLI via remote installer from GitHub (`alimtvnetwork/git-repo-navigator`)
- `gitmap`, `git-map` install keywords mapping to script ID 35
- GitMap entry in all-dev `config.json` and `registry.json`
- Global `-Defaults` (`-D`) and `-Y` flags on `run.ps1` -- propagated to child scripts as `ExtraArgs`
- `-Defaults` shows all default values and prompts for confirmation before proceeding
- `-Defaults -Y` auto-confirms and proceeds without prompting
- `-Defaults` without `-I` defaults to script 12 (all-dev)
- Defaults Mode section in `run.ps1 -Help` showing default dev directory, VS Code edition, and sync mode
- `spec/35-install-gitmap/readme.md` with full usage documentation

---

## [v0.5.5] -- 2026-04-07

**Release pipeline script for versioned ZIP packaging**

### Added

- `release.ps1` -- packages `scripts/`, `run.ps1`, `bump-version.ps1`, `readme.md`, `LICENSE`, and `CHANGELOG.md` into a versioned ZIP under `.release/`
- Supports `-DryRun` (preview contents) and `-Force` (overwrite existing ZIP) flags
- Reads version automatically from `.gitmap/release/latest.json`
- `spec/release-pipeline/readme.md` with full usage documentation

---

## [v0.5.4] -- 2026-04-06

**Audit --DryRun flag and Invoke-WithTimeout shared helper**

### Added

- `--DryRun` flag for audit symlink verification (`Test-VerifySymlinks`) -- previews which symlinks would be removed, created, or skipped without modifying the filesystem
- `Invoke-WithTimeout` shared helper (`scripts/shared/invoke-with-timeout.ps1`) -- wraps any script block in a background job with a configurable timeout guard, polling progress logs, and forceful termination on timeout
- 6 new `timeout*` log message keys in `scripts/shared/log-messages.json`
- Usage examples for `--DryRun` in `spec/audit/readme.md`
- Full `invoke-with-timeout.ps1` section in `spec/shared/readme.md`

---

## [v0.5.3] -- 2026-04-06

**DBeaver Community installer, combo group presets, and database menu integration**

### Added

- Script 32 (`32-install-dbeaver`) -- installs DBeaver Community Edition via Chocolatey with `config.json`, `helpers/dbeaver.ps1`, `log-messages.json`, and `run.ps1`
- `spec/32-install-dbeaver/readme.md` -- spec doc for the DBeaver installer
- `dbeaver`, `db-viewer`, `dbviewer` install keywords mapping to script ID 32
- DBeaver entry in `databases/config.json` as type `"tool"` so it appears in the interactive database installer menu (script 30)
- New all-dev menu combo group presets in `12-install-all-dev-tools/config.json`:
  - `o` -- All Dev + MySQL
  - `p` -- All Dev + PostgreSQL
  - `r` -- All Dev + PostgreSQL + Redis
  - `s` -- SQLite + DBeaver
  - `t` -- All DBs + DBeaver (18-29, 32)
- New database menu groups in `databases/config.json`:
  - `f` -- Popular + DBeaver
  - `g` -- All + DBeaver
- Registry entry for script 32 in `scripts/registry.json`
- DBeaver added to orchestrator config sequence and `"Everything"` group

---

## [v0.5.2] -- 2026-04-06

**Post-install symlink verification for database scripts**

### Added

- `Test-PostInstallSymlink` helper in `databases/run.ps1` -- verifies junction exists and is a valid reparse point after each database install
- `symlinkVerifyOk`, `symlinkVerifyMissing`, `symlinkVerifyNotJunction` log messages in `databases/log-messages.json`
- `Invoke-DbScript` now accepts `$Key` parameter and triggers symlink verification automatically after script completion

---

## [v0.5.1] -- 2026-04-06

**Drive override flag, audit --Fix for broken symlinks, and new spec docs**

### Added

- `-Drive` flag on `databases/run.ps1` -- override auto-detected drive (e.g. `.\run.ps1 -Drive F`)
- `-Fix` flag on `audit/run.ps1` -- removes broken junctions and recreates them automatically
- `driveOverride` log message in `databases/log-messages.json`
- Audit fix log messages (`symlinkFixRemoved`, `symlinkFixCreated`, `symlinkFixSkipped`, `symlinkFixMissing`) in `audit/log-messages.json`
- `spec/shared/dev-dir.md` -- smart drive selection, 10 GB threshold, `Test-DriveQualified` / `Find-BestDevDrive` / `Resolve-SmartDevDir` docs
- `spec/shared/symlink-utils.md` -- `Resolve-DbInstallDir` and `New-DbSymlink` function docs

### Changed

- `audit/helpers/checks.ps1` `Test-VerifySymlinks` now accepts `-Fix` to repair broken and missing junctions
- `audit/run.ps1` dot-sources `symlink-utils.ps1` and passes `-Fix` through

### Fixed

- Broken or stale database junctions can now be auto-repaired instead of requiring manual cleanup

---

## [v0.5.0] -- 2026-04-06

**Smart drive detection, database symlinks, and dynamic dev directory resolution**

### Added

- Smart drive detection in `dev-dir.ps1`: priority E: > D: > best non-system drive > user prompt
- `Test-DriveQualified` function -- checks drive exists and has at least 10 GB free space
- `Find-BestDevDrive` function -- scans fixed drives and picks the best candidate
- `Resolve-SmartDevDir` function -- orchestrates detection with user prompt fallback
- `scripts/shared/symlink-utils.ps1` with `Resolve-DbInstallDir` and `New-DbSymlink` functions
- Directory junction creation from `<devDir>\databases\<name>` to actual Chocolatey install paths
- 15 new log messages (8 drive detection + 7 symlink) in `shared/log-messages.json`
- All 12 database `run.ps1` files now call `New-DbSymlink` after successful install

### Changed

- All `config.json` files updated from `"mode": "json-or-prompt"` / `"default": "E:\\dev"` to `"mode": "smart"` / `"default": "auto"`
- `Resolve-DevDir` now uses smart drive detection instead of hardcoded defaults
- `installMode: "devDir"` config option now actually creates junctions to the dev directory

### Fixed

- Databases previously installed to system default locations ignoring `devDir` config -- now symlinked to `<devDir>\databases\<name>`
- Dev directory no longer hardcoded to E: drive -- dynamically selects the best available drive

---

## [v0.4.1] -- 2026-04-07

**Crash-safe error logging, VS Code/pwsh detection fallbacks, and full-path error diagnostics**

### Added

- `try/catch/finally` wrapper in all 31 `run.ps1` files -- `Save-LogFile` now always runs, even on unhandled exceptions
- Warnings (warn-level) now captured in error log files alongside errors, with separate `errors` and `warnings` arrays
- `warnCount` field added to error log JSON schema
- 4-tier VS Code exe fallback chain: config paths → Chocolatey shim/lib → `Get-Command` → `where.exe` (script 10)
- Chocolatey shim fallback for `pwsh.exe` detection (script 31)
- Detailed per-step failure logging for all fallback paths in scripts 10 and 31

### Changed

- `fileExistsAtPath` log message now includes the full file path being checked, not just True/False
- File-not-found checks in scripts 10 and 31 now log at error/warn level instead of info (captured in error logs)
- `Get-InstalledDir` function replaces `$script:_InstalledDir` variable for robust sourcing context
- `Save-InstalledRecord` accepts empty version strings gracefully (falls back to `'unknown'`)
- Error log creation trigger expanded: any warn OR fail event now generates an error log file

### Fixed

- `$script:_InstalledDir` variable not set error -- replaced with `Get-InstalledDir` function that works regardless of dot-sourcing context
- Empty version string error in `Save-InstalledRecord` when `choco list` returns no match
- Missing error log files when scripts crashed with unhandled exceptions before `Save-LogFile` could run
- VS Code exe not found after Chocolatey install because `config.json` only had user/system paths, not choco paths

### Docs

- Issue 4 added to `scripts/10-vscode-context-menu-fix/issues.md` documenting Chocolatey path detection root cause
- `spec/shared/logging.md` updated with warn-level capture, new error log schema, and crash-safe `try/catch/finally` pattern
- `spec/shared/installed.md` updated with `Get-InstalledDir`, empty version fallback, and Error Tracking section

---

## [v0.4.0] -- 2026-04-06

**Error tracking, registry API migration, database menu option, and spec updates**

### Added

- `Save-InstalledError` catch blocks in all 13 install helper scripts (vscode, choco, nodejs, pnpm, python, golang, git, github-desktop, mingw, winget, php, powershell, databases)
- All Databases Only option (`mode: alldb`) as option 3 in script 12 quick menu
- Error Tracking section in `spec/shared/installed.md` with field docs, JSON examples, and retry behaviour
- `Save-InstalledError` column in spec tracking table showing coverage across all scripts

### Changed

- Scripts 10 and 31 migrated from `reg.exe` to .NET `Microsoft.Win32.Registry` API to fix Invalid syntax errors with nested quotes
- Script 12 questionnaire reordered: Install All (1), Dev Tools Only (2), All Databases Only (3), Custom (4)

### Fixed

- Registry command failures in scripts 10 (VS Code context menu) and 31 (PowerShell context menu) caused by `cmd.exe /c` parsing of nested quotes in `pwsh.exe -Command` strings

### Docs

- Updated `spec/shared/installed.md` with error JSON schema fields (`lastError`, `errorAt`), recovery examples, and retry behaviour
- Updated `scripts/10-vscode-context-menu-fix/issues.md` with root cause analysis and .NET API migration notes

---

## [v0.3.0] -- 2026-04-05

**Database scripts, installation tracking, front-loaded questionnaire, shared helpers, and structured logging**

### Added

- Database installation scripts (18-29): MySQL, MariaDB, PostgreSQL, SQLite, MongoDB, CouchDB, Redis, Cassandra, Neo4j, Elasticsearch, DuckDB, LiteDB
- Database orchestrator (`scripts/databases/`) with interactive menu, `-All`, `-Only`, `-Skip`, `-DryRun` flags
- Generic `Install-Database` function in `scripts/databases/helpers/install-db.ps1` (choco and dotnet-tool methods)
- Installation tracking via `.installed/` folder with per-tool JSON files (name, version, method, timestamps, error fields)
- Shared `installed.ps1` with `Test-AlreadyInstalled`, `Save-InstalledRecord`, `Save-InstalledError`, `Get-InstalledRecord`
- Front-loaded questionnaire in script 12: dev dir, VS Code editions, sync mode, Git name/email asked upfront
- Quick menu in script 12: Install All Dev (1), All Dev + All DBs (2), Custom (3)
- `-D` / `-Defaults` flag for zero-prompt runs with default answers
- `.resolved/` folder pattern with `Save-ResolvedData` and `Get-ResolvedDir` shared helpers
- Structured JSON logging system: `Initialize-Logging`, `Write-Log` event collection, `Save-LogFile` to `.logs/`
- Error log auto-creation when fail-level events are recorded
- Shared helpers: `choco-utils.ps1`, `path-utils.ps1`, `dev-dir.ps1`
- Script 14 (winget): detection, install via MSIX, PATH refresh
- Script 15 (windows-tweaks): system tweaks with confirmation skip under orchestrator
- Script 16 (PHP): Chocolatey-based install with upgrade support
- Script 17 (PowerShell): pwsh install/upgrade via Chocolatey
- Script 31 (pwsh-context-menu): PowerShell Here context menu entries for folders, backgrounds, and admin mode
- Audit script (`scripts/audit/`): system checks and validation
- `install-keywords.json` mapping natural-language keywords to script IDs
- Interactive menu in script 12: lettered group shortcuts, CSV/space number input, loop-back after install

### Changed

- All install helpers now use `Test-AlreadyInstalled` to skip redundant installs when version matches
- `Write-Banner` auto-reads `scripts/version.json` for project version display
- Logging moved from `scripts/logs/` to `.logs/` at project root
- Version numbers in `Write-Log` output highlighted in Yellow
- Config files are declarative input only -- runtime state goes to `.resolved/`

### Docs

- `spec/shared/installed.md`: installation tracking specification
- `spec/shared/logging.md`: structured logging specification
- Spec docs for all new scripts (14-29, 31, audit, databases)
- Memory files for database-scripts, installed-tracking, interactive-menu, questionnaire, resolved-folder, shared-helpers, logging

---

## [v0.2.0] -- 2026-04-03

Initial tagged release (no changelog recorded).

---

## [v0.1.0] -- 2026-04-03

Initial tagged release (no changelog recorded).
