---
name: install-self-relocation
description: install.ps1 + install.sh self-relocation flow when CWD is inside or contains scripts-fixer, plus stderr-noise fix
type: feature
---

# install.ps1 / install.sh self-relocation & stderr fix

## Two bugs combined

1. **Stderr noise** — `git clone` writes `Cloning into '...'` to stderr.
   - PowerShell: `2>&1` causes `NativeCommandError` (red text) even on exit 0.
     FIX: redirect stderr to a temp file (`2>$errFile`), use `--quiet`, only
     show stderr on `$LASTEXITCODE -ne 0`.
   - Bash: `2>&1 >/dev/null` previously hid useful diagnostics. FIX: capture
     stderr to `mktemp` file, use `--quiet`, print only on non-zero exit.

2. **Folder-in-use** — Running the bootstrap from inside
   `~/scripts-fixer` (or from a parent dir that contains a `scripts-fixer`
   subfolder) means `Remove-Item` / `rm -rf` may fail because the current
   shell holds a handle on the directory (Windows file locks; on Unix, edge
   cases like NFS, missing perms, or bind mounts).

## Required flow (both scripts, identical logic)

Detect: leaf of CWD is `scripts-fixer` OR a `scripts-fixer` subdir exists in CWD.

If detected:
1. `cd ..` when inside (releases handle).
2. Try safe removal (PS: clear read-only bits + `Remove-Item -Recurse -Force`;
   bash: `rm -rf`).
3. Success → direct clone into `$folder` / `$FOLDER`.
4. Failure → clone to TEMP staging dir
   (`$env:TEMP\scripts-fixer-bootstrap-<timestamp>` /
   `${TMPDIR:-/tmp}/scripts-fixer-bootstrap-<timestamp>`),
   then copy recursively into target. Best-effort cleanup of temp.
5. PS: `cd $folder` → `& .\run.ps1 -d`. Bash: print `cd` instructions to user.

If NOT detected → direct clone, no relocation logs.

## Logging tags (required, both scripts)

`[LOCATE]` `[CD]` `[CLEAN]` `[GIT]` `[OK]` `[INFO]` `[TEMP]` `[COPY]` `[ERROR]` `[WARN]`

Every log line must include the **exact path** involved (CODE RED rule).

## Implementation specifics

- PowerShell uses `Copy-Item -Recurse -Force` for the temp→target copy.
- Bash uses `cp -a "$TEMP_DIR/." "$FOLDER/"` — the trailing `/.` copies
  contents including dotfiles; `-a` preserves attributes.
- Both scripts use `--quiet` on `git clone` to minimize stderr.
- Both scripts log the exact source URL and target path BEFORE cloning.

## Why

- Users routinely re-run the one-liner from inside the cloned folder during
  testing — must not error out.
- Users on shared/locked filesystems may have file locks — must have a fallback.
- Spec: `spec/install-bootstrap/readme.md` § "Self-Relocation Clone Flow".
