# Spec: OS Clean Expansion (v0.41.0)

> **Status:** DRAFT -- awaiting sign-off on catalog + naming before implementation.
> **Target version:** v0.41.0
> **Owner:** Alim Ul Karim
> **Dependencies:** None (replaces / extends `scripts/os/helpers/clean.ps1` only).

---

## 1. Goals

1. Expand `os clean` from **9 steps** to **~25 categories** covering Windows housekeeping that Windows itself doesn't surface in Disk Cleanup.
2. Every category gets its own **flat top-level subcommand** (`os clean-<name>`) so it can be run in isolation.
3. `os clean` (no suffix) = run **every** category sequentially, with a single locked-files report at the end.
4. **First-run consent gate**: aggressive defaults, but the first `os clean` (and the first run of any destructive subcommand) prompts for `--yes`. Consent is persisted under `.resolved/os-clean-consent.json`. Subsequent runs skip the prompt.
5. **`--dry-run`** flag on every subcommand AND on `os clean`. Reports per-category byte counts + file counts + would-be-deleted paths, performs no writes.
6. Maintain the locked-file accumulator pattern from v0.39.6 (catch, don't crash; final `[ LOCKED FILES ]` section).

---

## 2. The Catalog (25 categories, 5 buckets)

Each row is a **separate top-level subcommand**. Bucket column is for documentation only -- there is no `os clean system` group command.

### Bucket A: System (8 categories)

| Subcommand                  | Path(s) wiped                                                                                              | Side effects                                                  |
|-----------------------------|-------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| `os clean-chkdsk`           | `C:\found.*\*.chk`                                                                                         | None                                                          |
| `os clean-dns`              | Runs `ipconfig /flushdns`                                                                                  | DNS lookups slower for 1-2 min                                |
| `os clean-recycle`          | Runs `Clear-RecycleBin -Force` for every drive                                                              | **UNRECOVERABLE** -- guarded by first-run consent             |
| `os clean-delivery-opt`     | `C:\Windows\SoftwareDistribution\DeliveryOptimization\Cache\*`                                              | None (cache rebuilds on next update)                          |
| `os clean-error-reports`    | `C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*` + `ReportQueue\*`                                    | Loses crash dumps for forensics                               |
| `os clean-event-logs`       | `wevtutil cl <each>` -- already in `os clean` step 7. Now also a standalone subcommand.                     | Loses Windows event history                                   |
| `os clean-etl`              | `C:\Windows\System32\LogFiles\WMI\*.etl` + `C:\Windows\Logs\*.etl`                                          | Loses ETW traces                                              |
| `os clean-windows-logs`     | `C:\Windows\Logs\CBS\*.log`, `C:\Windows\Logs\DISM\*.log`, `C:\Windows\Logs\WindowsUpdate\*.log`            | Loses servicing history                                       |

### Bucket B: User Shell (6 categories)

| Subcommand                  | Path(s) wiped                                                                                              | Side effects                                                  |
|-----------------------------|-------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| `os clean-notifications`    | `%LOCALAPPDATA%\Microsoft\Windows\Notifications\wpndatabase.db`                                             | Loses notification history; live notifications still work     |
| `os clean-explorer-mru`     | Registry: `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU`, `RecentDocs`, `TypedPaths`     | Loses File Explorer Run history + recent typed paths          |
| `os clean-recent-docs`      | `%APPDATA%\Microsoft\Windows\Recent\*`                                                                     | Empties Quick Access "Recent files"                           |
| `os clean-jumplist`         | `%APPDATA%\Microsoft\Windows\Recent\AutomaticDestinations\*` + `CustomDestinations\*`                      | Loses taskbar jump-lists                                      |
| `os clean-thumbnails`       | `%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db` + `iconcache_*.db`                              | First Explorer browse rebuilds cache (slow once)              |
| `os clean-ms-search`        | Stops `WSearch` service, deletes `C:\ProgramData\Microsoft\Search\Data\Applications\Windows\*.edb`, restart | **Search index rebuild can take HOURS** -- consent-gated      |

### Bucket C: Graphics / Web (3 categories)

| Subcommand                  | Path(s) wiped                                                                                              | Side effects                                                  |
|-----------------------------|-------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| `os clean-dx-shader`        | `%LOCALAPPDATA%\D3DSCache\*` + `NVIDIA\GLCache\*` + `NVIDIA\DXCache\*` + `AMD\DxCache\*`                    | First game launch recompiles shaders (slow once)              |
| `os clean-web-cache`        | `%LOCALAPPDATA%\Microsoft\Windows\INetCache\*` + `INetCookies\*` (cookies opt-in via `--cookies`)           | Logs out of some IE/Edge legacy auth                          |
| `os clean-font-cache`       | `%LOCALAPPDATA%\Microsoft\Windows\FontCache\*` (stops `FontCache` service first)                            | First app launch with custom fonts slow once                  |

### Bucket D: Browsers -- cache only, NEVER cookies/history/passwords (4 categories)

| Subcommand                  | Path(s) wiped                                                                                              | Side effects                                                  |
|-----------------------------|-------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| `os clean-chrome`           | `%LOCALAPPDATA%\Google\Chrome\User Data\<Profile>\Cache\*` + `Code Cache\*` + `GPUCache\*`                 | Re-downloads cached JS/CSS/images on next browse              |
| `os clean-edge`             | `%LOCALAPPDATA%\Microsoft\Edge\User Data\<Profile>\Cache\*` + `Code Cache\*` + `GPUCache\*`                | Same as Chrome                                                |
| `os clean-firefox`          | `%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2\*` + `startupCache\*`                                    | Same                                                          |
| `os clean-brave`            | `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\<Profile>\Cache\*` + GPU/Code variants               | Same                                                          |

### Bucket E: Apps -- caches only (4 categories, more later)

| Subcommand                  | Path(s) wiped                                                                                              | Side effects                                                  |
|-----------------------------|-------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| `os clean-clipchamp`        | `%LOCALAPPDATA%\Packages\Clipchamp.Clipchamp_*\LocalCache\*` + `TempState\*`                                | Drafts unaffected; export cache rebuilds                      |
| `os clean-vlc`              | `%APPDATA%\vlc\art\*` + `%APPDATA%\vlc\ml.xspf` (media library cache, NOT vlcrc settings)                  | Album art re-fetched on next play                             |
| `os clean-discord`          | `%APPDATA%\discord\Cache\*` + `Code Cache\*` + `GPUCache\*` (NOT `Local Storage` -- that has login state)  | None visible to user                                          |
| `os clean-spotify`          | `%LOCALAPPDATA%\Spotify\Storage\*` + `Browser\Cache\*` (NOT offline downloads)                              | Re-streams cached tracks once                                 |

### Bucket F: Dev tools (4 categories)

| Subcommand                  | Path(s) wiped                                                                                              | Side effects                                                  |
|-----------------------------|-------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| `os clean-vscode-cache`     | `%APPDATA%\Code\Cache\*` + `CachedData\*` + `Code Cache\*` + `GPUCache\*` + `logs\*`                       | Workspaces/extensions safe; VS Code cold-starts slower once   |
| `os clean-npm-cache`        | Runs `npm cache clean --force` if npm present                                                              | Re-downloads packages on next install                         |
| `os clean-pip-cache`        | Runs `pip cache purge` if pip present                                                                      | Same                                                          |
| `os clean-docker-dangling`  | Runs `docker system prune -f` (dangling images + stopped containers + unused networks)                     | Skipped if Docker not running                                 |

### Bucket G: Media -- age-gated (3 categories)

| Subcommand                          | Path(s) wiped                                                                                       | Default threshold | Side effects                  |
|-------------------------------------|------------------------------------------------------------------------------------------------------|-------------------|-------------------------------|
| `os clean-obs-recordings`           | `%USERPROFILE%\Videos\*.mkv` + `*.mp4` whose `LastWriteTime < (today - N days)`                     | N=30 (`--days N`) | **Permanently deletes user video files** -- consent-gated, double-prompt |
| `os clean-steam-shader`             | `<SteamLibrary>\steamapps\shadercache\*`                                                            | None              | First game launch recompiles  |
| `os clean-windows-update-old`       | `dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase`                                 | None              | Removes ability to uninstall past Windows updates |

**Total: 32 subcommands across 7 buckets.** Some redundancy with existing `os clean` steps is intentional -- e.g. `os clean-event-logs` lets you wipe just event logs without touching anything else.

---

## 3. Aggregate command: `os clean`

Runs **every subcommand** in catalog order (Bucket A → Bucket G), then prints:
- Per-category result row (count, bytes freed, locked, status).
- Grand total bytes / files / locked.
- Single deduped `[ LOCKED FILES ]` section.

### Flags on `os clean`

| Flag                  | Effect                                                                                  |
|-----------------------|-----------------------------------------------------------------------------------------|
| `--yes`               | Skip first-run consent prompt. Required first time, optional after consent persisted.    |
| `--dry-run`           | Report only. No deletions, no service stops, no `docker prune`, no `dism` invocation.   |
| `--skip <cat,cat>`    | Skip listed categories. E.g. `--skip recycle,ms-search,obs-recordings`.                  |
| `--only <cat,cat>`    | Run only listed categories. (Sugar -- equivalent to running each subcommand in order.)   |
| `--bucket <A|B|...>`  | Run only one bucket. E.g. `--bucket D` = all browser caches.                             |
| `--days <N>`          | Override age threshold for media subcommands (default 30).                               |

### First-run consent (`.resolved/os-clean-consent.json`)

```jsonc
{
  "version": 1,
  "consentedAt": "2026-04-19T14:32:00+08:00",
  "consentedFor": ["recycle", "ms-search", "obs-recordings"],
  "machineName": "ALIM-DESKTOP"
}
```

- File missing OR consent list missing a destructive category → prompt with category name + side-effect summary, require typed `yes` (not just Enter).
- `--yes` writes the consent file the first time, then is honored on subsequent runs.
- `--dry-run` never writes the consent file (lets users explore safely).

### Destructive categories (require explicit consent every machine, first run only)

1. `recycle` -- unrecoverable file deletion
2. `ms-search` -- multi-hour rebuild
3. `obs-recordings` -- user video files
4. `windows-update-old` -- removes Windows rollback option

Non-destructive categories (no consent prompt, just `--yes` to skip the standard "Continue? [y/N]" gate which still applies to `os clean` as a whole the first time):

- All cache-only subcommands (browsers, dev tools, app caches, shader caches, font cache, web cache).

---

## 4. File / module layout

```
scripts/os/
├── run.ps1                          # dispatcher (UPDATED: routes 32 new actions)
├── config.json                      # paths catalog (UPDATED: 25+ new path entries)
├── log-messages.json                # (UPDATED: 60+ new strings)
└── helpers/
    ├── _common.ps1                  # (UPDATED: + Resolve-CleanPath, + Test-Consent, + Save-Consent, + Invoke-DryRunReport)
    ├── clean.ps1                    # (UPDATED: now an orchestrator -- calls every clean-* helper in order)
    ├── temp-clean.ps1               # unchanged
    ├── hibernate.ps1                # unchanged
    ├── longpath.ps1                 # unchanged
    ├── add-user.ps1                 # unchanged
    ├── choco-clean.ps1              # unchanged
    └── clean-categories/            # NEW directory -- 32 helpers, one per category
        ├── chkdsk.ps1
        ├── dns.ps1
        ├── recycle.ps1
        ├── delivery-opt.ps1
        ├── error-reports.ps1
        ├── event-logs.ps1
        ├── etl.ps1
        ├── windows-logs.ps1
        ├── notifications.ps1
        ├── explorer-mru.ps1
        ├── recent-docs.ps1
        ├── jumplist.ps1
        ├── thumbnails.ps1
        ├── ms-search.ps1
        ├── dx-shader.ps1
        ├── web-cache.ps1
        ├── font-cache.ps1
        ├── chrome.ps1
        ├── edge.ps1
        ├── firefox.ps1
        ├── brave.ps1
        ├── clipchamp.ps1
        ├── vlc.ps1
        ├── discord.ps1
        ├── spotify.ps1
        ├── vscode-cache.ps1
        ├── npm-cache.ps1
        ├── pip-cache.ps1
        ├── docker-dangling.ps1
        ├── obs-recordings.ps1
        ├── steam-shader.ps1
        └── windows-update-old.ps1
```

### Per-category helper contract

Every `clean-categories/<name>.ps1` exports nothing (script-mode), but follows a strict signature so the orchestrator can compose them:

```powershell
param(
    [switch]$DryRun,
    [switch]$Yes,
    [int]$Days = 30,    # only used by media subcommands
    [object]$Config,    # passed in by orchestrator OR loaded if invoked standalone
    [object]$LogMessages
)

# Returns a [hashtable] with the SAME shape every other category uses:
# @{
#   Category    = "chkdsk"
#   Label       = "Chkdsk file fragments"
#   Bucket      = "A"
#   Destructive = $false
#   Count       = 0          # files actually deleted (0 in dry-run)
#   WouldCount  = 0          # files that would be deleted (populated in dry-run)
#   Bytes       = 0          # actually freed
#   WouldBytes  = 0          # would be freed
#   Locked      = 0
#   LockedDetails = @()      # array of @{ Path = ...; Reason = ... }
#   Status      = "ok"|"warn"|"skip"|"fail"|"dry-run"
#   Notes       = @()        # human-readable hints (e.g. "Service WSearch was stopped")
# }
```

The orchestrator (`clean.ps1`) calls each helper in catalog order, accumulates the hashtables into `$results`, and prints the standard summary block + locked-file section.

When a user calls a single subcommand directly (`os clean-chrome`), the dispatcher calls the same helper with `$Config` / `$LogMessages` loaded inline, then prints a **single-row** summary block.

---

## 5. Dispatcher (`scripts/os/run.ps1`)

Add 32 new switch arms. Each arm is one line:

```powershell
{ $_ -in @("clean-chrome", "cleanchrome") } {
    & (Join-Path $scriptDir "helpers\clean-categories\chrome.ps1") @Rest
    exit $LASTEXITCODE
}
```

`os --help` (and `os clean --help`) gets a new section listing every subcommand grouped by bucket with a one-line description.

---

## 6. Keywords (`scripts/shared/install-keywords.json`)

No changes -- subcommands route via the `os` dispatcher, not via keyword IDs.

---

## 7. Logging

- Each subcommand writes to `.logs/os-clean-<category>-<timestamp>.log`.
- The orchestrator (`os clean`) writes to `.logs/os-clean-all-<timestamp>.log` AND each category's individual log.
- Locked-file detail rows are repeated in both the per-category log and the aggregate log.
- Dry-run logs are tagged with a `[DRY-RUN]` prefix on every line.

---

## 8. Test plan (post-implementation)

| # | Test                                                                                                 | Pass criteria                                                       |
|---|------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| 1 | `.\run.ps1 os clean --dry-run` on a fresh box                                                        | Reports 32 categories, 0 actual deletions, 0 consent file written   |
| 2 | `.\run.ps1 os clean-chrome` on a box with Chrome closed                                              | Wipes only Chrome cache; reports MB freed                            |
| 3 | `.\run.ps1 os clean-chrome` on a box with Chrome running                                             | Cache files locked → reported in [LOCKED FILES], no crash            |
| 4 | `.\run.ps1 os clean-recycle` first-run                                                               | Prompts for typed `yes`, refuses on Enter alone                     |
| 5 | After test 4 succeeds: `.\run.ps1 os clean-recycle` again                                            | Skips prompt (consent persisted)                                     |
| 6 | `.\run.ps1 os clean --skip recycle,ms-search,obs-recordings`                                         | Runs 29 categories, no destructive prompts                          |
| 7 | `.\run.ps1 os clean --bucket D`                                                                      | Runs only Chrome+Edge+Firefox+Brave                                 |
| 8 | `.\run.ps1 os clean-obs-recordings --days 7 --dry-run`                                               | Lists every .mkv/.mp4 older than 7 days under ~/Videos              |
| 9 | `.\run.ps1 os clean` aggregate                                                                       | Single locked-files section, deduped across categories              |
|10 | Re-run any subcommand twice                                                                          | Second run reports 0 bytes, 0 items (idempotent)                    |

---

## 9. Out of scope (deferred to v0.42.0+)

- Browser **cookies** / **history** / **saved passwords** -- explicitly excluded per user instruction.
- VS Code `workspaceStorage` (per-workspace state) -- valuable to some users; needs separate consent.
- Steam game cache (multi-GB per game) -- needs per-game selection UI.
- WhatsApp Desktop / Telegram cache -- can be added in v0.42.0 batch.
- Office cache (`%LOCALAPPDATA%\Microsoft\Office\<ver>\OfficeFileCache`) -- syncs to OneDrive, risky.
- WSL distros (`wsl --shutdown` + ext4 sparse trim) -- separate dispatcher (`os clean-wsl`) maybe v0.42.0.

---

## 10. Versioning

- Implementation lands as **v0.41.0** (minor bump -- new feature surface).
- `bump-version.ps1` will auto-regenerate `spec/script-registry-summary.md` (Subcommand Keywords section will grow from 25 to 57 entries).
- CI drift check (v0.40.3) catches any forgotten regen.

---

## 11. Open decisions (need user sign-off before code)

1. **Does the 32-category catalog match your intent?** Anything missing? Anything that should be merged or split?
2. **Bucket G -- `os clean-obs-recordings`**: this PERMANENTLY DELETES user video files older than 30 days. Are you sure you want this in `os clean` aggregate? Or should it be subcommand-only (never run by aggregate)?
3. **`os clean-ms-search`**: should this be in the aggregate? A multi-hour search rebuild might catch users off guard even with consent.
4. **`os clean-windows-update-old`**: same concern -- removes ability to uninstall recent Windows updates. Aggregate or subcommand-only?
5. **Naming**: `os clean-chrome` vs `os clean-browser-chrome` vs `os browser-clean chrome`? Flat is what you picked, but want to confirm the exact prefix.
6. **`os clean -h`**: should it print all 32 subcommands inline, or just a summary + "see `os --help` for full list"?
