<div align="center">

# Dev Tools Setup Scripts

**Automated Windows development environment configuration**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)](https://docs.microsoft.com/powershell/)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![Scripts](https://img.shields.io/badge/Scripts-51-green)](scripts/)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)
[![Changelog](https://img.shields.io/badge/Changelog-v0.40.5-orange)](changelog.md)

*One command to set up your entire dev environment. No manual installs. No guesswork.*

</div>

---

## Quick Start

### One-liner install (Windows)

```powershell
irm https://raw.githubusercontent.com/alimtvnetwork/scripts-fixer-v8/main/install.ps1 | iex
```

### One-liner install (Unix / macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/scripts-fixer-v8/main/install.sh | bash
```

### Manual clone

```powershell
git clone https://github.com/alimtvnetwork/scripts-fixer-v8.git scripts-fixer
cd scripts-fixer
```

```powershell
# Interactive menu -- pick what to install
.\run.ps1 -d

# Install everything with default answers (no prompts)
.\run.ps1 -d -D

# Install by keyword
.\run.ps1 install nodejs,pnpm
.\run.ps1 install python,git
.\run.ps1 install pylibs                # Python + all pip libraries in one go

# Install a specific tool by ID
.\run.ps1 -I 3          # Node.js + Yarn + Bun
.\run.ps1 -I 7          # Git + LFS + gh

# Shortcuts
.\run.ps1 -v             # VS Code
.\run.ps1 -a             # Audit mode
.\run.ps1 -w             # Winget
.\run.ps1 -t             # Windows tweaks

# Show all available scripts
.\run.ps1
```

---

## What It Does

A modular collection of **46 PowerShell scripts** that automate everything from installing VS Code, Git, and databases to configuring Go, Python, Node.js, Flutter, .NET, Java, C++, Rust, Docker, Kubernetes, and local AI tools (Ollama, llama.cpp) -- all from a single root dispatcher with an interactive menu and keyword install system.

### Core Tools (01-09, 16-17, 38-46)

| ID | Script | What It Does | Admin |
|----|--------|--------------|-------|
| 01 | **Install VS Code** | Install Visual Studio Code (Stable or Insiders) | Yes |
| 02 | **Install Chocolatey** | Install and update the Chocolatey package manager | Yes |
| 03 | **Node.js + Yarn + Bun** | Install Node.js LTS, Yarn, Bun, verify npx | Yes |
| 04 | **pnpm** | Install pnpm, configure global store | No |
| 05 | **Python** | Install Python, configure pip user site | Yes |
| 06 | **Golang** | Install Go, configure GOPATH and go env | Yes |
| 07 | **Git + LFS + gh** | Install Git, Git LFS, GitHub CLI, configure settings | Yes |
| 08 | **GitHub Desktop** | Install GitHub Desktop via Chocolatey | Yes |
| 09 | **C++ (MinGW-w64)** | Install MinGW-w64 C++ compiler, verify g++/gcc/make | Yes |
| 16 | **PHP** | Install PHP via Chocolatey | Yes |
| 17 | **PowerShell (latest)** | Install latest PowerShell via Winget/Chocolatey | Yes |
| 38 | **Flutter + Dart** | Install Flutter SDK, Dart, Android toolchain | Yes |
| 39 | **.NET SDK** | Install .NET SDK (6/8/9), configure dotnet CLI | Yes |
| 40 | **Java (OpenJDK)** | Install OpenJDK via Chocolatey (17/21) | Yes |
| 41 | **Python Libraries** | Install pip packages: ML, viz, web, jupyter (by group) | No |
| 42 | **Ollama** | Install Ollama for local LLMs, configure models directory | Yes |
| 43 | **llama.cpp** | Download llama.cpp binaries (CUDA/AVX2/KoboldCPP), GGUF models | Yes |
| 44 | **Rust** | Install Rust toolchain via rustup, clippy, rustfmt, rust-analyzer | Yes |
| 45 | **Docker Desktop** | Install Docker Desktop via Chocolatey, WSL2 check, Compose v2 | Yes |
| 46 | **Kubernetes Tools** | Install kubectl, minikube, Helm via Chocolatey | Yes |

### VS Code Extras (10-11) & Context Menus

| ID | Script | What It Does | Admin |
|----|--------|--------------|-------|
| 10 | **VSCode Context Menu Fix** | Add/repair VS Code right-click context menu entries | Yes |
| 11 | **VSCode Settings Sync** | Sync VS Code settings, keybindings, and extensions | No |
| 31 | **PowerShell Context Menu** | Add "Open PowerShell Here" (normal + admin) to right-click menu | Yes |

### Databases (18-29)

| ID | Script | What It Does | Admin |
|----|--------|--------------|-------|
| 18 | **MySQL** | Install MySQL -- popular open-source relational database | Yes |
| 19 | **MariaDB** | Install MariaDB -- MySQL-compatible fork | Yes |
| 20 | **PostgreSQL** | Install PostgreSQL -- advanced relational database | Yes |
| 21 | **SQLite** | Install SQLite + DB Browser for SQLite | Yes |
| 22 | **MongoDB** | Install MongoDB -- document-oriented NoSQL database | Yes |
| 23 | **CouchDB** | Install CouchDB -- Apache document database with REST API | Yes |
| 24 | **Redis** | Install Redis -- in-memory key-value store and cache | Yes |
| 25 | **Apache Cassandra** | Install Cassandra -- wide-column distributed NoSQL | Yes |
| 26 | **Neo4j** | Install Neo4j -- graph database for connected data | Yes |
| 27 | **Elasticsearch** | Install Elasticsearch -- full-text search and analytics | Yes |
| 28 | **DuckDB** | Install DuckDB -- analytical columnar database | Yes |
| 29 | **LiteDB** | Install LiteDB -- .NET embedded NoSQL file-based database | Yes |

### Orchestrators

| ID | Script | What It Does | Admin |
|----|--------|--------------|-------|
| 12 | **Install All Dev Tools** | Interactive grouped menu with CSV input, group shortcuts, and loop-back | Yes |
| 30 | **Install Databases** | Interactive database installer menu (SQL, NoSQL, graph, search) | Yes |

### Utilities

| ID | Script | What It Does | Admin |
|----|--------|--------------|-------|
| 13 | **Audit Mode** | Scan configs, specs, and suggestions for stale IDs or references | No |
| 14 | **Install Winget** | Install/verify Winget package manager (standalone) | Yes |
| 15 | **Windows Tweaks** | Launch Chris Titus Windows Utility for system tweaks and debloating | Yes |

### Desktop Tools (32-37)

| ID | Script | What It Does | Admin |
|----|--------|--------------|-------|
| 32 | **DBeaver Community** | Universal database visualization and management tool | Yes |
| 33 | **Notepad++ (NPP)** | Install NPP, NPP Settings, or NPP + Settings | Yes |
| 34 | **Simple Sticky Notes** | Install Simple Sticky Notes via Chocolatey | Yes |
| 35 | **GitMap** | Git repository navigator CLI tool | Yes |
| 36 | **OBS Studio** | Install OBS, OBS Settings, or OBS + Settings | Yes |
| 37 | **Windows Terminal** | Install WT, WT Settings, or WT + Settings | Yes |

---

## Root Dispatcher

The root `run.ps1` is the **single entry point** for all scripts. It handles git pull, log cleanup, environment flags, and cache management before delegating.

```powershell
.\run.ps1                           # Show help (after git pull)
.\run.ps1 -I <number>               # Run a specific script
.\run.ps1 -I <number> -D            # Run with all default answers (skip prompts)
.\run.ps1 -I <number> -Clean        # Wipe cache, then run
.\run.ps1 -CleanOnly                # Wipe all cached data
```

### Shortcut Flags

| Flag | Equivalent | Description |
|------|-----------|-------------|
| `-d` | `-I 12` | Interactive dev tools menu |
| `-D` | N/A | Use all default answers (skip prompts) |
| `-a` | `-I 13` | Audit mode |
| `-h` | `-I 13 -Report` | Health check |
| `-v` | `-I 1` | Install VS Code |
| `-w` | `-I 14` | Install Winget |
| `-t` | `-I 15` | Windows tweaks |

### Keyword Install

Install tools by human-friendly name instead of script ID:

```powershell
.\run.ps1 install vscode             # Install VS Code
.\run.ps1 install nodejs,pnpm        # Install Node.js + pnpm
.\run.ps1 install go,git,cpp         # Install Go, Git, C++
.\run.ps1 install python             # Install Python + pip
.\run.ps1 install pylibs             # Python + all pip libraries (numpy, pandas, jupyter, etc.)
.\run.ps1 install flutter            # Install Flutter SDK + Dart
.\run.ps1 install dotnet             # Install .NET SDK
.\run.ps1 install java               # Install OpenJDK
.\run.ps1 install databases          # Interactive database menu
.\run.ps1 install mysql,redis        # Install specific databases
.\run.ps1 install npp                # Notepad++ + Settings
.\run.ps1 install obs                # OBS Studio + Settings
.\run.ps1 install wt                 # Windows Terminal + Settings
.\run.ps1 install dbeaver            # DBeaver + Settings
.\run.ps1 -Install python,php        # Named parameter style
```

### Python & Libraries Keywords

```powershell
# Quick install
.\run.ps1 install pylibs             # Python + all libraries in one go
.\run.ps1 install python-libs        # All pip libraries only (libs without Python install)
.\run.ps1 install python+libs        # Python + all libraries (same as pylibs)

# By purpose
.\run.ps1 install data-science       # Python + data/viz libs (pandas, matplotlib, plotly)
.\run.ps1 install ai-dev             # Python + ML libs (numpy, scipy, scikit-learn, torch)
.\run.ps1 install deep-learning      # Python + ML libs (same as ai-dev)
.\run.ps1 install ai-full            # Python + ML libs + Ollama + llama.cpp (05, 41, 42, 43)

# By group (libs only, no Python install)
.\run.ps1 install jupyter+libs       # Jupyter only (jupyterlab, notebook, ipykernel)
.\run.ps1 install viz-libs           # Visualization (matplotlib, seaborn, plotly)
.\run.ps1 install web-libs           # Web frameworks (django, flask, fastapi, uvicorn)
.\run.ps1 install scraping-libs      # Scraping (requests, beautifulsoup4)
.\run.ps1 install db-libs            # Database (sqlalchemy)
.\run.ps1 install cv-libs            # Computer Vision (opencv-python)
.\run.ps1 install data-libs          # Data tools (pandas, polars)

# Python + specific group
.\run.ps1 install python+viz         # Python + visualization group
.\run.ps1 install python+web         # Python + web frameworks group
.\run.ps1 install python+scraping    # Python + scraping group
.\run.ps1 install python+db          # Python + database group
.\run.ps1 install python+cv          # Python + computer vision group
.\run.ps1 install python+data        # Python + data tools group
.\run.ps1 install python+ml          # Python + ML group
.\run.ps1 install python+jupyter     # Python + all libraries (includes Jupyter)

# Direct group invocation
.\run.ps1 -I 41 -- group ml          # ML group (numpy, scipy, scikit-learn, torch...)
.\run.ps1 -I 41 -- group jupyter     # Jupyter group
.\run.ps1 -I 41 -- group viz         # Visualization group
.\run.ps1 -I 41 -- add <pkg> <pkg>   # Install specific packages by name
.\run.ps1 -I 41 -- list              # Show all available library groups
.\run.ps1 -I 41 -- installed         # Show currently installed pip packages
.\run.ps1 -I 41 -- uninstall         # Uninstall all tracked libraries
```

### Combo Shortcuts

```powershell
.\run.ps1 install vscode+settings    # VSCode + Settings Sync (01, 11)
.\run.ps1 install vms                # VSCode + Menu Fix + Sync (01, 10, 11)
.\run.ps1 install git+desktop        # Git + GitHub Desktop (07, 08)
.\run.ps1 install node+pnpm          # Node.js + pnpm (03, 04)
.\run.ps1 install frontend           # VSCode + Node + pnpm + Sync (01, 03, 04, 11)
.\run.ps1 install backend            # Python + Go + PHP + PG + .NET + Java (05, 06, 16, 20, 39, 40)
.\run.ps1 install web-dev            # VSCode + Node + pnpm + Git + Sync (01, 03, 04, 07, 11)
.\run.ps1 install essentials         # VSCode + Choco + Node + Git + Sync (01, 02, 03, 07, 11)
.\run.ps1 install full-stack         # Everything for full-stack dev (01-09, 11, 16, 39, 40)
.\run.ps1 install mobile-dev         # Flutter mobile dev (38)
.\run.ps1 install data-dev           # Postgres + Redis + DuckDB + DBeaver (20, 24, 28, 32)
```

### Desktop Tools Install Modes

```powershell
# Notepad++
.\run.ps1 install npp                # Install + sync settings (default)
.\run.ps1 install npp+settings       # Install + sync settings (explicit)
.\run.ps1 install npp-settings       # Sync settings only
.\run.ps1 install install-npp        # Install only (no settings)

# OBS Studio
.\run.ps1 install obs                # Install + sync settings (default)
.\run.ps1 install obs-settings       # Sync settings only
.\run.ps1 install install-obs        # Install only (no settings)

# Windows Terminal
.\run.ps1 install wt                 # Install + sync settings (default)
.\run.ps1 install wt-settings        # Sync settings only
.\run.ps1 install install-wt         # Install only (no settings)

# DBeaver
.\run.ps1 install dbeaver            # Install + sync settings (default)
.\run.ps1 install dbeaver-settings   # Sync settings only
.\run.ps1 install install-dbeaver    # Install only (no settings)

# .NET SDK versions
.\run.ps1 install dotnet-6           # Install .NET 6
.\run.ps1 install dotnet-8           # Install .NET 8
.\run.ps1 install dotnet-9           # Install .NET 9

# Java versions
.\run.ps1 install jdk-17             # Install OpenJDK 17
.\run.ps1 install jdk-21             # Install OpenJDK 21

# Flutter modes
.\run.ps1 install flutter            # Install Flutter SDK
.\run.ps1 install flutter+android    # Install with Android toolchain
.\run.ps1 install flutter-extensions # Install VS Code Flutter extensions
.\run.ps1 install flutter-doctor     # Run flutter doctor

# AI Tools
.\run.ps1 install ollama             # Install Ollama for local LLMs (42)
.\run.ps1 install llama-cpp          # Download llama.cpp binaries + models (43)
.\run.ps1 install llama              # Same as llama-cpp (43)
.\run.ps1 install ai-tools           # Install both Ollama + llama.cpp (42, 43)
.\run.ps1 install local-ai           # Same as ai-tools (42, 43)
.\run.ps1 install ai-full            # Python + ML libs + Ollama + llama.cpp (05, 41, 42, 43)

# Rust, Docker, Kubernetes
.\run.ps1 install rust               # Install Rust via rustup (44)
.\run.ps1 install docker             # Install Docker Desktop (45)
.\run.ps1 install kubernetes         # Install kubectl + minikube + Helm (46)
.\run.ps1 install k8s                # Same as kubernetes (46)
.\run.ps1 install devops             # Git + Docker + Kubernetes (07, 45, 46)
.\run.ps1 install container-dev      # Docker + Kubernetes (45, 46)
.\run.ps1 install systems-dev        # C++ + Rust (09, 44)
```

Keywords are case-insensitive, support comma/space separation, auto-deduplicate, and run in sorted order. See `scripts/shared/install-keywords.json` for the full keyword map.

---

## Interactive Menu (Script 12)

When you run `.\run.ps1 -d`, you get a full interactive menu with:

- **Individual selection** -- type script numbers: `1`, `3`, `7`
- **CSV input** -- type comma-separated IDs: `1,3,5,7`
- **Group shortcuts** -- press a letter to select a predefined group:

| Key | Group | Scripts |
|-----|-------|---------|
| `a` | All Core (01-09) | 01, 02, 03, 04, 05, 06, 07, 08, 09 |
| `b` | Dev Runtimes (03-08) | 03, 04, 05, 06, 07, 08 |
| `c` | JS Stack (03-04) | 03, 04 |
| `d` | Languages (05-06,16) | 05, 06, 16 |
| `e` | Git Tools (07-08) | 07, 08 |
| `f` | Web Dev (03,04,06,08,16) | 03, 04, 06, 08, 16 |
| `g` | All + Extras (01-11,16-17,31,33) | 01-11, 16, 17, 31, 33 |
| `h` | SQL DBs (18-21) | 18, 19, 20, 21 |
| `i` | NoSQL DBs (22-26) | 22, 23, 24, 25, 26 |
| `j` | All Databases (18-29) | 18-29 |
| `k` | Backend Stack | 03, 04, 06, 18-20, 24 |
| `l` | Full Stack | 03, 04, 06, 07, 16, 18, 20, 22, 24 |
| `m` | Data Engineering | 05, 20, 27, 28 |
| `n` | Everything (01-46) | All scripts |
| `o` | All Dev + MySQL | 01-09, 18 |
| `p` | All Dev + PostgreSQL | 01-09, 20 |
| `r` | All Dev + PostgreSQL + Redis | 01-09, 20, 24 |
| `s` | SQLite + DBeaver | 21, 32 |
| `t` | All DBs + DBeaver (18-29,32) | 18-29, 32 |
| `u` | AI Tools (42-43) | 42, 43 |
| `v` | AI Full Stack (05,41-43) | 05, 41, 42, 43 |
| `w` | DevOps (07,45-46) | 07, 45, 46 |
| `x` | Container Dev (44-46) | 44, 45, 46 |

- **Select All / None** -- `A` to select all, `N` to deselect all
- **Loop-back** -- after install + summary, returns to the menu
- **Quit** -- press `Q` to exit

---

## Dev Directory

Scripts install tools into a shared dev directory with **smart drive detection** (E: > D: > drive with most free space):

```
E:\dev-tool\
  go\          # GOPATH (bin, pkg/mod, cache/build)
  nodejs\      # npm global prefix
  python\      # Python install + PYTHONUSERBASE (Scripts/)
  pnpm\        # pnpm store
  llama-cpp\   # llama.cpp binaries (CUDA, AVX2, KoboldCPP)
  llama-models\# GGUF model files
  ollama\      # Ollama installer cache
```

Ollama models default to `<dev-dir>\ollama-models` (configurable via `OLLAMA_MODELS` env var).

Override with: `.\run.ps1 -I 12 -- -Path F:\dev-tool`

Manage the path:

```powershell
.\run.ps1 path                # Show current dev directory
.\run.ps1 path D:\my-tools    # Set custom dev directory
.\run.ps1 path --reset        # Clear saved path, use smart detection
```

The orchestrator (script 12) resolves this path once and passes it to all child scripts via `$env:DEV_DIR`.

---

## Versioning

All scripts read their version from `scripts/version.json` (single source of truth). Use the bump script:

```powershell
.\bump-version.ps1 -Patch            # 0.3.0 -> 0.3.1
.\bump-version.ps1 -Minor            # 0.3.0 -> 0.4.0
.\bump-version.ps1 -Major            # 0.3.0 -> 1.0.0
.\bump-version.ps1 -Set "2.0.0"     # Explicit version
```

---

## Project Structure

```
run.ps1                        # Root dispatcher (single entry point)
bump-version.ps1               # Version bump utility
scripts/
  version.json                 # Centralized version (single source of truth)
  registry.json                # Maps IDs to folder names
  shared/                      # Reusable helpers (logging, JSON, PATH, etc.)
    install-keywords.json      # Keyword-to-script-ID mapping
  01-install-vscode/           # VS Code
  02-install-package-managers/ # Chocolatey
  03-install-nodejs/           # Node.js + Yarn + Bun
  04-install-pnpm/             # pnpm
  05-install-python/           # Python
  06-install-golang/           # Go
  07-install-git/              # Git + LFS + gh
  08-install-github-desktop/   # GitHub Desktop
  09-install-cpp/              # C++ (MinGW-w64)
  10-vscode-context-menu-fix/  # VSCode context menu
  11-vscode-settings-sync/     # VSCode settings sync
  12-install-all-dev-tools/    # Orchestrator (interactive menu)
  14-install-winget/           # Winget (standalone)
  15-windows-tweaks/           # Chris Titus Windows Utility
  16-install-php/              # PHP
  17-install-powershell/       # PowerShell (latest)
  18-install-mysql/            # MySQL
  19-install-mariadb/          # MariaDB
  20-install-postgresql/       # PostgreSQL
  21-install-sqlite/           # SQLite + DB Browser
  22-install-mongodb/          # MongoDB
  23-install-couchdb/          # CouchDB
  24-install-redis/            # Redis
  25-install-cassandra/        # Apache Cassandra
  26-install-neo4j/            # Neo4j
  27-install-elasticsearch/    # Elasticsearch
  28-install-duckdb/           # DuckDB
  29-install-litedb/           # LiteDB
  databases/                   # Database orchestrator menu
  31-pwsh-context-menu/        # PowerShell context menu
  32-install-dbeaver/          # DBeaver Community
  33-install-notepadpp/        # Notepad++
  34-install-sticky-notes/     # Simple Sticky Notes
  35-install-gitmap/           # GitMap CLI
  36-install-obs/              # OBS Studio
  37-install-windows-terminal/ # Windows Terminal
  38-install-flutter/          # Flutter + Dart
  39-install-dotnet/           # .NET SDK
  40-install-java/             # Java (OpenJDK)
  41-install-python-libs/      # Python pip libraries
  42-install-ollama/           # Ollama local LLM runtime
  43-install-llama-cpp/        # llama.cpp binaries + GGUF models
  44-install-rust/             # Rust toolchain via rustup
  45-install-docker/           # Docker Desktop + Compose
  46-install-kubernetes/       # kubectl + minikube + Helm
  audit/                       # Audit scanner
spec/                          # Specifications per script
suggestions/                   # Improvement ideas
settings/                      # App settings (NPP, OBS, WT, DBeaver)
.resolved/                     # Runtime state (git-ignored)
```

### Each Script Contains

```
scripts/NN-name/
  run.ps1                  # Entry point
  config.json              # External configuration
  log-messages.json        # All display strings
  helpers/                 # Script-specific functions
  logs/                    # Auto-created (gitignored)
```

---

## Shared Helpers

Reusable utilities in `scripts/shared/`:

| File | Purpose |
|------|---------|
| `logging.ps1` | Console output with colorful status badges, auto-version from `version.json` |
| `json-utils.ps1` | File backups, hashtable conversion, deep JSON merge |
| `resolved.ps1` | Persist runtime state to `.resolved/` |
| `cleanup.ps1` | Wipe `.resolved/` contents |
| `git-pull.ps1` | Git pull with skip guard (`$env:SCRIPTS_ROOT_RUN`) |
| `help.ps1` | Formatted `-Help` output from log-messages.json |
| `path-utils.ps1` | Safe PATH manipulation with dedup |
| `choco-utils.ps1` | Chocolatey install/upgrade wrappers |
| `dev-dir.ps1` | Dev directory resolution and creation |
| `tool-version.ps1` | Version detection, PATH refresh, Python resolver |
| `installed.ps1` | `.installed/` tracking system for version persistence |
| `install-keywords.json` | Keyword-to-script-ID mapping for `install` command |
| `log-viewer.ps1` | Log file viewer utility |
| `symlink-utils.ps1` | Symlink creation and management |

---

## Adding a New Script

1. Create folder `scripts/NN-name/` with `run.ps1`, `config.json`, `log-messages.json`, and `helpers/`
2. Dot-source shared helpers from `scripts/shared/`
3. Support `-Help` flag using `Show-ScriptHelp`
4. Save state via `Save-ResolvedData`
5. Add spec in `spec/NN-name/readme.md`
6. Register in `scripts/registry.json`
7. Add keywords in `scripts/shared/install-keywords.json`
8. Add to script 12's `config.json` if it should be orchestrated

---

## Recent Changes

### v0.28.0 -- Rust, Docker, Kubernetes

- **Script 44 -- Install Rust** -- Rust toolchain via rustup + clippy/rustfmt/rust-analyzer + cargo/bin PATH
- **Script 45 -- Install Docker** -- Docker Desktop via Chocolatey + WSL2 check + daemon verify
- **Script 46 -- Install Kubernetes** -- kubectl + minikube + Helm via Chocolatey
- **New combos** -- `devops` (7+45+46), `container-dev` (45+46), `systems-dev` (9+44)

### v0.26.0 -- 4-Filter Model Picker

- **81-model catalog** -- expanded from 69 to 81 models with new small/fast entries
- **4-filter chain** -- RAM → Size → Speed → Capability with re-indexing
- **Speed filter + column** -- inference speed tier based on file size

### v0.22.1 -- Help Display Overhaul

- **Alignment fixed** -- all keyword tables use consistent PadRight columns for perfect alignment
- **Installed versions shown** -- Available Scripts section displays `[vX.Y.Z]` in green for installed tools
- **Missing scripts added** -- Flutter (38), .NET (39), Java (40), Windows Terminal (37) in help display
- **`pylibs` keyword in help** -- appears in Install by Keyword, Keywords table, and Combo Shortcuts
- **Desktop Tools category** -- renamed from Database Tools, includes all desktop apps

---

## Prerequisites

- **Windows 10/11**
- **PowerShell 5.1+** (ships with Windows)
- **Administrator privileges** (for most scripts)
- **Internet access** (for package downloads)

---

## Author

<div align="center">

### [Md. Alim Ul Karim](https://www.google.com/search?q=alim+ul+karim)

**[Creator & Lead Architect](https://alimkarim.com)** | [Chief Software Engineer](https://www.google.com/search?q=alim+ul+karim), [Riseup Asia LLC](https://riseup-asia.com)

</div>

A system architect with **20+ years** of professional software engineering experience across enterprise, fintech, and distributed systems. His technology stack spans **.NET/C# (18+ years)**, **JavaScript (10+ years)**, **TypeScript (6+ years)**, and **Golang (4+ years)**.

Recognized as a **top 1% talent at Crossover** and one of the top software architects globally. He is also the **Chief Software Engineer of [Riseup Asia LLC](https://riseup-asia.com/)** and maintains an active presence on **[Stack Overflow](https://stackoverflow.com/users/513511/md-alim-ul-karim)** (2,452+ reputation, 961K+ reached, member since 2010) and **LinkedIn** (12,500+ followers).

| | |
|---|---|
| **Website** | [alimkarim.com](https://alimkarim.com/) · [my.alimkarim.com](https://my.alimkarim.com/) |
| **LinkedIn** | [linkedin.com/in/alimkarim](https://linkedin.com/in/alimkarim) |
| **Stack Overflow** | [stackoverflow.com/users/513511/md-alim-ul-karim](https://stackoverflow.com/users/513511/md-alim-ul-karim) |
| **Google** | [Alim Ul Karim](https://www.google.com/search?q=Alim+Ul+Karim) |
| **Role** | Chief Software Engineer, [Riseup Asia LLC](https://riseup-asia.com) |

### Riseup Asia LLC — Top Software Company in Wyoming, USA

[Riseup Asia LLC](https://riseup-asia.com) is a **top-leading software company headquartered in Wyoming, USA**, specializing in building **enterprise-grade frameworks**, **research-based AI models**, and **distributed systems architecture**. The company follows a **"think before doing"** engineering philosophy — every solution is researched, validated, and architected before implementation begins.

**Core expertise includes:**

- 🏗️ **Framework Development** — Designing and shipping production-grade frameworks used across enterprise and fintech platforms
- 🧠 **Research-Based AI** — Inventing and deploying AI models grounded in rigorous research methodologies
- 🔬 **Think Before Doing** — A disciplined engineering culture where architecture, planning, and validation precede every line of code
- 🌐 **Distributed Systems** — Building scalable, resilient systems for global-scale applications

| | |
|---|---|
| **Website** | [riseup-asia.com](https://riseup-asia.com) |
| **Facebook** | [riseupasia.talent](https://www.facebook.com/riseupasia.talent/) |
| **LinkedIn** | [Riseup Asia](https://www.linkedin.com/company/105304484/) |
| **YouTube** | [@riseup-asia](https://www.youtube.com/@riseup-asia) |

---

## License

This project is licensed under the **MIT License** -- see the [LICENSE](LICENSE) file for the full text.

```
Copyright (c) 2026 Alim Ul Karim
```

You may use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, provided the copyright notice and permission notice are preserved. The software is provided "AS IS", without warranty of any kind.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

<div align="center">

*Built with clean architecture, external configs, and colorful terminal output -- because dev tools setup should be effortless.*

</div>
