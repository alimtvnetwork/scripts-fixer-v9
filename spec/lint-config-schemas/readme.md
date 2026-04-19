# Spec: config.json Schema Linter (`scripts/_internal/lint-config-schemas.cjs`)

> **Status:** SHIPPED in v0.40.5.
> **Owner:** Alim Ul Karim
> **Wiring:** `bump-version.ps1` (suggested local pre-flight) + `.github/workflows/release.yml` (blocking CI gate).

---

## 1. Purpose

Audit every `scripts/<folder>/config.json` for:

- **Real bugs** that would crash a script at runtime (FAIL -- blocks release).
- **Drift / inconsistency** that maintainers should clean up over time (WARN -- non-blocking).

Acts as a structural safety net so `os clean`, `gsa --prune`, `os clean-clipchamp`, and the other 50+ scripts don't accidentally ship with a broken `defaultMode` or a `validModes` typo that would break a release.

---

## 2. Run it

```bash
node scripts/_internal/lint-config-schemas.cjs
```

Exit codes:

| Code | Meaning                                            | CI behavior              |
|------|----------------------------------------------------|--------------------------|
| `0`  | No FAIL rows. WARN rows are advisory.              | Release proceeds         |
| `1`  | One or more FAIL rows -- real schema bug.          | Release blocked          |
| `2`  | Linter crashed (bad JSON, missing files, etc.)     | Release blocked + diag   |

Set `NO_COLOR=1` to suppress ANSI colors. GitHub Actions annotations (`::warning file=...`, `::error file=...`) are emitted automatically when `$GITHUB_ACTIONS` is set, so each issue surfaces inline in the PR / tag run UI.

---

## 3. Rules

### R1a -- defaultMode-in-validModes consistency (FAIL)

If both `validModes` and `defaultMode` are set, `defaultMode` MUST appear in the `validModes` array. Otherwise `run.ps1 install <id>` would fall through with no matching mode and crash. Real bug; blocking.

### R1b -- validModes shape sanity (FAIL)

If `validModes` is set, it must be a non-empty array of non-empty strings. Object / null / mixed-type values catch typos like `"validModes": "choco,git"` (a string instead of an array).

### R1c -- name + desc are recommended (WARN, advisory)

`name` (or `label`) and `desc` (or `description`) are searched at top level AND one level deep inside any object value (project convention -- `phpmyadmin` block in `16-install-php` carries its own name/desc). If neither location has them, WARN.

NOT a FAIL: most installers happily run without these fields because the registry / folder name supplies the display string. Maintainers can add them at leisure for richer help output.

### R2 -- chocoPackage required when validModes contains "choco" (FAIL)

If a script declares it can run in `choco` mode but no `chocoPackage` (or `chocoPackageName`) is set anywhere (top OR 1-deep), the choco mode would have nothing to install. Real bug; blocking.

### R3 -- placeholder values + minimum name length (WARN)

When `name` / `desc` ARE present, they must:
- Not be `""`, `"TODO"`, `"FIXME"`, `"tbd"`, `"..."`, `"n/a"`, `"na"` (case-insensitive).
- `name` must be >= 3 characters.

Catches scaffolded configs that were never filled in.

### R4 -- unknown TOP-LEVEL SCALAR keys (WARN)

For installer-style scripts, any top-level scalar key (string / number / bool) NOT in the allowed schema is flagged. The allowed installer schema is:

```
_comment, enabled,
name, desc, description, label,
chocoPackage, chocoPackageName, verifyCommand, versionFlag,
validModes, defaultMode,
promptEdition, editions,
devDir
```

**Object values are tolerated** -- `phpmyadmin: {...}`, `tweaks: {...}`, `gitConfig: {...}` etc. are project-convention "feature blocks" and never warned. Only loose scalars like `"alwaysUpgradeToLatest": true` or `"installMethod": "..."` are flagged. Helps catch dead config from old refactors.

For dispatcher folders (`os`, `profile`, `audit`, `models`, `databases`, `12-install-all-dev-tools`), each has its own per-folder allowed-key list and any unknown key (scalar OR object) is flagged.

---

## 4. Schema discrimination

```
                                       config.json
                                            |
                                            v
                       +-----------------------------------+
                       | Folder in DISPATCHER_SCHEMAS map? |
                       +-----------------------------------+
                              /                        \
                            yes                         no
                            |                            |
                            v                            v
                  lintDispatcher(schema)        lintInstaller()
                  (R3 + per-folder R4)        (R1a/b/c + R2 + R3 + R4)
```

Dispatcher folders explicitly handled (each with its own allowed-keys list):
`os`, `profile`, `audit`, `models`, `databases`, `12-install-all-dev-tools`.

Folders WITHOUT a `config.json` (e.g. `git-tools`) are listed in an "informational" block at the bottom of the report -- never counted as failure.

---

## 5. Output format

```
  config.json schema lint
  =======================

  [  OK  ] 47-install-ubuntu-font
         [OK  ] [-]   all checks passed
  [ WARN ] 16-install-php
         [WARN] [R1c] no name / label found at top-level or in any 1-deep feature block
         [WARN] [R4]  unknown top-level scalar key: "alwaysUpgradeToLatest"
  [ FAIL ] 99-broken-example
         [FAIL] [R2]  validModes contains "choco" but no chocoPackage / chocoPackageName found

  Folders WITHOUT config.json (informational, not a failure):
    [ -- ] git-tools

  Summary
  -------
    Folders scanned    : 55
    With config.json   : 54
    OK                 : 29
    WARN               : 25
    FAIL               : 0

  Result: 25 folder(s) have WARN -- exiting 0 (release proceeds, fix at leisure).
```

Each finding line is also emitted as a GitHub Actions annotation when running under CI -- so `[ FAIL ]` rows surface as red ❌ in the workflow summary, `[ WARN ]` rows as yellow ⚠️.

---

## 6. CI integration (`.github/workflows/release.yml`)

The lint step runs immediately after the v0.40.3 registry-summary drift check, before the ZIP build:

```yaml
- name: Lint -- scripts/<folder>/config.json schemas
  shell: pwsh
  run: |
    & node scripts/_internal/lint-config-schemas.cjs
    if ($LASTEXITCODE -eq 1) {
        Write-Host "::error::config.json schema lint reported FAIL row(s) -- release blocked."
        exit 1
    }
```

Order:
1. Tag alignment (`scripts/version.json` matches tag)
2. Registry summary drift (v0.40.3)
3. **Schema lint (v0.40.5 -- this)**
4. Build ZIP
5. Smoke test (`run.ps1 -h` from extracted ZIP)
6. SHA256 checksum
7. Publish release

---

## 7. Local pre-flight

You can run the linter manually any time:

```bash
node scripts/_internal/lint-config-schemas.cjs
```

`bump-version.ps1` does NOT auto-invoke the linter (in contrast to the registry summary regenerator) because lint is a *check*, not a *generator* -- there's nothing to commit. Maintainers see CI catch it on push if they forget to fix locally.

If you want strict pre-commit enforcement, add this to `bump-version.ps1` (currently NOT enabled by default):

```powershell
& node (Join-Path $PSScriptRoot "scripts" "_internal" "lint-config-schemas.cjs")
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ FAIL ] schema lint failed -- aborting bump." -ForegroundColor Red
    exit 1
}
```

---

## 8. Current baseline (v0.40.5 snapshot)

```
Folders scanned : 55
With config.json: 54
OK              : 29
WARN            : 25
FAIL            :  0
```

The 25 WARN rows are advisory backlog -- mostly missing `name`/`desc` and unknown scalar keys (e.g. `alwaysUpgradeToLatest`, `installMethod`, `defaultVersion`). They can be cleaned up incrementally without bumping the lint threshold.

---

## 9. Extending the linter

Add a rule in 4 places:
1. `lintInstaller()` (or `lintDispatcher()`) -- emit a `findings` row with `severity` + `code` + `msg`.
2. The big rule comment at the top of the file -- explain the rule.
3. This spec section 3 -- document the rule for hand-off.
4. Decide severity: real-bug → FAIL, advisory → WARN.

Add an allowed top-level key for installers in `INSTALLER_ALLOWED_KEYS`.
Add a dispatcher folder in `DISPATCHER_SCHEMAS` with its own allowed-keys list.

---

## 10. Related

- `scripts/_internal/generate-registry-summary.cjs` -- sister tool. Generates `spec/script-registry-summary.md` from the same config.json sources. The linter's `R1a` (defaultMode-in-validModes) covers a class of bug the generator silently tolerates.
- `spec/release-pipeline/readme.md` -- CI workflow documentation. The schema lint step is documented there in the "Drift Detection" section.
- `scripts/_internal/readme.md` -- explains the role of `_internal/` maintenance scripts in general.
