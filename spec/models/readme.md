# Spec: Models Orchestrator

## Purpose

Single entry point (`./run.ps1 models` / `model` / `-M`) for browsing,
filtering, and installing AI models across both supported backends:

| Backend     | Folder                          | What it installs                    |
|-------------|---------------------------------|-------------------------------------|
| `llama-cpp` | `scripts/43-install-llama-cpp/` | Raw GGUF files for llama.cpp runtime |
| `ollama`   | `scripts/42-install-ollama/`    | Models pulled via the Ollama daemon |

The orchestrator never duplicates picker logic -- it dispatches to the
existing scripts (which already own catalogs, filters, and downloaders).

## CLI surface

| Invocation                                           | Behaviour                                                    |
|------------------------------------------------------|--------------------------------------------------------------|
| `.\run.ps1 models`                                   | Interactive: pick backend, then dispatch to its picker        |
| `.\run.ps1 model`                                    | Alias for `models`                                           |
| `.\run.ps1 -M`                                       | Shortcut flag, same as `models`                              |
| `.\run.ps1 models qwen2.5-coder-3b,llama3.2`         | CSV direct install (auto-routes per backend)                 |
| `.\run.ps1 models -Backend llama-cpp`                | Skip backend prompt, go straight to llama.cpp picker          |
| `.\run.ps1 models -Backend ollama -Install llama3.2,qwen2.5-coder` | Non-interactive install on a specific backend |
| `.\run.ps1 models list`                              | List all models from both catalogs                            |
| `.\run.ps1 models list llama`                        | List only llama.cpp catalog                                   |
| `.\run.ps1 models list ollama`                       | List only Ollama defaults                                    |
| `.\run.ps1 models -Help`                             | Help text                                                    |
| `.\run.ps1 models search llama`                      | **Live search** of ollama.com/library; pick results to pull  |
| `.\run.ps1 models search`                            | Prompts for query, then live search                          |
| `.\run.ps1 models uninstall`                         | List local installs (both backends), multi-select, delete    |
| `.\run.ps1 models uninstall llama`                   | Uninstall picker scoped to llama.cpp GGUF files only         |
| `.\run.ps1 models uninstall ollama`                  | Uninstall picker scoped to Ollama daemon models only         |
| `.\run.ps1 models rm`                                | Alias for `uninstall`                                        |
| `.\run.ps1 models uninstall -Force`                  | Skip the `yes` confirmation prompt (CI / scripts)            |

## File layout

```
scripts/models/
  run.ps1                  # Thin dispatcher (this file is intentionally small)
  config.json              # Backend registry: scriptFolder, catalogFile, idField
  log-messages.json        # All user-facing strings (per logging convention)
  helpers/
    picker.ps1             # Backend picker, catalog loader, CSV resolver, dispatcher
    ollama-search.ps1      # Live Ollama Hub search + HTML parser + result picker
    uninstall.ps1          # Local-installs scanner, multi-select picker, deleter
```

`run.ps1` only handles arg parsing + flow control. All real logic lives in
`helpers/*.ps1` so the file stays under ~200 lines per the project's
"keep run.ps1 small" rule.

## Ollama Hub search

`.\run.ps1 models search <query>` performs a live HTTP GET against
`https://ollama.com/search?q=<query>`, parses the result HTML using stable
`x-test-*` markers (`x-test-model`, `x-test-search-response-title`,
`x-test-size`, `x-test-capability`, `x-test-pull-count`, `x-test-tag-count`,
`x-test-updated`), and renders a numbered table. Selection accepts the
same syntax as the other pickers (`1,3`, `1-5`, `all`, `q`) plus an
optional `:tag` suffix per pick to target a specific size, e.g. `2:7b`
pulls `<slug>:7b`. Selected slugs are joined into a CSV and dispatched to
script 42 via the `OLLAMA_PULL_MODELS` env var (the same handoff used by
the CSV install path), so unknown slugs become ad-hoc `ollama pull <slug>`
calls without needing config edits.

The href parser tolerates both absolute (`href="https://ollama.com/library/X"`)
and relative (`href="/library/X"`) shapes. Network failures and empty
result sets are logged and return cleanly -- they never throw.

## Uninstall

`.\run.ps1 models uninstall` (or `rm` / `remove`) enumerates everything
currently on this machine across both backends:

- **llama.cpp**: source of truth is `.installed/model-*.json` (the same
  tracking files written by `Install-SelectedModels`). Each id is
  cross-referenced with `43-install-llama-cpp/models-catalog.json` to
  recover `fileName`, `displayName`, and `fileSizeGB`. The GGUF folder is
  resolved from `.resolved/43-install-llama-cpp.json` first, then
  `$env:DEV_DIR/llama-models` as fallback. The picker shows whether the
  file is still on disk so users can also clean up stale tracking entries.
- **Ollama**: shells out to `ollama list` and parses its tabular output
  (columns `NAME / ID / SIZE / MODIFIED`, separated by 2+ spaces). When
  the binary or the daemon are unavailable, this returns an empty array
  and logs a warning -- never throws.

After multi-select (same syntax as the install pickers), the orchestrator
prints the proposed deletions and requires an explicit `yes` to proceed.
Pass `-Force` to skip the confirmation prompt entirely -- useful for CI
pipelines and unattended cleanup scripts. Deletion routes per backend:
`Remove-Item` + `Remove-InstalledRecord` for GGUFs, `ollama rm <id>` for
Ollama models. Per-item success/failure is logged and a final summary
line is printed.

## Algorithm

1. **Parse args**: detect list mode vs CSV vs interactive.
2. **List mode**: load catalogs, render flat table, exit.
3. **CSV mode**: load catalog(s), match each id (exact, then `-like *id*`),
   group matches by backend, dispatch to each backend's `run.ps1` with
   the resolved ids passed via env var (`LLAMA_CPP_INSTALL_IDS` /
   `OLLAMA_PULL_MODELS`).
4. **Interactive mode**: prompt for backend (1=llama, 2=ollama, 3=both),
   then either show combined list or invoke the backend script's own
   picker.

## Catalog wiring

`config.json` declares each backend:

```json
{
  "backends": {
    "llama-cpp": {
      "scriptFolder": "43-install-llama-cpp",
      "catalogFile":  "models-catalog.json",
      "idField":      "id",
      "displayField": "displayName"
    },
    "ollama": {
      "scriptFolder": "42-install-ollama",
      "catalogFile":  "config.json",
      "catalogPath":  "defaultModels",
      "idField":      "slug",
      "displayField": "displayName"
    }
  }
}
```

To add a third backend, drop a config entry and a script that accepts
either an env var or a CSV positional arg -- no changes to `picker.ps1`.

## Dispatcher contract

The orchestrator passes resolved ids to backends via env vars rather than
positional args, since both backend scripts already use positional args
for their own subcommands (`install`, `pull`, `models`, `uninstall`).

| Backend     | Env var passed         | Subcommand invoked | Honored by (since) |
|-------------|------------------------|--------------------|--------------------|
| `llama-cpp` | `LLAMA_CPP_INSTALL_IDS` | `all`              | `Invoke-ModelInstaller` -- v0.33.0 |
| `ollama`    | `OLLAMA_PULL_MODELS`    | `pull`             | `Pull-OllamaModels` -- v0.33.0 |

**llama-cpp** behaviour when `LLAMA_CPP_INSTALL_IDS` is set: skip all RAM/size/speed/capability filter prompts, resolve each CSV id against the catalog (exact match first, then `-like *id*`), download only the matched subset. Unmatched ids are warned and skipped; empty result aborts cleanly.

**ollama** behaviour when `OLLAMA_PULL_MODELS` is set: skip per-model yes/no prompt, resolve each slug against `config.json -> defaultModels` (matches `slug` or `pullCommand`), and fall back to ad-hoc `ollama pull <slug>` for unknown slugs so users can pull anything from ollama.com/library without editing config.

## Examples

```powershell
# Interactive: friendliest path
.\run.ps1 models

# Direct install across backends, comma-separated
.\run.ps1 models qwen2.5-coder-3b,llama3.2,deepseek-r1:8b

# Browse before deciding
.\run.ps1 models list
.\run.ps1 models list llama

# Force a backend, skip prompt
.\run.ps1 models -Backend llama-cpp
```

## Why not just point users at scripts 42 and 43?

- Discoverability: `models` is the obvious verb; users don't need to
  know which numbered script handles what.
- Cross-backend CSV: `qwen2.5-coder-3b,llama3.2` mixes backends; users
  shouldn't have to split the call.
- Single help surface: one `--help` lists every model id from every backend.
