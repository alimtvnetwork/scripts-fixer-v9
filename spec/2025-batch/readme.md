# 2025 Batch -- New Commands, Tools, and Profiles

> Master index for the 2025 feature batch. Each numbered subdoc is a
> self-contained spec that another AI (or human) can implement in
> isolation. Implement in numeric order unless noted.

**Status**: spec only -- no code written yet.
**Target version**: v0.40.0 (minor bump per project rule).
**Created**: 2026-04-19 (Asia/Kuala_Lumpur, UTC+8).

---

## Decisions locked (from clarification round)

| Topic | Decision |
|-------|----------|
| Spec layout | One master spec (this file) + per-feature subdocs (`01-*.md` ... `12-*.md`) |
| Profile invocation | **Both** -- new keywords in `install-keywords.json` AND new `profile` subcommand |
| "OS dir" installs | Skip dev-dir prompt -- use Chocolatey default (`C:\ProgramData\chocolatey` shims, `C:\Program Files\<tool>`). No `--install-arguments` overrides. |
| ConEmu XML location | `settings/06 - conemu/ConEmu.xml` -- copied to `%APPDATA%\ConEmu\` after install. Mirrors notepad++ / obs / windows-terminal pattern. |
| `add-user` password | **Plain CLI args** (`add-user name pass [pin] [email]`). User accepted the security risk. Password is masked in console output but written to argv. |
| WhatsApp / OneNote | **Chocolatey desktop installers** -- no Microsoft Store, no winget Store source. `choco install whatsapp -y`, OneNote via Office or `choco install onenote -y` (fallback to download). |
| `git-safe-all` (`gsa`) | **Both modes** -- default = wildcard (`safe.directory = *`). `--scan <path>` flag = walk dir, add per-repo `safe.directory <full-path>` entries. |

---

## Subdoc index

| # | Subdoc | Script ID | Folder | Keywords |
|---|--------|-----------|--------|----------|
| 01 | `01-ubuntu-font.md` | 47 | `47-install-ubuntu-font` | `ubuntu-font`, `ubuntu.font` |
| 02 | `02-conemu.md` | 48 | `48-install-conemu` | `conemu`, `conemu+settings`, `conemu-settings` |
| 03 | `03-whatsapp.md` | 49 | `49-install-whatsapp` | `whatsapp`, `wa` |
| 04 | `04-os-clean.md` | n/a (subcommand) | `os/` dispatcher | `os clean` |
| 05 | `05-git-safe-all.md` | n/a (subcommand) | `git/` dispatcher | `git-safe-all`, `gsa` |
| 06 | `06-onenote.md` | 50 | `50-install-onenote` | `onenote` |
| 07 | `07-fix-long-path.md` | n/a (subcommand) | `os/` dispatcher | `fix-long-path`, `flp` |
| 08 | `08-add-user.md` | n/a (subcommand) | `os/` dispatcher | `os add-user` |
| 09 | `09-lightshot.md` | 51 | `51-install-lightshot` | `lightshot` |
| 10 | `10-hibernate-off.md` | n/a (subcommand) | `os/` dispatcher | `os hib-off` |
| 11 | `11-psreadline.md` | n/a | folded into Base profile | `psreadline` |
| 12 | `12-profiles.md` | n/a | new `profile/` dispatcher | `profile base`, `profile git-compact`, `profile advance`, `profile cpp-dx`, `profile small-dev` |

---

## New script registrations (scripts/registry.json)

```json
"47": "47-install-ubuntu-font",
"48": "48-install-conemu",
"49": "49-install-whatsapp",
"50": "50-install-onenote",
"51": "51-install-lightshot"
```

## New combo keywords (scripts/shared/install-keywords.json)

```json
"ubuntu-font":      [47],
"ubuntu.font":      [47],
"conemu":           [48],
"conemu+settings":  [48],
"conemu-settings":  [48],
"whatsapp":         [49],
"wa":               [49],
"onenote":          [50],
"lightshot":        [51],
"profile-base":     [14, 7, "vlc", "7zip.install", "winrar", 47, 33, 48, "googlechrome", 36],
"profile-git":      [7, 8],
"profile-advance":  ["profile-base", "profile-git", "wordweb-free", "beyondcompare", 36, 49, 1, 11],
"profile-cpp-dx":   ["vcredist-all", "directx", "directx-sdk"],
"profile-small-dev":["profile-advance", 6, 5, 3, 4]
```
*(IDs vs. string keys: existing infra is integer-only. Profile keywords need string-resolution support -- see `12-profiles.md`.)*

## New subcommand dispatchers

Two new top-level dispatchers under `scripts/`:

- `scripts/os/run.ps1` -- handles `os clean`, `os hib-off`, `os add-user`, `os flp`, `os fix-long-path`
- `scripts/git-tools/run.ps1` -- handles `gsa`, `git-safe-all`

Routed from `run.ps1` (root dispatcher) via new branches:
```powershell
if ($Command -eq "os")          { & "$PSScriptRoot\scripts\os\run.ps1" @Rest }
if ($Command -eq "git-safe-all" -or $Command -eq "gsa") { ... }
if ($Command -eq "profile")     { & "$PSScriptRoot\scripts\profile\run.ps1" @Rest }
```

## Implementation order (recommended)

1. **Spec review** -- this file + all 12 subdocs (current step). Sign-off required before any code.
2. **Group A -- Single-tool installers** (low risk, additive):
   - 01 ubuntu-font, 02 conemu, 03 whatsapp, 06 onenote, 09 lightshot
3. **Group B -- OS subcommands** (touches root dispatcher):
   - `os` dispatcher skeleton, then 04 clean, 07 flp, 08 add-user, 10 hib-off
4. **Group C -- Git tools**:
   - 05 git-safe-all
5. **Group D -- Profiles** (depends on A, B, C):
   - 12 profile dispatcher + 5 profile recipes
6. **Group E -- Polish**:
   - 11 psreadline (folded into Base, no separate script)
   - Default git config update (filter.lfs, safe.directory, url rewrite)
   - Spec update + memory update + version bump to v0.40.0

## Versioning

- Each Group merge bumps **patch** (v0.39.1, v0.39.2, ...).
- Final Group E merge bumps **minor** to **v0.40.0** with the full batch in changelog.
- Per user rule: code changes must bump at least minor version, but inside a single batch we use patches and bump minor at the close.

## Files this batch will create or modify

**Create:**
- `spec/2025-batch/readme.md` (this file) + `01-*.md` ... `12-*.md`
- `scripts/47-install-ubuntu-font/` (run.ps1, config.json, log-messages.json, helpers/)
- `scripts/48-install-conemu/` (run.ps1, config.json, log-messages.json, helpers/conemu.ps1, helpers/sync.ps1)
- `scripts/49-install-whatsapp/`
- `scripts/50-install-onenote/`
- `scripts/51-install-lightshot/`
- `scripts/os/run.ps1` + `scripts/os/helpers/{clean,hibernate,longpath,add-user}.ps1` + log-messages.json
- `scripts/git-tools/run.ps1` + `scripts/git-tools/helpers/safe-all.ps1` + log-messages.json
- `scripts/profile/run.ps1` + `scripts/profile/helpers/{base,git-compact,advance,cpp-dx,small-dev}.ps1` + config.json + log-messages.json
- `settings/06 - conemu/ConEmu.xml` (already copied)
- `settings/06 - conemu/readme.txt` (already created)
- `.lovable/memory/features/2025-batch.md`

**Modify:**
- `scripts/registry.json` (+5 entries)
- `scripts/shared/install-keywords.json` (+15 entries)
- `run.ps1` (root dispatcher: add `os`, `gsa`/`git-safe-all`, `profile` branches)
- `scripts/07-install-git/config.json` (add `[safe] directory = *`, `[filter "lfs"]`, `[url "ssh://git@gitlab.com/"]`)
- `.lovable/plan.md`, `changelog.md`, `scripts/version.json`

## Open questions (none -- all answered in clarification round)

If new questions surface during implementation of any subdoc, append them to that subdoc's "Open questions" section and ping the user.

---

See subdocs `01-*.md` through `12-*.md` for full implementation details.
