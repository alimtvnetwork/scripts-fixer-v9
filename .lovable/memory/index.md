# Memory: index.md
Updated: 2026-04-18

# Project Memory

## Core
Project includes PowerShell utility scripts alongside the React web app.
User prefers structured script projects: external JSON configs, spec docs, suggestions folder, colorful logging.
CODE RED: Every file/path error MUST log exact file path + failure reason. Use Write-FileError helper.
Current version: v0.38.0 with 43 scripts, 81-model GGUF catalog, models orchestrator, bootstrap auto-discovery.
4-filter chain in model picker: RAM -> Size -> Speed -> Capability.
Bootstrap (install.ps1): CWD-aware target (CWD\scripts-fixer when safe, else USERPROFILE), self-relocation, stderr-noise fix, -DryRun, launches `.\run.ps1` with no args.
"read memory" triggers .lovable/prompts/01-read-prompt.md. "write memory" / "end memory" triggers .lovable/prompts/02-write-prompt.md.

## Memories
- [Script structure](mem://preferences/script-structure) — How the user wants scripts organized with configs, specs, and suggestions
- [Naming conventions](mem://preferences/naming-conventions) — is/has prefix for booleans; kebab-case file/folder names
- [Terminal banners](mem://constraints/terminal-banners) — Avoid em dashes and wide Unicode in box-drawing banners
- [Error management file path rule](mem://features/error-management-file-path-rule) — CODE RED: every file/path error must include exact path and failure reason
- [Database scripts](mem://features/database-scripts) — Database installer script patterns
- [Installed tracking](mem://features/installed-tracking) — .installed/ tracking system
- [Interactive menu](mem://features/interactive-menu) — Interactive menu system for script 12
- [Logging](mem://features/logging) — Structured JSON logging system
- [Notepad++ settings](mem://features/notepadpp-settings) — 3-variant NPP install modes with settings zip
- [Questionnaire](mem://features/questionnaire) — Questionnaire system for script 12
- [Resolved folder](mem://features/resolved-folder) — .resolved/ runtime state persistence
- [Shared helpers](mem://features/shared-helpers) — Shared PowerShell helper modules
- [2025 batch spec](mem://features/2025-batch) — Spec for scripts 47-51, os/gsa subcommands, 5 install profiles (awaiting sign-off)
- [Model picker filters](mem://features/model-picker-filters) — 4-filter chain (RAM, Size, Speed, Capability) with re-indexing
- [Path parameter](mem://features/path-parameter) — Every run.ps1 accepts -Path to override dev directory
- [Uninstall command](mem://features/uninstall-command) — Every run.ps1 supports uninstall subcommand
- [Install bootstrap](mem://features/install-bootstrap) — install.ps1/install.sh auto-discovery, fresh-clone, -Version flag
- [Install self-relocation](mem://features/install-self-relocation) — install.ps1 stderr-noise fix + cd-out + TEMP-staging fallback when CWD is/contains scripts-fixer
- [Install target resolution](mem://features/install-target-resolution) — install.ps1 CWD-aware target with safe fallback; final launches `.\run.ps1` no-args
- [Models orchestrator](mem://features/models-orchestrator) — scripts/models/ unified entry: search, install csv, uninstall
- [Suggestions tracker](mem://suggestions/01-suggestions-tracker) — All suggestions: implemented and pending
- [Workflow status](mem://workflow/01-current-status) — What is done and pending as of v0.36.0
