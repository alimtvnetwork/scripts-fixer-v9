# `_internal/` -- repo maintenance scripts

These are NOT user-facing dev tools. They're maintenance scripts the project
itself uses to keep generated docs / metadata in sync. None of them are
wired into the registry, the dispatcher, or the keyword map.

## generate-registry-summary.cjs

Auto-regenerates `spec/script-registry-summary.md` from the live data in:

- `scripts/registry.json`             -- numeric ID -> folder mapping
- `scripts/<folder>/config.json`      -- per-script name / desc / chocoPackage / validModes
- `scripts/shared/install-keywords.json` -- keyword -> [script ids] + per-keyword mode overrides

### Run it

```bash
node scripts/_internal/generate-registry-summary.cjs
```

Output is written to `spec/script-registry-summary.md` (overwrites in place).
The script also prints a one-line summary on stdout, e.g.:

```
Wrote /.../spec/script-registry-summary.md
  51 scripts, 329 keywords, 73 mode entries, 47 combos, 25 subcommand keywords
```

### When to re-run

- After adding / removing / renaming a script folder (and updating `registry.json`)
- After editing `scripts/shared/install-keywords.json` (new keywords or modes)
- After editing a script's `config.json` (name / desc / validModes / defaultMode change)

### What the generator pulls

| Source field                       | Where it shows up                              |
|------------------------------------|------------------------------------------------|
| `registry.scripts[id]`             | Folder column + headings                       |
| `config.json` top-level or 1-deep `name`        | Script heading (e.g. "Script 16: phpMyAdmin") |
| `config.json` `desc` / `description`            | "Description" line                             |
| `config.json` `chocoPackage` / `chocoPackageName` | "Choco package" line                         |
| `config.json` `validModes`         | "Valid Modes" line under mode mappings         |
| `config.json` `defaultMode`        | "Default Mode" line under mode mappings        |
| `install-keywords.json` `keywords` | Per-script keyword list + Combo Keywords table |
| `install-keywords.json` `modes`    | Per-script Mode Mappings table                 |

Subcommand-style keyword targets (`"os:clean"`, `"profile:base"`, etc.) are
collected separately into a "Subcommand Keywords" section -- they don't
correspond to numeric script IDs in the registry.

### Why CommonJS (`.cjs`)

The repo's `package.json` declares `"type": "module"`, so `.js` files would
be parsed as ESM. This script uses `require()` for synchronous file IO and
zero-dependency simplicity, so it lives as `.cjs`.
