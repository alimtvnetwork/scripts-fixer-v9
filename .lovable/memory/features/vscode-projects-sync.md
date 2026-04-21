---
name: VS Code Project Manager sync (`run.ps1 scan <path>`)
description: Scan command upserts discovered projects into VS Code Project Manager projects.json -- match by rootPath, atomic writes, never opens VS Code
type: feature
---

## Command
`.\run.ps1 scan <path> [--depth N] [--dry-run] [--json <file>] [--include-hidden]`

If `<path>` is omitted, current working directory is used.

## Source of truth
The VS Code `projects.json` itself. **No SQLite, no sidecar DB.**

## Target file (per OS)
| OS      | Path                                                                                   |
|---------|----------------------------------------------------------------------------------------|
| Windows | `%APPDATA%\Code\User\globalStorage\alefragnani.project-manager\projects.json`          |
| macOS   | `~/Library/Application Support/Code/User/globalStorage/alefragnani.project-manager/projects.json` |
| Linux   | `~/.config/Code/User/globalStorage/alefragnani.project-manager/projects.json`          |

If file or parent dir is missing, create with `[]`.

## Schema (confirmed from user upload)
```json
{ "name": "...", "rootPath": "...", "paths": [], "tags": [], "enabled": true, "profile": "" }
```

## Hard rules
1. Match key = `rootPath` (case-insensitive on Windows, case-sensitive on Unix; trailing slashes stripped).
2. On **insert**: `name = folder basename`, `paths=[]`, `tags=[]`, `enabled=true`, `profile=""`.
3. On **update** (rootPath already present): preserve `name`, `paths`, `tags`, `enabled`, `profile` -- never overwrite.
4. Preserve every existing entry we did not add.
5. Atomic write: serialize -> temp file in same dir -> `Move-Item -Force`. Never partial writes.
6. **Never open VS Code** from this command.
7. The string `git map` (with a space) must not appear in code, help, or logs. Command is `gitmap` (single word) only -- and is **out of scope** for this scan command.

## Project detection markers
`.git/`, `package.json`, `pyproject.toml`, `requirements.txt`, `setup.py`, `Cargo.toml`, `go.mod`, `composer.json`, `pom.xml`, `build.gradle`, `build.gradle.kts`, `*.csproj`, `*.sln`, `Gemfile`, `.lovable/`.

Once a folder qualifies, walker does not descend into it. Skip dirs by default: `.git`, `.idea`, `node_modules`, `vendor`, `dist`, `build`, `target`, `.next`, `.venv`, `venv`, `__pycache__`.

## File layout
```
scripts/scan/run.ps1
scripts/scan/config.json
scripts/scan/log-messages.json
scripts/scan/helpers/vscode-projects.ps1
scripts/scan/helpers/walker.ps1
spec/01-vscode-project-manager-sync/readme.md
```

## Dispatcher wiring
Root `run.ps1` recognizes a bare `scan` command (`$isBareScanCommand`) and forwards remaining args to `scripts/scan/run.ps1`. Behaves like the existing `path`, `doctor`, `os`, `git-tools` bare commands.
