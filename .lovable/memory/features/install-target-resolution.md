---
name: install-target-resolution
description: install.ps1 CWD-aware target folder resolution with safe fallback for protected dirs, and final launch is `.\run.ps1` no-args
type: feature
---

# install.ps1 target folder resolution (CWD-aware)

## Decision tree (in order, first match wins)

1. **CWD's leaf folder name == `scripts-fixer`** → target = **CWD itself**.
   The user re-ran the bootstrap from inside an existing checkout; clone
   back into the same path on the same drive. (`Reason = cwd-is-target`)
2. **CWD contains a `scripts-fixer` subfolder** → target = **that subfolder**.
   The user is one level above an existing checkout; refresh in place.
   (`Reason = cwd-has-sibling`)
3. **CWD is "safe"** (writable, not a protected/system path, not a drive root)
   → target = `<CWD>\scripts-fixer`. (`Reason = cwd-safe`)
4. **Otherwise** → fallback to `$env:USERPROFILE\scripts-fixer`.
   (`Reason = fallback-userprofile`)

## What counts as "unsafe" CWD (forces fallback)

- `$env:WINDIR` and any subpath (e.g. `C:\Windows\System32`)
- `$env:ProgramFiles`, `${env:ProgramFiles(x86)}`, `$env:ProgramData` and subpaths
- A drive root (e.g. `C:\`, `D:\`) — too noisy to drop a 100-script repo there
- Any path that fails a quick write-probe (`New-Item` of a temp file)

## Implementation

Two helpers in `install.ps1`:

- `Test-CwdIsSafe -Path <p>` → returns `$true` only when `<p>` is not protected,
  not a drive root, and passes a write-probe.
- `Resolve-TargetFolder -Cwd <c> -Fallback <f>` → returns
  `[pscustomobject]@{ Path; Reason; IsInside }`. The `IsInside` flag drives the
  later `cd ..` step (release file handle on the target dir before remove).

The static `$folder = Join-Path $env:USERPROFILE 'scripts-fixer'` is GONE.
It is now computed dynamically as `$resolved.Path` after CWD inspection.

## Logging

The `[LOCATE]` block prints one of four reason lines so the user always sees
WHY the target was chosen:

```
[LOCATE] Current directory : D:\
[LOCATE] Target folder     : D:\scripts-fixer
[LOCATE] CWD is writable -- cloning into <CWD>\scripts-fixer.
```

Or:
```
[LOCATE] Current directory : C:\Windows\System32
[LOCATE] Target folder     : C:\Users\X\scripts-fixer
[LOCATE] CWD is a protected/system path -- falling back to USERPROFILE.
```

## Final action change

After clone, the bootstrap now runs `& .\run.ps1` with **no arguments**
(was `& .\run.ps1 -d`). The user picks what to do from the dispatcher's own
menu/help instead of being thrown straight into "Install All Dev Tools".

## Why

- Previously, running from `D:\scripts-fixer` cloned into `C:\Users\X\scripts-fixer`,
  which was confusing and ignored the user's explicit drive choice.
- Auto-launching `.\run.ps1 -d` skipped the dispatcher menu, removing the user's
  ability to choose between scripts.
- Spec: `spec/install-bootstrap/readme.md` § "Self-Relocation Clone Flow" + new
  § "Target Folder Resolution".

## Bash mirror (v0.38.1)

Ported. `install.sh` now implements the same 4-step decision tree:

- `test_cwd_is_safe <path>` — write-probe via `touch`/`rm`, plus a deny-list
  for `/`, `/usr`, `/etc`, `/var`, `/bin`, `/sbin`, `/boot`, `/sys`, `/proc`,
  `/System`, `/Library`, `/Applications` (covers Linux + macOS system paths).
- `resolve_target_folder <cwd> <fallback>` — sets `TARGET`, `REASON`,
  `IS_INSIDE` globals.
- Reasons emitted: `cwd-is-target`, `cwd-has-sibling`, `cwd-safe`,
  `fallback-home` (note: `fallback-home`, not `fallback-userprofile`, since
  `$HOME` is the Unix-equivalent of `$env:USERPROFILE`).
- `--dry-run` flag mirrors PowerShell `-DryRun` and prints
  `[DRYRUN] <action>  (skipped)` for every mutating step.
- Final launch is `pwsh ./run.ps1` (no `-d`), same as PowerShell.
