# Release Pipeline

## Overview

`release.ps1` packages project assets into a versioned ZIP archive under the `.release/` directory. The version is read from `.gitmap/release/latest.json`.

## Output

```
.release/dev-tools-setup-v<version>.zip
```

## Contents of the ZIP

| Item               | Type      | Description                              |
|--------------------|-----------|------------------------------------------|
| `scripts/`         | Directory | All numbered script folders + shared/    |
| `run.ps1`          | File      | Root dispatcher                          |
| `bump-version.ps1` | File      | Version bump utility                     |
| `readme.md`        | File      | Project readme                           |
| `LICENSE`          | File      | License file                             |
| `changelog.md`     | File      | Changelog                                |

## Parameters

| Parameter  | Type   | Description                                      |
|------------|--------|--------------------------------------------------|
| `-Force`   | Switch | Overwrite an existing ZIP for the same version    |
| `-DryRun`  | Switch | Preview what would be packaged without creating   |

## Usage

```powershell
# Build release ZIP for current version
.\release.ps1

# Preview contents without creating ZIP
.\release.ps1 -DryRun

# Overwrite existing ZIP
.\release.ps1 -Force
```

## Workflow

1. Reads version from `.gitmap/release/latest.json`
2. Creates `.release/` directory if missing
3. Stages `scripts/`, `run.ps1`, `bump-version.ps1`, `readme.md`, `LICENSE`, `changelog.md` into a temp directory
4. Compresses staged files into `dev-tools-setup-v<version>.zip`
5. Reports file count and ZIP size
6. Cleans up the staging directory

## Notes

- Missing source files are skipped with a warning (not a failure)
- Existing ZIP for the same version is skipped unless `-Force` is used
- The `.release/` folder should be added to `.gitignore`

---

## CI: Registry Summary Drift Detection (since v0.40.3)

`.github/workflows/release.yml` runs an additional **drift check** step on every tag push, after the version-alignment check and before the ZIP build:

1. Hashes the committed `spec/script-registry-summary.md`.
2. Runs `node scripts/_internal/generate-registry-summary.cjs` (overwrites the file in the runner workspace only).
3. Hashes the regenerated file and compares to the original.
4. If hashes differ, the release **fails** with a `::error` annotation, prints the full `git diff` of what changed, and refuses to publish the GitHub Release.

This guarantees `spec/script-registry-summary.md` can never silently drift from `scripts/registry.json` + per-script `config.json`. To recover from a failed drift check:

```powershell
node scripts/_internal/generate-registry-summary.cjs
git add spec/script-registry-summary.md
git commit -m "Refresh script-registry-summary"
# Then re-tag.
```

`bump-version.ps1` runs the same generator locally on every version bump, so a normal release flow never trips this gate.
