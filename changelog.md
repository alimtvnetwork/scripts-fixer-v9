# Changelog

All notable changes to this project are documented in this file.

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
