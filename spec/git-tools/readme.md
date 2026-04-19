# `git-tools` Subcommand

**Folder**: `scripts/git-tools/`
**Invocations**:
- `.\run.ps1 git-tools <action>`
- `.\run.ps1 gsa` (shortcut for `git-tools safe-all`)
- `.\run.ps1 git-safe-all` (long alias)

## Why this exists

Git on Windows often refuses to operate on a repo with:
```
fatal: detected dubious ownership in repository at 'C:/Users/.../some-repo'
```
This happens when the NTFS owner of the repo files doesn't match the current
user (common on shared drives, after copying from another machine, when WSL
touches a Windows path, etc.). The standard fix is to add the repo path to
`safe.directory` in the global gitconfig.

Doing this manually for 50+ repos is tedious. `gsa` automates it.

## Actions

The dispatcher supports 4 actions. Each can be invoked as a positional verb
(`gsa list`) or as an inline flag (`gsa --list`).

### 1. `safe-all` -- Default wildcard mode

```powershell
.\run.ps1 gsa
```

- Adds `safe.directory='*'` to `~/.gitconfig` once (idempotent).
- One entry trusts all directories. Recommended for personal dev machines.
- Detects existing wildcard via `git config --global --get-all safe.directory`.

### 2. `safe-all --scan <path>` -- Per-repo mode

```powershell
.\run.ps1 gsa --scan C:\Users\Alim\GitHub
.\run.ps1 gsa --scan D:\code --depth 6
```

1. Walks `<path>` recursively (default depth 4, override with `--depth N`).
2. Finds every `.git` folder.
3. For each, adds the parent repo path to `safe.directory` (idempotent --
   skips entries already present).
4. Prints summary: `Added 17 repos, 3 already present, scanned 20 .git folders in 0.4s`.

Use this in shared / locked-down environments where the `*` wildcard is too
permissive but you still want every existing repo trusted.

### 3. `list` (alias: `--list`, `audit`, `safe-list`) -- READ-ONLY audit

```powershell
.\run.ps1 gsa --list
.\run.ps1 git-tools list
```

- Reads `git config --global --get-all safe.directory`.
- Sorts and dedupes; reports duplicates removed.
- Splits wildcard (`*`) vs per-repo entries; reports counts of each.
- Prints every per-repo entry numbered, sorted, white-on-dark.
- Useful for auditing what's been trusted over time.
- Log written to `.logs/git-safe-list-<timestamp>.log`.

### 4. `remove <path>` (alias: `--remove`, `unset`, `safe-remove`) -- Idempotent unset

```powershell
.\run.ps1 gsa --remove C:\Users\Alim\old-repo
.\run.ps1 gsa --remove '*'                       # revoke wildcard trust
```

1. Snapshots `safe.directory` entries -> `$before`.
2. If `<path>` is not present, prints `[ SKIP ]` with the exact path and exits 0.
3. Otherwise runs `git config --global --unset-all safe.directory ^<regex-escaped-path>$`.
4. Snapshots again -> `$after`. Reports before / after / removed counts.

**Exact-match safety**: the value pattern is `[regex]::Escape($path)` wrapped
in `^...$`, so removing `C:/dev` will NOT also nuke `C:/dev/old-repo`.

Log written to `.logs/git-safe-remove-<timestamp>.log`.

### 5. `prune` (alias: `--prune`, `safe-prune`) -- Remove orphans

```powershell
.\run.ps1 gsa --prune --dry-run     # preview only
.\run.ps1 gsa --prune                # apply
```

1. Snapshots `safe.directory` entries.
2. Filters out the wildcard `'*'` (NEVER pruned -- it doesn't represent a path).
3. Tests every per-repo entry with `Test-Path -LiteralPath`.
4. Classifies as `alive` vs `orphan`.
5. Lists every orphan path (numbered) before deleting -- always shown so you
   can Ctrl+C if something looks wrong.
6. For each orphan, runs the same exact-match `git config --unset-all` as
   `--remove`.
7. Verifies post-prune count matches expected delta; warns on drift.
8. Reports before / after / orphans / alive counts.

**`--dry-run`**: lists orphans + counts, performs no `git config` writes.
Recommended first run after a big repo cleanup.

Log written to `.logs/git-safe-prune-<timestamp>.log`. Status:
- `ok` -- 0 orphans or all removed cleanly
- `partial` -- some unset failures (rare; usually concurrent gitconfig edit)
- `fail` -- git not on PATH

## Flags

| Flag             | Applies to       | Default          | Notes                                              |
|------------------|------------------|------------------|----------------------------------------------------|
| `--scan <path>`  | `safe-all`       | (wildcard mode)  | Switches to per-repo mode                          |
| `--depth <n>`    | `safe-all --scan`| `4`              | Max recursion depth                                |
| `--list`         | (action flag)    | -                | Same as positional `list`                          |
| `--remove <path>`| (action flag)    | -                | Same as positional `remove <path>`                 |
| `--prune`        | (action flag)    | -                | Same as positional `prune`                         |
| `--dry-run`      | `prune`          | off              | Preview orphans, no writes                         |

`--scan=<path>`, `--depth=<n>`, `--remove=<path>` (with `=`) are all accepted.

## Verification

```powershell
.\run.ps1 gsa                                   # add wildcard
.\run.ps1 gsa --list                            # confirm wildcard present, 0 per-repo
.\run.ps1 gsa --scan C:\Users\Alim\GitHub       # add per-repo
.\run.ps1 gsa --list                            # confirm wildcard + N repos

# Remove one
.\run.ps1 gsa --remove C:/Users/Alim/GitHub/old-project
.\run.ps1 gsa --list                            # confirm removed

# Delete a repo from disk, then prune
Remove-Item C:\Users\Alim\GitHub\old-project -Recurse -Force
.\run.ps1 gsa --prune --dry-run                 # confirm orphan listed
.\run.ps1 gsa --prune                           # remove
.\run.ps1 gsa --list                            # confirm gone
```

## Implementation notes

- `helpers/safe-all.ps1` snapshots existing `safe.directory` entries once
  before scanning to avoid N + 1 `git config` reads.
- `helpers/list-safe.ps1` is read-only -- never invokes `git config --add`
  or `--unset`.
- `helpers/remove-safe.ps1` and `helpers/prune-safe.ps1` both build the
  unset value-pattern via `^[regex]::Escape($path)$` for exact-match safety.
- `helpers/prune-safe.ps1` snapshots before + after and verifies the count
  delta matches the number of orphans removed; warns on drift.
- Repo paths are stored with forward slashes (git's preferred form on Windows).
  `Test-Path -LiteralPath` accepts forward slashes on Windows, so prune works
  without normalization.
- Pre-flight check (every helper): bails with a clear error if `git` isn't on
  `PATH` (suggests `.\run.ps1 install git`).
- Each action gets its own log file under `.logs/` for clean audit trails:
  `git-safe-all-*.log`, `git-safe-list-*.log`, `git-safe-remove-*.log`,
  `git-safe-prune-*.log`.

## Related

- `scripts/07-install-git/` -- main git installer (LFS, GitHub CLI, gitconfig
  template). Since v0.40.0, the default gitconfig template includes
  `safe.directory=*` out of the box for new installs.

