# Spec: Install Bootstrap -- Auto-Discovery of Latest Repo Version

## Purpose

When a user pipes `install.ps1` (Windows) or `install.sh` (Unix/macOS) from a
specific versioned repository (e.g. `scripts-fixer-v5`), the bootstrap should
**transparently redirect to the newest published version** of the repo
(e.g. `scripts-fixer-v9`) instead of installing a stale generation.

This solves the problem of users sharing or bookmarking old one-liners and
unknowingly installing outdated code.

## Why this matters

The project is published as a **family of versioned repositories**:

```
github.com/<owner>/scripts-fixer-v1
github.com/<owner>/scripts-fixer-v2
...
github.com/<owner>/scripts-fixer-v7      <-- current
github.com/<owner>/scripts-fixer-v8      <-- not yet created
```

Each major generation lives in its own repo. A user who runs:

```
irm https://raw.githubusercontent.com/alimtvnetwork/scripts-fixer-v5/main/install.ps1 | iex
```

should not be locked into v5. The bootstrap must discover that v7 exists and
hand off to it.

---

## Algorithm

### 1. Parse the current invocation

Extract three values from the bootstrap's own clone URL (which is hardcoded
inside the script -- we do not need to inspect `$MyInvocation`):

| Value      | Example                  | Source                         |
|------------|--------------------------|--------------------------------|
| `owner`    | `alimtvnetwork`          | `$repo` URL                    |
| `baseName` | `scripts-fixer`          | repo name minus `-vN` suffix   |
| `current`  | `7`                      | trailing integer of repo name  |

If the repo name does **not** match `<base>-v<number>`, skip discovery and run
self (the user is on a fork or custom name).

### 2. Probe in parallel

For `N` in `current+1 .. current+30` (inclusive), send a parallel
**HTTP HEAD** request to:

```
https://raw.githubusercontent.com/<owner>/<baseName>-v<N>/main/install.ps1
```

(Use `install.sh` for the bash variant.)

- **Method**: `HEAD` -- lightweight, no body download
- **Timeout**: 5 seconds per request
- **Concurrency**: All 30 probes fire in parallel (PowerShell jobs / xargs -P)
- **Success criterion**: HTTP `200`
- **Probe range**: `current+30` (configurable via env var, see below)

### 3. Pick the highest

Of the probes that returned `200`, pick the **largest** `N`. That is the latest
published version.

- If no probes succeed → user is already on the latest, run self.
- If the highest is `current` itself → run self (no upgrade available).
- If the highest is `> current` → redirect.

### 4. Redirect (re-invoke)

Re-execute the same one-liner pattern but pointing at the new repo's
`install.ps1` / `install.sh`, then **exit**. The new bootstrap takes over.

Before redirect, set an environment variable to prevent infinite loops:

```
SCRIPTS_FIXER_REDIRECTED=1
```

The redirected bootstrap MUST check this env var at startup and skip its own
discovery step if set. This guarantees termination even if some future repo's
URL is briefly cached/stale.

### 5. Friendly logging

The user must see exactly what is happening:

```
  Scripts Fixer -- Bootstrap Installer

  [SCAN] Currently on v5. Probing v6..v25 for newer releases (parallel)...
  [FOUND] Newer version available: v7
  [REDIRECT] Switching to scripts-fixer-v7...

  Scripts Fixer -- Bootstrap Installer  (now running v7)
  ...
```

Or, when already current:

```
  [SCAN] Currently on v7. Probing v8..v27 for newer releases (parallel)...
  [OK] You're on the latest (v7). Continuing...
```

Or, when discovery is skipped:

```
  [SKIP] Auto-discovery disabled (-NoUpgrade flag).
```

---

## CLI / Env-var Controls

| Control                          | Effect                                              |
|----------------------------------|-----------------------------------------------------|
| `-NoUpgrade` (PowerShell)        | Skip discovery, run self                            |
| `--no-upgrade` (bash)            | Skip discovery, run self                            |
| `-Version` (PowerShell)          | Show current bootstrap + latest resolved, then exit   |
| `--version` (bash)               | Show current bootstrap + latest resolved, then exit   |
| `$env:SCRIPTS_FIXER_NO_UPGRADE=1`| Skip discovery (CI-friendly)                        |
| `$env:SCRIPTS_FIXER_PROBE_MAX=N` | Override probe range (default 30, max 100)          |
| `$env:SCRIPTS_FIXER_REDIRECTED=1`| Internal: prevents redirect loops, do not set      |

---

## Edge Cases

| Case                              | Behaviour                                          |
|-----------------------------------|----------------------------------------------------|
| Repo name has no `-vN` suffix     | Skip discovery, run self                           |
| All HEAD probes timeout/fail      | Run self with `[WARN] Discovery failed`            |
| Network completely offline        | Run self with `[WARN] Network unreachable`         |
| Highest found == current          | Run self with `[OK] You're on the latest`          |
| `SCRIPTS_FIXER_REDIRECTED=1` set  | Skip discovery (loop guard)                        |
| GitHub returns `429` (rate-limit) | Skip discovery, log warning, run self              |
| User passes `-NoUpgrade`          | Skip discovery, run self                           |

---

## Reference: PowerShell parallel HEAD probe

```powershell
$jobs = @()
foreach ($n in ($current + 1)..($current + $probeMax)) {
    $url = "https://raw.githubusercontent.com/$owner/$baseName-v$n/main/install.ps1"
    $jobs += Start-ThreadJob -ScriptBlock {
        param($u, $v)
        try {
            $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { return $v }
        } catch {}
        return $null
    } -ArgumentList $url, $n
}
$found = $jobs | Wait-Job | Receive-Job | Where-Object { $_ -ne $null }
$jobs | Remove-Job -Force
$latest = if ($found) { ($found | Measure-Object -Maximum).Maximum } else { $current }
```

If `Start-ThreadJob` is unavailable (Windows PowerShell 5.1 without the
`ThreadJob` module), fall back to `Start-Job` (slower but works) or sequential
HEAD requests with a tighter timeout.

## Reference: Bash parallel HEAD probe

```bash
probe_one() {
    local n=$1
    local url="https://raw.githubusercontent.com/$OWNER/$BASE-v$n/main/install.sh"
    if curl -fsI -m 5 "$url" >/dev/null 2>&1; then
        echo "$n"
    fi
}
export -f probe_one
export OWNER BASE
seq $((CURRENT + 1)) $((CURRENT + PROBE_MAX)) \
    | xargs -P 20 -I{} bash -c 'probe_one "$@"' _ {} \
    | sort -n | tail -1
```

---

## Redirect mechanics

### PowerShell

```powershell
$env:SCRIPTS_FIXER_REDIRECTED = "1"
$newUrl = "https://raw.githubusercontent.com/$owner/$baseName-v$latest/main/install.ps1"
Invoke-Expression (Invoke-WebRequest -Uri $newUrl -UseBasicParsing).Content
exit
```

### Bash

```bash
export SCRIPTS_FIXER_REDIRECTED=1
NEW_URL="https://raw.githubusercontent.com/$OWNER/$BASE-v$LATEST/main/install.sh"
curl -fsSL "$NEW_URL" | bash
exit 0
```

---

## Testing checklist

- [ ] Run from `scripts-fixer-v5` when only v5 exists → runs self
- [ ] Run from `scripts-fixer-v5` when v7 exists → redirects to v7
- [ ] Run from `scripts-fixer-v7` (latest) → runs self with "[OK] You're on the latest"
- [ ] Run from a fork named `my-fork` (no `-vN`) → runs self, no probes
- [ ] Run with `-NoUpgrade` → skips discovery
- [ ] Run with `-Version` / `--version` → prints version info and exits without cloning
- [ ] Run with `SCRIPTS_FIXER_REDIRECTED=1` preset → skips discovery (loop guard)
- [ ] Run offline → falls back to self with warning
- [ ] Probe takes < 3 seconds total when 20 versions are probed in parallel
- [ ] Friendly log output is visible and unambiguous at every step

---

## Release / Version Bump Checklist

When copying `install.ps1` and `install.sh` into a new `-vN` repository (e.g., `scripts-fixer-v8`), update these values before committing:

### install.ps1
- [ ] `$current = 7` → Bump to new version number (e.g., `$current = 8`)
- [ ] Verify `$repo` URL uses the correct `-v$current` suffix
- [ ] Test clone error handling works (check `$LASTEXITCODE` logic)

### install.sh
- [ ] `CURRENT=7` → Bump to new version number (e.g., `CURRENT=8`)
- [ ] Verify `REPO=` URL uses the correct `-v$CURRENT` suffix  
- [ ] Test clone error handling works (check `$?` exit code capture)

### readme.md (this repo)
- [ ] Update line 21 example from current version to new version
- [ ] Update line 31 example from current version to new version

### Critical reminders
- **Both** bootstraps MUST be bumped — a mismatch causes redirect loops or misleading banners
- Version numbers must be **integers**, not strings (for proper numeric comparison)
- Never commit the old version number to a new repo — users will see confusing "v7" banners when running from v8

---

## Self-Relocation Clone Flow (install.ps1 + install.sh)

> Both bootstraps implement the **same** self-relocation logic and the **same**
> stderr-noise fix. Keep them in sync when changing one — see test matrix.

### Problem

Two distinct failure modes when re-running the bootstrap one-liner:

1. **stderr-as-error noise** — `git clone` writes its progress (`Cloning into '...'`) to stderr. Using `2>&1` to merge streams in PowerShell promotes those lines to `RemoteException` records, which PowerShell prints in red as `NativeCommandError` even on a successful clone (exit 0).
2. **Folder is in use** — When the user runs the bootstrap from **inside** `C:\Users\X\scripts-fixer` (or from a parent that contains a `scripts-fixer` subfolder), `Remove-Item` may fail because the current shell is holding a handle on the directory.

### Fix

#### Stderr handling

Do NOT use `2>&1` to merge git's stream. Redirect stderr to a temp file:

```powershell
$errFile = [System.IO.Path]::GetTempFileName()
$stdout  = & git clone --quiet $repo $target 2>$errFile
$exit    = $LASTEXITCODE
$stderr  = Get-Content $errFile -Raw
Remove-Item $errFile -Force
```

Use `--quiet` to suppress most progress output. Only print `$stderr` when `$exit -ne 0`.

#### Self-relocation flow

Detect whether CWD is the target folder OR contains a `scripts-fixer` sibling:

```powershell
$cwdLeaf        = Split-Path (Get-Location).Path -Leaf
$isInsideTarget = ($cwdLeaf -ieq 'scripts-fixer')
$hasSibling     = Test-Path (Join-Path (Get-Location).Path 'scripts-fixer')
$needsRelocate  = $isInsideTarget -or $hasSibling
```

When `$needsRelocate`:

1. **`cd` to parent** if `$isInsideTarget` (releases handle on target dir).
2. **Try direct removal** of `$folder` with `Remove-FolderSafe` (clears read-only bits first, then `Remove-Item -Recurse -Force`).
3. If removal **succeeded** → clone directly into `$folder`.
4. If removal **failed** → clone into `$env:TEMP\scripts-fixer-bootstrap-<timestamp>`, then `Copy-Item` recursively into `$folder` (overwriting locked files in place where possible). Best-effort cleanup of temp staging.
5. **`cd` into `$folder`** and launch `run.ps1 -d`.

When **no conflict** detected → direct clone, no relocation noise.

### Logging contract

Every step logs with a tag and exact paths:

```
  [LOCATE] Current directory : D:\scripts-fixer
  [LOCATE] Target folder     : C:\Users\Administrator\scripts-fixer
  [LOCATE] You are INSIDE a 'scripts-fixer' folder -- using relocation flow.
  [CD]     Stepping out to parent  : D:\
  [CLEAN]  Removing existing folder: C:\Users\Administrator\scripts-fixer
  [OK]     Folder removed.
  [GIT]    Cloning from : https://github.com/alimtvnetwork/scripts-fixer-v8.git
  [GIT]    Cloning into : C:\Users\Administrator\scripts-fixer
  [OK]     Cloned successfully into C:\Users\Administrator\scripts-fixer
  [CD]     Entering              : C:\Users\Administrator\scripts-fixer
```

On lock fallback:

```
  [INFO] Direct removal failed -- will use TEMP staging fallback.
  [TEMP] Staging clone path  : C:\Users\X\AppData\Local\Temp\scripts-fixer-bootstrap-20260419-143022
  [GIT]  Cloning from : https://github.com/alimtvnetwork/scripts-fixer-v8.git
  [GIT]  Cloning into : <temp path>
  [OK]   Temp clone complete.
  [COPY] From : <temp path>
  [COPY] To   : C:\Users\X\scripts-fixer
  [OK]   Files copied into C:\Users\X\scripts-fixer
  [CLEAN] Temp staging removed.
```

### Test matrix

| Scenario                                                  | Expected flow                       |
|-----------------------------------------------------------|-------------------------------------|
| Fresh machine, no existing folder                         | Direct clone                        |
| Re-run from `C:\Users\X` (sibling exists, not inside)     | Remove sibling, direct clone        |
| Re-run from **inside** `C:\Users\X\scripts-fixer`         | cd .., remove, direct clone         |
| Re-run from inside, but folder is locked by another shell | cd .., remove fails, TEMP + copy    |
| Run from `D:\scripts-fixer` (different drive sibling name)| cd .., remove, direct clone         |
| Run from arbitrary folder (no conflict at all)            | Direct clone, no relocation logs    |

### Bash equivalents

The bash bootstrap mirrors the PowerShell flow exactly:

| Concern                        | PowerShell                              | Bash                                          |
|--------------------------------|-----------------------------------------|-----------------------------------------------|
| Stderr capture                 | `2>$errFile` + `Get-Content`            | `2>"$err_file"` (mktemp) + `sed`              |
| Quiet clone                    | `git clone --quiet`                     | `git clone --quiet`                           |
| Detect inside target           | `(Split-Path -Leaf) -ieq 'scripts-fixer'`| `[ "$(basename "$PWD")" = "scripts-fixer" ]` |
| Detect sibling                 | `Test-Path (Join-Path $cwd 'scripts-fixer')` | `[ -d "$PWD/scripts-fixer" ]`            |
| Remove                         | `Remove-FolderSafe` (clears RO bits)    | `remove_folder_safe` → `rm -rf`               |
| Temp dir                       | `$env:TEMP\scripts-fixer-bootstrap-<ts>`| `${TMPDIR:-/tmp}/scripts-fixer-bootstrap-<ts>`|
| Copy from temp                 | `Copy-Item -Recurse -Force`             | `cp -a "$TEMP_DIR/." "$FOLDER/"`              |
| Final action                   | `cd $folder; & .\run.ps1 -d`            | print `cd $FOLDER; pwsh ./run.ps1 -d`         |

The same `[LOCATE]`/`[CD]`/`[CLEAN]`/`[GIT]`/`[OK]`/`[INFO]`/`[TEMP]`/`[COPY]`/`[ERROR]`/`[WARN]` log tags are used in both scripts.
