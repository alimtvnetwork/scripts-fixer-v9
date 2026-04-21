# 01 - VS Code Project Manager Sync (`run.ps1 scan <path>`)

## Overview

Walks a root directory, discovers project folders, and **upserts** them into
the VS Code Project Manager extension's `projects.json` so they show up in
the `alefragnani.project-manager` sidebar.

- Single command: `run.ps1 scan <path> [flags]`
- JSON-only storage (no DB) -- the VS Code `projects.json` IS the source of truth.
- Atomic writes (temp file + rename) -- never corrupts `projects.json`.
- Preserves entries we did not add (and per-entry fields we don't manage:
  `paths`, `tags`, `enabled`, `profile`).
- **Never opens VS Code.** This command only syncs the JSON file.

The `gitmap`-CLI integration and any `gitmap code <alias>` behavior are
**out of scope** for this spec by user decision (2026-04-21). This file
documents only the `scan` command.

## Command

```powershell
.\run.ps1 scan <root-path>                  # walk <root-path>, upsert into projects.json
.\run.ps1 scan <root-path> --depth 4        # custom recursion depth (default 5)
.\run.ps1 scan <root-path> --dry-run        # preview adds/updates, write nothing
.\run.ps1 scan <root-path> --json <file>    # override target projects.json path
.\run.ps1 scan --help                       # show help
```

If `<root-path>` is omitted, the current working directory is used.

## Flags

| Flag             | Description                                                | Default |
|------------------|------------------------------------------------------------|---------|
| `--depth N`      | Max directory recursion depth                              | `5`     |
| `--dry-run`      | Show what would change; do not write `projects.json`       | off     |
| `--json <path>`  | Override target `projects.json` (testing / non-default)    | OS auto |
| `--include-hidden` | Walk into folders starting with `.`                      | off     |
| `--help`         | Show help and exit                                         |         |

## Project Detection

A folder is treated as a project when it contains **any** of:

- `.git/` (Git repository root)
- `package.json`
- `pyproject.toml` / `requirements.txt` / `setup.py`
- `Cargo.toml`
- `go.mod`
- `composer.json`
- `pom.xml` / `build.gradle` / `build.gradle.kts`
- `*.csproj` / `*.sln`
- `Gemfile`
- `.lovable/` (Lovable project marker)

Once a folder qualifies as a project, the walker does **not** recurse into it
(prevents nested `node_modules`-style noise). Hidden folders (`.git`, `.idea`,
`node_modules`, `vendor`, `dist`, `build`, `target`, `.next`, `.venv`, `venv`,
`__pycache__`) are skipped unless `--include-hidden` is passed.

## VS Code `projects.json` Location

| OS      | Path                                                                                   |
|---------|----------------------------------------------------------------------------------------|
| Windows | `%APPDATA%\Code\User\globalStorage\alefragnani.project-manager\projects.json`          |
| macOS   | `~/Library/Application Support/Code/User/globalStorage/alefragnani.project-manager/projects.json` |
| Linux   | `~/.config/Code/User/globalStorage/alefragnani.project-manager/projects.json`          |

If the file or its parent directory does not exist, the script creates them
and seeds the file with `[]`.

## `projects.json` Schema

Confirmed from the user-supplied sample. The file is a JSON array; each entry:

```json
{
  "name": "atto-property",
  "rootPath": "d:\\wp-work\\riseup-asia\\atto-property",
  "paths": [],
  "tags": [],
  "enabled": true,
  "profile": ""
}
```

Field handling on upsert:

| Field      | On insert (new entry)             | On update (existing `rootPath`)     |
|------------|-----------------------------------|-------------------------------------|
| `name`     | Folder basename                   | **Preserved** (user may have aliased it) |
| `rootPath` | Absolute, normalized              | Match key -- never rewritten        |
| `paths`    | `[]`                              | Preserved                           |
| `tags`     | `[]`                              | Preserved                           |
| `enabled`  | `true`                            | Preserved                           |
| `profile`  | `""`                              | Preserved                           |

`rootPath` matching is **case-insensitive on Windows**, case-sensitive on
macOS / Linux. Trailing slashes are stripped before compare.

## Atomic Write Algorithm

1. Read the current `projects.json` (or `[]` if missing).
2. Build the upserted array in memory.
3. Serialize to JSON (UTF-8, no BOM, `Depth = 10`, indented with tabs to match
   the VS Code Project Manager style).
4. Write the bytes to `projects.json.tmp-<pid>-<ticks>` in the same directory.
5. `Move-Item -Force` the temp file over `projects.json`.
6. On any error, the temp file is deleted and the original is left untouched.

## Output

```
  Scripts Fixer v0.50.0
  Scan: VS Code Project Manager Sync
  ==================================

  Root        : D:\wp-work\riseup-asia
  Target JSON : C:\Users\Alim\AppData\Roaming\Code\User\globalStorage\alefragnani.project-manager\projects.json
  Depth       : 5
  Mode        : write

  [scan ] D:\wp-work\riseup-asia\atto-property              (git, node)
  [scan ] D:\wp-work\riseup-asia\category-forge             (git, node)
  ...

  Summary
  -------
    discovered : 14
    added      :  3
    updated    :  0    (already present, no field change)
    preserved  : 11    (existing entries we did not touch)
    skipped    :  0
    written to : C:\Users\Alim\AppData\Roaming\...\projects.json
```

## Acceptance Criteria

| # | Behavior                                                                  |
|---|---------------------------------------------------------------------------|
| 1 | `.\run.ps1 scan D:\code` upserts every discovered project; never opens VS Code |
| 2 | Re-running is idempotent -- no duplicates by `rootPath`                   |
| 3 | Existing entries we did not add are preserved verbatim                    |
| 4 | Existing `name`, `tags`, `paths`, `enabled`, `profile` are preserved on update |
| 5 | File writes are atomic (temp + rename); aborted runs never corrupt JSON   |
| 6 | Works on Windows / macOS / Linux paths                                    |
| 7 | `--dry-run` prints planned changes and writes nothing                     |
| 8 | The string `git map` (with a space) appears nowhere in code, help, or logs |
| 9 | Help text is reachable via `.\run.ps1 scan --help`                        |

## Out of Scope (this spec)

- `gitmap` CLI subcommand (`gitmap code`, `gitmap scan`, etc.)
- SQLite storage layer
- Auto-opening VS Code
- Multi-root (`paths`) authoring
- Auto-deriving `tags` (we leave `tags` alone on update; on insert they are `[]`)

## File Layout

```
scripts/scan/
  run.ps1                # dispatcher
  config.json            # detection markers, ignore list, depth
  log-messages.json      # banner + status strings
  helpers/
    vscode-projects.ps1  # locate / read / atomic-write projects.json
    walker.ps1           # directory walk + project detection
spec/01-vscode-project-manager-sync/
  readme.md              # this file
```
