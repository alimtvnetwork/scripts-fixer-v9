# Changelog

All notable changes to this project are documented in this file.

## [v0.46.2] -- 2026-04-20

### Pinned: SHA256 integrity hashes for the 4 existing remote installers

Followed the v0.45.2 CODE RED integrity guard end-to-end and committed pinned `sha256` values into `scripts/shared/install-keywords.json` for every working `remote.*` entry. From this release onward, `.\run.ps1 install <pinned-keyword>` will refuse to execute the streamed body unless its hash matches the value below.

### Pinned values (verified 2026-04-20, Malaysia time)

| Key | URL | SHA256 (lowercase hex) | Body size |
|---|---|---|---|
| `clean-code` | `https://raw.githubusercontent.com/alimtvnetwork/coding-guidelines-v15/main/install.ps1` | `c045f55132171ba170c60af0d3b1671059c571bfcc293a7674c2e6a2635b8c42` | 14 672 B |
| `oh-my-posh` | `https://ohmyposh.dev/install.ps1` | `eae09e2ff6a7312b59507d26a5335550580fd8f8ea59334dc2a0a6026ae225ba` | 2 194 B |
| `scoop` | `https://get.scoop.sh` (-> `https://raw.githubusercontent.com/scoopinstaller/install/master/install.ps1`) | `48f6ea398b3a3fa26fae0093d37bd85b13e7eaa5d1d4a3e208408768408e35ae` | 26 292 B |

All three bodies are LF-only ASCII / UTF-8, so the raw-byte hash and the `[Encoding]::UTF8.GetBytes((Invoke-WebRequest).Content)` hash that `run.ps1` computes at line ~2359 produce identical digests. No byte-order-mark or line-ending normalization to worry about.

### Starship -- intentionally left UNPINNED

`remote.starship` was added in v0.45.0 with `url = https://starship.rs/install.ps1`. **That URL currently returns HTTP 404** -- Starship ships only `install.sh` (POSIX bash) in their repo (`install/install.sh` at `github.com/starship/starship`), and the official Windows install path documented at starship.rs is `winget install starship` / `scoop install starship`, not a piped PowerShell installer.

Rather than:
- pin a hash for a 404 (every future run would `[ FAIL ]` with "URL returned an empty body"), or
- silently rewrite the URL to point at a third-party `.ps1` we can't audit,

we set `remote.starship.sha256 = ""` and added a `_sha256_note` field explaining the situation. An empty pin disables the integrity check for that one entry only (run.ps1 already prints a yellow `(not pinned -- add 'sha256' to remote.starship in install-keywords.json to enable integrity check)` warning), and `doctor --self-check` section (d) will continue to flag the URL as `HTTP 404` until upstream is fixed or the entry is rewritten.

**Action item for future maintenance**: either replace `remote.starship` with a `winget install starship` wrapper script in this repo, or remove the entry. Tracking via `_sha256_note`.

### Maintenance procedure (also embedded in `install-keywords.json` -> `_pinMaintenanceNote`)

Refresh the pins **whenever an upstream installer publishes a new release, or at least quarterly**:

1. Download the body fresh:
   ```bash
   curl -fsSL <remote.<key>.url> -o /tmp/<key>.ps1
   ```
2. Compute the hash **exactly the way `run.ps1` does** -- UTF-8 bytes of the decoded text body:
   ```powershell
   $body  = (Invoke-WebRequest <url>).Content
   $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
   ([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes) `
     | ForEach-Object { $_.ToString("x2") }) -join ""
   ```
3. Paste the lowercase hex into the matching `remote.<key>.sha256` field in `scripts/shared/install-keywords.json`.
4. Update `_pinLastVerified` to today's date (`yyyy-MM-dd`, Malaysia time).
5. Bump `scripts/version.json` (patch).
6. Run `.\run.ps1 doctor --self-check` to confirm pins resolve and URLs return 200.

> **CODE RED rule**: Never commit a hash you didn't verify in the same session. A stale or guessed hash makes the integrity guard refuse every future run of that installer with `SHA256 mismatch -- refusing to execute unverified body`, and the user has no way to recover except editing the JSON.

### Files touched

- `scripts/shared/install-keywords.json` -- added `sha256` (3 pinned + 1 empty), `_pinMaintenanceNote`, `_pinLastVerified`, and `_sha256_note` for starship.
- `scripts/version.json` -- bumped `0.46.1` -> `0.46.2`.
- `changelog.md` -- this entry.

No PowerShell logic was changed; this release is data-only. The integrity guard at `run.ps1:2355-2380` and the unpinned-warning path at `run.ps1:2342` were both shipped in v0.45.2 and need no modification.

### Verification on Windows

```powershell
.\run.ps1 install clean-code   # expect: [  OK  ] SHA256 verified (c045f55...)
.\run.ps1 install oh-my-posh   # expect: [  OK  ] SHA256 verified (eae09e2...)
.\run.ps1 install scoop        # expect: [  OK  ] SHA256 verified (48f6ea3...)
.\run.ps1 install starship     # expect: yellow "(not pinned ...)" warning, then HTTP 404
.\run.ps1 doctor --self-check  # expect: section (d) -- 3 of 4 remote URLs green, starship FAIL HTTP 404
```

A negative test (tamper detection): edit any character of the upstream body locally, point the URL at a file://, or temporarily change the pinned hex by one nibble -- run.ps1 must abort with `SHA256 mismatch -- refusing to execute unverified body. Expected: <pinned>  Actual: <computed>  URL: <url>  Pin source: install-keywords.json -> remote.<key>.sha256`.

---

## [v0.46.1] -- 2026-04-20

### Added: `.\run.ps1 doctor --self-check` -- deep self-audit

> **Versioning note:** user requested `v0.45.2`, but the project is already at `v0.46.0`. Per the monotonic-version rule we ship as **v0.46.1** to preserve forward-only history.

A new `--self-check` flag on the existing `doctor` command runs four deep audits and prints a green/red `[ OK ]` / `[FAIL]` row per item, grouped by section, with a final tally. The original quick `doctor` (10 sanity checks, < 2 sec) is unchanged -- the flag opts into the deeper audit.

### Surface

```powershell
.\run.ps1 doctor                # 10 quick sanity checks (unchanged)
.\run.ps1 doctor --self-check   # deep audit (4 sections below)
```

Aliases accepted: `--self-check`, `-self-check`, `--selfcheck`, `selfcheck`, `self-check`.

### Audits performed

| # | Section | What it checks | How |
|---|---|---|---|
| (a) | `changelog` | Every `` `path/to/file.ext` `` reference in `changelog.md` resolves to a real file on disk | Regex `` `([A-Za-z0-9_./\\-]+\.(ps1|json|md|psm1|psd1))` ``, skips URLs / `%VAR%` / `~`-rooted paths, normalizes `/` -> `\` and joins with `$RootDir`. Each path becomes one row. |
| (b) | `version` | `scripts/version.json` matches the latest `## [vX.Y.Z]` header in `changelog.md` | Parses both, single row showing `version.json=vA.B.C  changelog=vX.Y.Z` -- green only when identical. |
| (c) | `clean` | Every `@{ Cat = ...; Bucket = ...; Helper = ... }` entry in `scripts/os/helpers/clean.ps1` has a matching `.ps1` file in `scripts/os/helpers/clean-categories/` | Regex-parses the catalog (no `Import-Module` needed), `Test-Path` each helper. One row per category. With v0.46.0's 49 categories, this section prints 49 rows. |
| (d) | `keyword` | Every entry in `install-keywords.json` -> `keywords` resolves to either a real registry script ID, an `os:<action>`, a `profile:<name>`, or a `remote:<key>` whose URL responds HTTP 200 | Builds a `validIds` set from `registry.json`, HEAD-probes every `remote.*` URL **once** with a 10s timeout (cached), then walks every keyword. `os:` and `profile:` targets are accepted by shape (resolved at runtime). Detail column shows `id 5, remote:starship 200, os:clean-vscode-cache`. |

### CODE RED file-path discipline

Every failure row includes the **exact path** that's missing or unreachable, e.g.:

```
[FAIL] clean    yarn-cache                              [F] MISSING: D:\proj\scripts\os\helpers\clean-categories\yarn-cache.ps1
[FAIL] keyword  starship                                remote:starship -> HTTP 503 for https://starship.rs/install.ps1
[FAIL] version  monotonic match                         version.json=v0.46.0  changelog=v0.45.2
```

### Output shape

```
  Doctor -- Self-Check (deep audit)
  =================================

  -- (a) Claimed files in changelog.md exist on disk
    [ OK ] changelog scripts/os/helpers/clean-categories/yarn-cache.ps1
    [ OK ] changelog scripts/os/run.ps1
    ...

  -- (b) version.json matches latest changelog header
    [ OK ] version  monotonic match                         version.json=v0.46.1  changelog=v0.46.1

  -- (c) os clean-categories: catalog vs helper files
    [ OK ] clean    recycle                                 [A] recycle.ps1
    [ OK ] clean    yarn-cache                              [F] yarn-cache.ps1
    ... (49 rows total)

  -- (d) install-keywords.json: keyword resolution
    [ OK ] keyword  vscode                                  id 1
    [ OK ] keyword  starship                                remote:starship 200
    ...

  Self-Check Summary: 187/187 OK

  All self-check rows green. Project is internally consistent.
```

### Why HEAD probes are run only once

The cache (`$remoteCache`) is built before walking the keywords list -- so `starship`, `ss`, and `starship-prompt` (3 keywords pointing at `remote:starship`) only generate one HTTP request, not three. Total network cost: 4 HEAD requests today (one per `remote.*` entry).

### Help surface

`.\run.ps1 -Help` now lists both modes:

```
    .\run.ps1 doctor                Quick health check of project setup
    .\run.ps1 doctor --self-check   Deep audit: changelog files, version match, clean catalog, keyword resolution
```

### Files

- `run.ps1`: new `Invoke-DoctorSelfCheck` function (~180 LOC) inserted directly after `Invoke-DoctorCommand`. Doctor dispatch block parses `--self-check` from `$Install` and routes accordingly. `Show-RootHelp` gains one extra line.
- `scripts/version.json`: 0.46.0 -> 0.46.1
- `changelog.md`: this entry

## [v0.46.0] -- 2026-04-20

### Added: OS Clean Phase 5 -- 5 dev-tool cache categories (49 total)

All five are **non-destructive cache-only** under Bucket F. Settings, projects, source code, installed CLIs, lockfiles, and credentials are NEVER touched. Each accepts `--dry-run` / `--yes` / `--days N` and uses the shared `_sweep.ps1` primitives (`Invoke-PathSweep`, `New-CleanResult`, `Set-CleanResultStatus`) -- zero duplication.

| Category | Targets | What it KEEPS | CLI invoked first |
|---|---|---|---|
| `yarn-cache` | `%LOCALAPPDATA%\Yarn\Cache\*`, `~\.yarn\berry\cache`, `~\.cache\yarn` | Project `node_modules`, lockfiles, `.yarnrc`, `yarn global add` packages | `yarn cache clean --all` (best effort, when CLI on PATH and not dry-run) |
| `bun-cache` | `~\.bun\install\cache`, `%LOCALAPPDATA%\bun-cache` | `~\.bun\bin` (the bun runtime + globally-linked CLIs), `bun.lockb` | `bun pm cache rm` (best effort) |
| `cargo-registry` | `~\.cargo\registry\cache`, `~\.cargo\registry\src`, `~\.cargo\git\checkouts`, `~\.cargo\git\db` | `~\.cargo\bin`, `config.toml`, `credentials.toml`, **registry\index** (re-syncing it costs minutes -- intentionally left alone) | none -- Cargo has no equivalent built-in command |
| `go-buildcache` | `GOCACHE` (default `%LOCALAPPDATA%\go-build`), `GOMODCACHE\cache\download` (default `~\go\pkg\mod\cache\download`) | `~\go\bin`, project source, `go.mod` / `go.sum`. Resolves paths via `go env GOCACHE` / `go env GOMODCACHE` when the CLI is on PATH (more accurate than guessing). | `go clean -cache` + `go clean -modcache` (best effort) |
| `maven-repo` | `~\.m2\repository`, `~\.m2\wrapper\dists` | `settings.xml`, `settings-security.xml`, project `pom.xml` / `target\`, the wrapper script itself | none -- Maven offers no whole-cache flush |

### CLI-first design

Where the upstream tool ships its own cache-cleaning command (Yarn, Bun, Go), we **invoke the official command first**, then run the path sweep to mop up anything the CLI missed (orphaned dirs, broken layouts, partial downloads). This is gated behind `if (-not $DryRun)` and `Get-Command <tool>` so the helpers stay safe on machines where the tool isn't installed and silent on dry-runs.

Cargo and Maven get pure path sweeps because their official tooling has no equivalent ("cargo doesn't ship a cache flush, Maven's `dependency:purge-local-repository` is per-project not global").

### Catalog wiring

- `scripts/os/run.ps1`: 5 entries appended to `$script:CleanCatalog` under Bucket F. Help banner now reads "Run all **49** cleanup categories".
- `scripts/os/helpers/clean.ps1`: catalog grew from 44 to 49; orchestrator synopsis bumped to `v0.46.0 -- 49 categories`.

### Subcommand surface

```powershell
.\run.ps1 os clean-yarn-cache --dry-run
.\run.ps1 os clean-bun-cache --dry-run
.\run.ps1 os clean-cargo-registry --dry-run
.\run.ps1 os clean-go-buildcache --dry-run
.\run.ps1 os clean-maven-repo --dry-run
.\run.ps1 os clean --bucket F --dry-run        # all 14 dev-tool categories now (was 9)
```

### Files

- `scripts/os/helpers/clean-categories/yarn-cache.ps1` (new)
- `scripts/os/helpers/clean-categories/bun-cache.ps1` (new)
- `scripts/os/helpers/clean-categories/cargo-registry.ps1` (new)
- `scripts/os/helpers/clean-categories/go-buildcache.ps1` (new)
- `scripts/os/helpers/clean-categories/maven-repo.ps1` (new)
- `scripts/os/run.ps1`: catalog +5, banner 44 -> 49
- `scripts/os/helpers/clean.ps1`: catalog +5, synopsis 44 -> 49
- `scripts/version.json`: 0.45.2 -> 0.46.0

## [v0.45.2] -- 2026-04-20

> **Note on version label:** the user requested "Bump to v0.44.1", but v0.44.1 is in the past (we shipped v0.45.0 + v0.45.1 earlier today). Per project memory ("version must monotonically increase"), this ships as **v0.45.2**. The integrity-check work the user asked for is delivered exactly as specified.

### Added: Optional SHA256 integrity pinning for remote installers

The `remote:` dispatch convention (introduced v0.44.0, expanded v0.45.0) now supports an optional `sha256` field per entry. When present, `run.ps1` **hashes the downloaded body BEFORE `Invoke-Expression` runs** and refuses to execute on mismatch.

#### Schema (in `scripts/shared/install-keywords.json`)

```jsonc
"remote": {
  "clean-code": {
    "url":    "https://raw.githubusercontent.com/alimtvnetwork/coding-guidelines-v15/main/install.ps1",
    "label":  "Coding Guidelines v15 (clean-code)",
    "sha256": "abc123...def"   // optional, lowercase hex, no separators
  },
  "starship":  { "url": "https://starship.rs/install.ps1",   "label": "..." },   // unpinned (existing behavior)
  "scoop":     { "url": "https://get.scoop.sh", "label": "...", "sha256": "..." }
}
```

The `_remoteComment` in the JSON now documents this schema in-place so future contributors don't need to read the changelog.

#### Runtime behavior

For each `remote:<key>` dispatch:

1. **Banner** prints `SHA256 : <hash> (pinned -- verified before exec)` when a hash is configured, or `SHA256 : (not pinned -- add 'sha256' to remote.<key> in install-keywords.json to enable integrity check)` in DarkYellow when it's missing. This makes pin status visible at a glance -- no silent unverified executions.
2. **Body fetched** via `Invoke-RestMethod -UseBasicParsing` (unchanged).
3. **Hash computed** via `[System.Security.Cryptography.SHA256]` over `UTF8.GetBytes($script)`, formatted as lowercase hex (matching `Get-FileHash`/`shasum -a 256` conventions). The SHA256 instance is `Dispose()`d.
4. **On match**: prints `[  OK  ] SHA256 verified (<hash>)` then proceeds to `Invoke-Expression`.
5. **On mismatch**: refuses to exec, prints a `[ FAIL ]` line containing **expected hash + actual hash + URL + the exact JSON path of the pin** (`install-keywords.json -> remote.<key>.sha256`) so the user knows where to update or audit -- CODE RED file-path discipline.
6. **On hash computation error**: also refuses to exec, surfaces the .NET exception message with the same `[ FAIL ]` envelope.

#### What's NOT changed

- Entries WITHOUT `sha256` keep working exactly as before (warning banner only). This is **opt-in pinning** -- breaking every existing call would be hostile when upstream installers (Starship, scoop) update frequently and pinning them requires per-release maintenance from the user.
- Failure paths still increment `$failCount`, success still increments `$successCount`, `Refresh-EnvPath` still runs after each remote dispatch.
- `--dry-run` semantics: remote installers don't have a dry-run mode (they're third-party), so the hash check still triggers on real fetches as before.

#### Why bytes-from-string vs bytes-from-stream

`Invoke-RestMethod` decodes the response body to a string before we see it. We re-encode as UTF-8 bytes for hashing. This matches what would happen if the user piped the same body through `Out-File -Encoding UTF8 | Get-FileHash`. If upstream serves bytes that don't round-trip through UTF-8 (extremely rare for `.ps1` text), the user can switch to `Invoke-WebRequest`+raw bytes -- noted as a future option but out of scope here.

#### Files

- `run.ps1`: `Resolve-InstallKeywords` captures `Sha256` field into the entry; remote dispatch branch now reads it, prints pin status, computes hash, refuses on mismatch.
- `scripts/shared/install-keywords.json`: `_remoteComment` updated to document the new optional `sha256` field. **No existing entries pinned** -- left to the user to populate per their threat model.
- `scripts/version.json`: 0.45.1 -> 0.45.2.

## [v0.45.1] -- 2026-04-20

> **Note on version label:** the user requested "Bump to v0.44.1", but v0.44.1 is in the past (we shipped v0.45.0 earlier today). Per project memory ("Code changes must bump at least minor version" -- treated here as "version must monotonically increase"), the change ships as **v0.45.1** instead. The discoverability work the user asked for is delivered exactly as specified.

### Added: `Show-RootHelp` + `Show-KeywordTable` "Remote installers" sections

The 4 remote installers shipped in v0.44.0 (`clean-code`) and v0.45.0 (`starship`, `oh-my-posh`, `scoop`) now show up in both top-level help surfaces so users can discover them via `.\run.ps1 -Help` and `.\run.ps1 -List`.

#### `.\run.ps1 -Help` (Show-RootHelp)

A new **"Remote installers (irm <url> | iex)"** block was inserted after the "Combine keywords" section and before the keyword table. Format mirrors the Database / Combine sections (Magenta header + DarkGray rows) and explicitly states **"All aliases on each row are EQUIVALENT -- pick whichever you remember."** so the equivalence is unmissable.

```
    Remote installers (irm <url> | iex):
      All aliases on each row are EQUIVALENT -- pick whichever you remember.

    install clean-code                          Coding Guidelines v15 -- alimtvnetwork/coding-guidelines-v15
    install code-guide  (= cg, cc)              Same as 'install clean-code' (4 aliases total)
    install coding-guidelines                   Same as 'install clean-code' (long alias)
    install starship    (= ss)                  Starship cross-shell prompt -- starship.rs/install.ps1
    install oh-my-posh  (= omp, posh)           Oh My Posh prompt -- ohmyposh.dev/install.ps1
    install scoop       (= sc)                  Scoop CLI installer -- get.scoop.sh

    Combine remote + local: install vscode,cg  (VS Code first, then clean-code)
```

#### `.\run.ps1 -List` (Show-KeywordTable)

A new **"Remote installers (irm | iex)"** group was inserted after "DevOps & Containers". The Script ID column reads `remote` (instead of a numeric script id) so users instantly see these dispatch through the `remote:` convention and not a local script.

| Keyword | Description | Script ID |
|---|---|---|
| `clean-code, cg, cc` | Coding Guidelines v15 | `remote` |
| `code-guide` | Coding Guidelines v15 (alias) | `remote` |
| `coding-guidelines` | Coding Guidelines v15 (alias) | `remote` |
| `starship, ss` | Starship cross-shell prompt | `remote` |
| `starship-prompt` | Starship (alias) | `remote` |
| `oh-my-posh, omp, posh` | Oh My Posh prompt theme | `remote` |
| `ohmyposh` | Oh My Posh (alias) | `remote` |
| `scoop, sc` | Scoop CLI installer | `remote` |
| `scoop-installer` | Scoop (alias) | `remote` |

### Files

- `run.ps1`: `Show-RootHelp` -- new "Remote installers" section after the Combine block.
- `run.ps1`: `Show-KeywordTable` -- new "Remote installers (irm | iex)" group after DevOps.
- `scripts/version.json`: 0.45.0 -> 0.45.1.

## [v0.45.0] -- 2026-04-20

Consolidated batch: OS Clean **Phase 4** (4 new dev-cache categories), `logs` subcommand **filter siblings** (`--grep` / `--since` / `--errors` / `--case-sensitive`), and **3 new remote installers** (`starship`, `oh-my-posh`, `scoop`) wired through the `remote:` convention introduced in v0.44.0.

### Added: OS Clean Phase 4 -- 4 dev-tool cache categories (44 total)

All four are **non-destructive cache-only** -- settings, projects, source code, SDK packages, and credentials are NEVER touched. Each accepts `--dry-run` / `--yes` / `--days N` like every other category.

| Category | Targets | What it KEEPS |
|---|---|---|
| `vscode-extensions-cache` | `%USERPROFILE%\.vscode\extensions\<ext>\(cache\|.cache\|logs\|.logs\|tmp)`, `%APPDATA%\Code\(CachedExtensions\|CachedExtensionVSIXs\|logs\exthost*)` | Extension code, settings.json, keybindings, snippets, workspace state |
| `jetbrains-cache` | `%LOCALAPPDATA%\JetBrains\<Product><Ver>\(caches\|log\|tmp)` for IntelliJ/PyCharm/WebStorm/Rider/GoLand/CLion/PhpStorm/RubyMine/DataGrip + Toolbox cache | `config\` (settings, keymaps), project files. Indexes will rebuild on next IDE launch (intentional). |
| `android-studio-cache` | `%LOCALAPPDATA%\Google\AndroidStudio*\(caches\|log\|tmp)`, JetBrains-flavoured AndroidStudio dirs, `~\.android\cache`, `~\.android\avd\*\snapshots\` | SDK packages under `%LOCALAPPDATA%\Android\Sdk`, `config.ini`, `userdata-qemu.img` (only AVD snapshots get nuked, the AVDs themselves stay) |
| `gradle-cache` | `~\.gradle\(caches\|daemon\|.tmp\|native)`. Calls `gradle --stop` first when the CLI is on PATH and we're not in dry-run. | `gradle.properties`, `init.d\` scripts, the wrapper distribution itself, project-local `.gradle\` (left alone) |

#### Catalog wiring

- `scripts/os/run.ps1`: 4 entries added to `$script:CleanCatalog` under Bucket F. Help banner now reads "Run all **44** cleanup categories".
- `scripts/os/helpers/clean.ps1`: catalog grew from 40 to 44; orchestrator synopsis bumped to `v0.45.0 -- 44 categories`.
- Each helper sits next to the others in `scripts/os/helpers/clean-categories/`. The same `_sweep.ps1` primitives (`Invoke-PathSweep`, `New-CleanResult`, `Set-CleanResultStatus`) are reused -- zero duplication.
- `clean-jetbrains-cache` explicitly **skips** AndroidStudio* directories so the work isn't double-done with `clean-android-studio-cache`. Toolbox + Shared are also skipped (settings, not cache).

#### Subcommand surface

```powershell
.\run.ps1 os clean-vscode-extensions-cache --dry-run
.\run.ps1 os clean-jetbrains-cache --dry-run
.\run.ps1 os clean-android-studio-cache --dry-run
.\run.ps1 os clean-gradle-cache --dry-run
.\run.ps1 os clean --bucket F --dry-run        # all 9 dev-tool categories
```

### Added: `logs --grep` / `--since` / `--errors` / `--case-sensitive`

The `logs` subcommand introduced in v0.43.2 now supports four filter flags that **all compose**. `--tail` still defaults to 20.

#### Flags

- `--grep <pattern>` -- filters events whose `.message` matches the regex. Case-**insensitive** by default (typical user intent). The regex is compiled **once up front** with `New-Object System.Text.RegularExpressions.Regex` -- a malformed pattern fails fast with the exact `.NET` message instead of throwing per-event.
- `--case-sensitive` -- toggles `--grep` into case-sensitive mode (`RegexOptions.None`).
- `--since <duration>` -- only events newer than the cutoff. Accepted suffixes: `s`/`sec`/`second(s)`, `m`/`min`/`minute(s)`, `h`/`hr`/`hour(s)`, `d`/`day(s)`, `w`/`wk`/`week(s)`. Examples: `30m`, `1h`, `2d`, `1w`. Invalid duration fails fast with a `[ FAIL ]` listing accepted formats.
- `--errors` -- only `level=fail` / `level=warn` / `level=error`. **Also reads `.logs/*-error.json`** (which were skipped by default to avoid duplicates) so dedicated error logs are surfaced.

All filters apply BEFORE the global tail. The `(default tail 20)` label only appears when `--tail` was NOT passed; otherwise the header reads e.g. `logs --tail 50 --errors --grep 'locked' --since 1h`.

When zero events survive the filters, the empty-result banner echoes the active filter set so you can see what excluded everything (CODE RED visibility).

#### Implementation notes

- Three filters are independent flags but share one event collector loop -- no double-pass over `.logs/*.json`.
- Per-event identity stamping (v0.43.1) is honored: when `--errors` reads from `errors[]` and `warnings[]` arrays, each entry's own `projectVersion` / `invokedFrom` / `scriptName` win over the file header.
- Help block (`logs --help`) now lists every flag with one-line descriptions.

### Added: 3 new remote installers (`starship`, `oh-my-posh`, `scoop`)

Each gets a JSON entry under `remote.*` plus short and long aliases. All five (clean-code already wired in v0.44.0) use the same `irm <url> | iex` dispatch.

| Aliases | URL | Label |
|---|---|---|
| `starship`, `starship-prompt`, `ss` | `https://starship.rs/install.ps1` | Starship cross-shell prompt |
| `oh-my-posh`, `ohmyposh`, `omp`, `posh` | `https://ohmyposh.dev/install.ps1` | Oh My Posh prompt theming engine |
| `scoop`, `scoop-installer`, `sc` | `https://get.scoop.sh` | Scoop -- command-line installer for Windows |

```powershell
.\run.ps1 install starship
.\run.ps1 install omp
.\run.ps1 install scoop
.\run.ps1 install starship,omp,scoop      # chained -- runs in order
```

The dispatcher prints `Source: <url>` and `Command: irm <url> | iex` before executing so the literal one-liner is copy-pasteable for manual reruns. Failures (network down, 404, non-zero exit, empty body) are caught and reported with the URL + reason -- no stack traces.

### Skipped (with reason)

- **Unix `run.sh --version` mirror** -- not applicable: this project has no `run.sh`. `install.sh` already has its own `--version` mode (bootstrap version probe), and the local dispatcher is `run.ps1` only.
- **Windows-runtime verifications for v0.43.1 (per-event identity) and v0.43.2 (`logs --tail`)** -- these need a real Windows shell with populated `.logs/*.json`. The new `--errors` flag gives you a one-command audit: any v0.43.1+ event written under the new identity rule will show up via `.\run.ps1 logs --errors` with its own `projectVersion`/`invokedFrom` per line. See "Manual Windows verification" in the testing suggestions below.

## [v0.44.0] -- 2026-04-20

### Added (`install clean-code` remote installer)

New keyword family `install clean-code`, `install code-guide`, `install cg`, `install cc`, `install coding-guidelines` -- all four resolve to the **same** action: stream and execute the Coding Guidelines v15 installer from GitHub.

```powershell
# All four commands are equivalent:
.\run.ps1 install clean-code
.\run.ps1 install code-guide
.\run.ps1 install cg
.\run.ps1 install cc
```

Equivalent to running directly:

```powershell
irm https://raw.githubusercontent.com/alimtvnetwork/coding-guidelines-v15/main/install.ps1 | iex
```

#### Implementation

- New `remote` block in `scripts/shared/install-keywords.json` maps each remote key to a `{ url, label }` pair. Source of truth -- new remote installers are added by editing JSON, not code.
- `Resolve-InstallKeywords` (in `run.ps1`) now recognises `remote:<key>` string entries alongside the existing `os:<action>` / `profile:<name>` subcommand convention. Missing URLs fail loudly with the exact JSON path (CODE RED file-path discipline).
- New `Kind = "remote"` entries are sorted to run **after** script installs and subcommands -- so `install vscode,clean-code` installs VS Code first, then streams the remote guide.
- Dispatch uses `Invoke-RestMethod -UseBasicParsing` + `Invoke-Expression` (the canonical `irm | iex` pattern) wrapped in `try/catch`. Failures report URL + reason; empty bodies and non-zero `$LASTEXITCODE` are both treated as failures.
- Each remote dispatch prints `Source: <url>` and `Command: irm <url> | iex` before executing -- users can copy the literal one-liner for manual reruns.
- After execution `Refresh-EnvPath` is called so any tool the remote installer added to PATH is picked up by subsequent chained steps.

#### Notes

- Banner avoids em dashes / wide Unicode (terminal-banners memory rule).
- Aliases use the `is`/`has` boolean prefix convention throughout the new branch.

## [v0.43.2] -- 2026-04-20

### Added (`logs --tail` subcommand)

New root subcommand `.\run.ps1 logs --tail [N]` that prints the last N events (default 20) from every `.logs/*.json` file, grouped by `invokedFrom`, with `projectVersion` shown per group. Exits before any git pull or script dispatch -- safe in restricted shells.

#### Behaviour

- **Source**: scans `.logs/*.json` (skips `*-error.json` -- those events are duplicates already present in the main file).
- **Sort**: every event is parsed for `timestamp`, normalised to a sortable `[datetime]`, and the global tail is taken across ALL files (not per-file). This ensures the actual chronological tail is shown even when multiple scripts ran in parallel.
- **Grouping**: after tailing, events are grouped by `invokedFrom` and groups are ordered by their most-recent event timestamp (most recent group last).
- **Per-group header**: shows the invoking script path + the `projectVersion` of the latest event in the group. If the group spans multiple versions (e.g. logs from before and after a bump), the header reads `v<latest> (mixed: v0.43.0, v0.43.1)` so version drift is visible.
- **Per-event line**: `<timestamp 19-char>  [<level>]  <message>`, color-coded by level (ok=Green, fail=Red, warn=Yellow, skip=DarkGray, info=Cyan).
- **Backward compat**: events written before v0.43.1 (no per-event identity) fall back to the file-level `projectVersion` / `invokedFrom` / `scriptName` from the JSON header. Files older than v0.42.2 (no header identity either) fall back to `"unknown"` and the log filename.

#### Flags

- `--tail [N]` -- explicit tail length. `N` must parse as a positive int; otherwise default 20 is used.
- `--help` / `-h` / `help` -- prints usage and exits 0.
- Bare `.\run.ps1 logs` (no `--tail`) is treated as `--tail 20` and labelled `(default tail 20)`.

#### Implementation

- Added a `logs` short-circuit in `run.ps1` immediately after the `--version` short-circuit. Reads `Install` (the catch-all `ValueFromRemainingArguments`) for flag parsing.
- Wraps each `ConvertFrom-Json` in `try/catch`; corrupt or partial files emit a `[ WARN ]` line with the exact path + parse error reason (CODE RED file-path discipline) and processing continues.
- Missing `.logs/` directory or empty file set exits 0 with a friendly `[ INFO ]` message -- never throws.

### Bumped

- `scripts/version.json`: 0.43.1 -> 0.43.2.

> Note: requested as v0.43.0, but on-disk state is already v0.43.1 (per-event identity stamping landed in v0.43.1). Increment lands as **v0.43.2** (smallest forward step, semver forward-only).


## [v0.43.1] -- 2026-04-20

### Added (per-event identity stamping)

Every event written via `Write-Log` and `Write-FileError` in `scripts/shared/logging.ps1` now carries its own `projectVersion`, `invokedFrom`, and `scriptName` fields inside the `events[]` / `errors[]` / `warnings[]` arrays of `.logs/*.json`. This means a single grepped, split, or concatenated log line is still fully traceable to its origin script and version -- the file-level identity header (added in v0.42.2) is no longer the only source of truth.

#### Mechanism

- New module-scoped cache `$script:_LogIdentity` holds the resolved `{projectVersion, invokedFrom}` for the entire session.
- `Initialize-Logging` populates the cache once via `Get-LogIdentityFields` (wrapped in `try/catch`; falls back to `"unknown"` on resolution failure). The call stack is walked **only once per session** instead of once per event.
- `Write-Log` and `Write-FileError` now use `[ordered]@{}` event hashtables and append three identity fields after the existing payload:
  - `projectVersion` -- e.g. `"0.43.1"` (from `scripts/version.json`)
  - `invokedFrom` -- e.g. `"scripts/os/run.ps1"` (top-of-callstack `.ps1`, project-root-relative, forward slashes)
  - `scriptName` -- the sanitised log name from `Initialize-Logging` (e.g. `"os-clean"`), so events grouped by run are also self-labelled.
- `Save-LogFile` now reuses the cached identity instead of re-resolving it; the file-level header still includes the same fields in the same positions, so existing consumers see no breaking change.
- Both `Write-Log` and `Write-FileError` defensively re-resolve identity if the cache is empty (e.g. an event is logged before `Initialize-Logging` ran). Worst case, both fields read `"unknown"` -- never throws.

#### Backward compatibility

- File-level top fields (`projectVersion`, `invokedFrom`, `scriptName`, `status`, `startTime`, `endTime`, `duration`, `eventCount`, `errorCount`, `warnCount`, `events`, `errors`, `warnings`) keep their existing positions and meanings.
- Existing event fields (`timestamp`, `level`, `message`, plus `type`/`filePath`/`operation`/`reason`/`module`/`fallback` for file-errors) are unchanged. The three new identity fields are appended; consumers that read by name are unaffected.
- Old `.logs/*.json` files are not retroactively rewritten -- only events emitted from this run forward gain the per-event identity.

### Bumped

- `scripts/version.json`: 0.43.0 -> 0.43.1.

> Note: requested as v0.42.3, but on-disk state is already v0.43.0 (after the v0.43.0 audit + re-apply batch). Increment lands as **v0.43.1** (smallest forward step, semver forward-only).


## [v0.43.0] -- 2026-04-20

### Audit + consolidated re-apply

Audit of prior-session features showed the on-disk repo was at v0.42.2 but missing four claimed features. This release re-applies all of them in one batch and bumps to **v0.43.0**.

#### Audit result

| Feature | Claimed in | On disk before v0.43.0 | Action |
|---|---|---|---|
| Consent flags (`--consent-list`, `--consent-reset`) | v0.42.1 | Present | Kept |
| Self-identifying log files (`projectVersion`, `invokedFrom`) | v0.42.2 | Present | Kept |
| OS Clean Phase 3 (zoom, slack, teams, onedrive-cache) | v0.45.0 (claimed) | **Missing** | Added |
| Root `--version` / `-V` flag | v0.44.2 (claimed) | **Missing** | Added |
| Execution-policy bypass docs | v0.44.1 (claimed) | **Missing** | Added |
| Footer + no-warranty disclaimer | v0.43.0 (claimed) | **Missing** | Added |
| Versioned bootstrap installers | v0.43.0/v0.44.0 (claimed) | Present (`install.ps1`, `install.sh` already pin to `scripts-fixer-v8`) | Kept |

#### Added (Phase 3 OS Clean -- 4 new categories, all Bucket E, cache-only)

- **`scripts/os/helpers/clean-categories/zoom.ps1`** -- sweeps `%APPDATA%\Zoom\data\Cache`, `data\Logs`, `logs`, `Temp`, plus `%LOCALAPPDATA%\Zoom\Cache|GPUCache|Code Cache`. **NEVER** touches `data\zoomus.db` (account/contacts), local recordings, or saved chats.
- **`scripts/os/helpers/clean-categories/slack.ps1`** -- probes Squirrel install, MSIX install, and MS Store package (`91750D7E.Slack_8she8kybcnzg4`). Sweeps `Cache`, `Code Cache`, `GPUCache`, `logs`, `Service Worker\CacheStorage`. **NEVER** touches `Local Storage` (login token) or `IndexedDB` (message history).
- **`scripts/os/helpers/clean-categories/teams.ps1`** -- handles **both** Teams Classic (`%APPDATA%\Microsoft\Teams`, Electron) **and** New Teams (`%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\Default`, WebView2). Sweeps cache + GPU + service-worker cache + logs. **NEVER** touches auth or chat IndexedDB.
- **`scripts/os/helpers/clean-categories/onedrive-cache.ps1`** -- cleans `%LOCALAPPDATA%\Microsoft\OneDrive\logs`, `setup\logs`, `cache`, plus `StandaloneUpdater\*.tmp`. **Hard guard**: skips `$env:OneDrive` (synced files) entirely and notes the path in the report. Account binding under `settings\Personal\*.dat` is excluded.
- **Wiring**: catalog in `scripts/os/run.ps1` and `scripts/os/helpers/clean.ps1` updated. Aggregate count is now **40 categories** (was 36). Help banner and synopsis updated to reflect the new total.

#### Added (root `--version` / `-V` flag)

- **`run.ps1`**: short-circuit handler at the top of the dispatch block. Recognizes `--version`, `version`, and `-V` (capital, matched case-sensitively via `$MyInvocation.Line -cmatch '(^|\s)-V(\s|$)'` so it does not collide with the existing lowercase `-v` -> VS Code shortcut).
- Output prints: project version (from `scripts/version.json`), short + full git SHA, current branch, root path, readme URL, and the no-warranty disclaimer. Resolves git fields via `git rev-parse` + `git status --porcelain` inside `Push-Location $RootDir`; wrapped in `try/catch` so non-git checkouts still work (commit reads `no-git`). `(dirty)` tag appended when uncommitted changes are present.
- Exits **before** any git pull or script dispatch -- safe to call in restricted shells.

#### Added (PowerShell execution-policy bypass docs)

- **`readme.md`**: new top-level section between Quick Start and the script catalog. Documents three options the user can copy-paste:
  1. `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` (current session, no admin)
  2. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -d` (single invocation)
  3. `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force` (permanent, user scope, no admin)

#### Added (footer + disclaimer)

- **`readme.md`**: new "Disclaimer / no warranty" section. States the project is shared **AS IS, for fun, to save time on OS setup**, that scripts touch system-level state (registry, services, package managers, browser caches), and that the user is responsible for anything they change. Recommends `--dry-run` and `os clean -h` for inspection. Surfaces `.\run.ps1 --version` as the canonical way to identify the running build.
- The same disclaimer is printed by `.\run.ps1 --version` so the running version + warranty stance is visible in-terminal as well as in the repo.
- Version badge bumped from `v0.41.0` to `v0.43.0`. Quick Start now mentions `--version`.

### Bumped

- `scripts/version.json`: 0.42.2 -> 0.43.0.

### Notes

- Bootstrap installers (`install.ps1`, `install.sh`) already pin to `scripts-fixer-v8` and the version-check mode (`-Version` / `--version`) was already wired in a previous commit; no change needed for this release. Future per-release installers should continue to bump the embedded `$current = N` / `CURRENT=N` literal when the repo is forked into `scripts-fixer-v9`.
- Identity stamping in `.logs/*.json` (added in v0.42.2) is unchanged. New runs of the new categories also produce self-identifying logs.


## [v0.42.2] -- 2026-04-20

### Added (self-identifying log files)

- **`scripts/shared/logging.ps1` `Get-LogIdentityFields`**: new internal helper that resolves two identity fields once per `Save-LogFile` call:
  - **`projectVersion`** -- read from `scripts/version.json`. Falls back to `"unknown"` if the file is missing or unreadable, with a `warn`-level log entry containing the exact path and failure reason (CODE RED file-path discipline).
  - **`invokedFrom`** -- the top-of-callstack `.ps1` (the original script the user ran), resolved via `Get-PSCallStack` and expressed **relative to project root** with forward slashes (e.g. `scripts/os/run.ps1`, `run.ps1`, `scripts/45-install-docker/run.ps1`). Falls back to absolute path if the script lives outside the repo. Skips the logging file itself when walking the stack.
- **`Save-LogFile`** now stamps `projectVersion` and `invokedFrom` as the **first two top-level fields** of every payload it writes:
  - Main log: `.logs/<name>.json`
  - Error log: `.logs/<name>-error.json` (when errors / warnings / overall fail)
- Both payloads switched from `@{}` to `[ordered]@{}` so the identity fields appear at the top of the JSON, making logs scannable without parsing.
- Identity resolution is wrapped in `try/catch` -- failure to resolve never aborts log writing. Worst case the fields read `"unknown"`.

### Behavior

- Existing `.logs/*.json` files are not retroactively rewritten; only new runs gain the fields.
- `eventCount`, `errorCount`, `warnCount`, `events`, `errors`, `warnings` retain their existing positions and contents -- no breaking change for any consumer that reads those fields by name.

### Bumped

- `scripts/version.json`: 0.41.0 -> 0.42.2.

> Note: requested as v0.43.1, but the on-disk project state was actually still at v0.41.0 (prior session bumps had not persisted). Increment lands as **v0.42.2** (smallest forward step from the last published changelog entry v0.42.1, semver forward-only).

## [v0.42.1] -- 2026-04-20

### Added

- `os clean --consent-list` and `os clean --consent-reset` flags (Phase 2 follow-up).

## [v0.42.0] -- 2026-04-20

### Added

- OS Clean Phase 2: `os clean-wsl`, `os clean-office`, `os clean-whatsapp`, `os clean-telegram`. All four wired into aggregate.

## [v0.41.0] -- 2026-04-20

### Added

- OS Clean Expansion: 32 categories total in aggregate; `recycle`, `ms-search`, `obs-recordings`, `windows-update-old` gated by first-run typed-yes consent persisted in `.resolved/os-clean-consent.json`.
