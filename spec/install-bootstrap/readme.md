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
