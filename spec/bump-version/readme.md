# Spec: Bump Version (bump-version.ps1)

## Overview

The root-level `bump-version.ps1` updates the project version in
`scripts/version.json` -- the single source of truth for all scripts.
All scripts pick up the new version automatically via `Write-Banner`.

---

## Usage

```powershell
.\bump-version.ps1 -Patch            # 0.3.0 -> 0.3.1
.\bump-version.ps1 -Minor            # 0.3.0 -> 0.4.0
.\bump-version.ps1 -Major            # 0.3.0 -> 1.0.0
.\bump-version.ps1 -Set "2.0.0"     # Explicit version
.\bump-version.ps1                   # Show usage help
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Patch` | switch | No | Bump patch version (e.g. 0.3.0 -> 0.3.1) |
| `-Minor` | switch | No | Bump minor version, reset patch (e.g. 0.3.0 -> 0.4.0) |
| `-Major` | switch | No | Bump major version, reset minor and patch (e.g. 0.3.0 -> 1.0.0) |
| `-Set` | string | No | Set an explicit version string (must be `Major.Minor.Patch` format) |

When no parameter is provided, the script prints usage help and exits.

---

## Execution Flow

1. Read current version from `scripts/version.json`
2. Display current version
3. Calculate new version based on the flag provided
4. Validate format (must be `N.N.N`)
5. Skip if new version equals current version
6. Write updated version to `scripts/version.json`
7. Update Changelog badge version in `readme.md` (if badge exists)
8. **Regenerate `spec/script-registry-summary.md`** by invoking
   `node scripts/_internal/generate-registry-summary.cjs` (skipped with a
   warning if Node is not on PATH -- bump still succeeds)
9. Display confirmation

---

## Validation

| Condition | Behaviour |
|-----------|-----------|
| `scripts/version.json` missing | `[ FAIL ]` and exit |
| `-Set` with invalid format (not `N.N.N`) | `[ FAIL ]` and exit |
| New version same as current | `[ SKIP ]` and exit |
| No flags provided | Show usage help and exit |

---

## Version Propagation

The version is consumed automatically by `Write-Banner` in
`scripts/shared/logging.ps1`. Every script that calls `Write-Banner -Title`
reads from `scripts/version.json` at runtime -- no per-script version
fields are needed.

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Single `version.json` source of truth | Eliminates version drift across 31+ scripts |
| No per-script version fields | Removed from all `log-messages.json` files; `Write-Banner` auto-loads |
| Explicit `-Set` validation | Prevents malformed version strings |
| Skip on same version | Avoids unnecessary file writes |
| Root-level placement | Easy to find alongside `run.ps1` |
