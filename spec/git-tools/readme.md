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

### `safe-all` -- Default wildcard mode

```powershell
.\run.ps1 gsa
```

- Adds `safe.directory='*'` to `~/.gitconfig` once (idempotent).
- One entry trusts all directories. Recommended for personal dev machines.
- Detects existing wildcard via `git config --global --get-all safe.directory`.

### `safe-all --scan <path>` -- Per-repo mode

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

## Flags

| Flag | Default | Notes |
|------|---------|-------|
| `--scan <path>` | (wildcard mode) | Switches to per-repo mode |
| `--depth <n>` | `4` | Max recursion depth in scan mode |

`--scan=<path>` and `--depth=<n>` (with `=`) are also accepted.

## Verification

```powershell
.\run.ps1 gsa
git config --global --get-all safe.directory   # includes '*'

.\run.ps1 gsa --scan C:\Users\Alim\GitHub
git config --global --get-all safe.directory   # now lists each repo
```

## Implementation notes

- `helpers/safe-all.ps1` snapshots existing `safe.directory` entries once
  before scanning to avoid N + 1 `git config` reads.
- Repo paths are stored with forward slashes (git's preferred form on Windows).
- Pre-flight check: bails with a clear error if `git` isn't on `PATH`
  (suggests `.\run.ps1 install git`).
- Logging via `Initialize-Logging -ScriptName "git-safe-all"` -- log written
  under `.logs/` like every other script.

## Related

- `scripts/07-install-git/` -- main git installer (LFS, GitHub CLI, gitconfig
  template). The default gitconfig template will be updated in Group E to
  include `safe.directory=*` out of the box for new installs.
