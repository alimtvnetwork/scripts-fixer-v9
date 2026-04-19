# Project Plan -- Dev Tools Setup

## Current Version: v0.38.0
## Last Updated: 2026-04-19

---

## 🔄 In Progress

_None._

## ⏳ Pending / Next Steps

### Bootstrap follow-ups
- [ ] Mirror CWD-aware target resolution in `install.sh` (currently still hardcoded to `$HOME/scripts-fixer`)
- [ ] Mirror `-DryRun` as `--dry-run` in `install.sh`
- [ ] End-to-end verify install.ps1 from D:\, C:\Users\X, C:\Windows\System32 (fallback), and inside an existing checkout

### Documentation & Quality
- [ ] Verify `-Version` flag end-to-end on real Windows + Linux shells
- [ ] Verify auto-discovery redirect with a real `vN+1` sibling repo
- [ ] Update changelog v0.26.0 entry to include speed filter (added after version bump)
- [ ] Verify 4-filter chain re-indexing works correctly end-to-end
- [ ] Verify catalog column alignment with Speed column across all 81 models

### Future Features (Not Started)
- [ ] GUI/TUI for the interactive menu
- [ ] Cross-machine settings sync via cloud storage
- [ ] Linux/macOS support for the actual install scripts (bootstrap already cross-platform)
- [ ] New tool scripts (Docker, Rust)
- [ ] Model catalog auto-update from Hugging Face trending
- [ ] Parallel model downloads (aria2c batch mode)
- [ ] Model integrity verification (SHA256 checksums in catalog)

---

## ✅ Completed

### v0.38.0 (2026-04-19)
- [x] `install.ps1` CWD-aware target resolution (CWD\scripts-fixer when safe, sibling reuse, USERPROFILE fallback for protected dirs/drive roots)
- [x] `install.ps1` final action changed: launches `.\run.ps1` with no args (was `-d` straight into Install All Dev Tools)
- [x] New helpers `Test-CwdIsSafe` + `Resolve-TargetFolder` with reason-tagged `[LOCATE]` logging

### v0.37.1 (2026-04-19)
- [x] `-DryRun` flag for `install.ps1` — magenta `[DRYRUN] ... (skipped)` lines for every mutating step

### v0.37.0 (2026-04-19)
- [x] `install.ps1` + `install.sh` self-relocation flow (cd-out, TEMP staging fallback, `[GIT]` URL log)
- [x] Stderr-noise fix (no more red `NativeCommandError` on successful clones)

### v0.36.0 (2026-04-18)
- [x] `-Version` / `--version` diagnostic flag for `install.ps1` + `install.sh`
- [x] Bumped default probe range from current+20 → current+30 in installers and spec

### v0.35.0 (2026-04-18)
- [x] Bootstrap installers always wipe and fresh-clone `scripts-fixer` (Windows + Unix)
- [x] CODE RED file-path errors on remove/clone failures with recovery hints

### v0.34.0 / v0.34.1 (2026-04-17)
- [x] `models search <query>` — live Ollama Hub search with x-test-* regex parser
- [x] `models uninstall` — multi-backend (llama.cpp + Ollama) with multi-select + confirm
- [x] `-Force` flag for `models uninstall` (CI-friendly, skips yes/no gate)

### v0.31.0 - v0.33.0 (2026-04-17)
- [x] `spec/install-bootstrap/readme.md` documenting parallel-probe auto-discovery
- [x] Auto-discovery in `install.ps1` (Start-ThreadJob, sequential PS 5.1 fallback)
- [x] Auto-discovery in `install.sh` (`xargs -P 20` parallel HEAD probes)
- [x] `scripts/models/` orchestrator with `picker.ps1` + env-var handoff contract
- [x] Non-interactive CSV installs end-to-end across both backends

### v0.27.0 - v0.30.1
- [x] AI onboarding protocol (`.lovable/prompts/01-read-prompt.md`)
- [x] `overview.md`, `strictly-avoid.md`, `suggestions.md`, `prompt.md`
- [x] Dynamic dev-dir banner in `run.ps1`

### v0.23.x - v0.26.0
- [x] Scripts 42 (Ollama) + 43 (llama.cpp) with CUDA/AVX2 detection
- [x] 81-model GGUF catalog with 4-filter chain (RAM → Size → Speed → Capability)
- [x] `aria2c` accelerated downloads with fallback
- [x] `.installed/` tracking for models

### v0.16.x - v0.22.x
- [x] Audit, Status, Doctor commands
- [x] Scripts 37-41 (WT, Flutter, .NET, Java, Python libs)
- [x] Settings export system (NPP, OBS, WT, DBeaver)
- [x] Combo shortcuts (backend, full-stack, data-dev, mobile-dev)

---

## 🚫 Avoid / Skipped

| Item | Reason |
|------|--------|
| Split `spec/install-bootstrap/readme.md` into sub-files | Suggested but not approved by user — keep as single 224-line file |
| Modify `.gitmap/release/` folder | Hard rule from `strictly-avoid.md` #7 |

---

## Architecture Notes

- 43 PowerShell scripts in `scripts/` folder
- Shared helpers in `scripts/shared/` (logging, path-utils, choco-utils, etc.)
- External JSON configs per script (`config.json`, `log-messages.json`)
- `.installed/` tracking for idempotent installs
- `.resolved/` for runtime state persistence
- `settings/` folder for app config sync (NPP, OBS, WT, DBeaver)
- Spec docs in `spec/` folder per script
- Bootstrap installers (`install.ps1`, `install.sh`) auto-discover newer `scripts-fixer-vN` repos
