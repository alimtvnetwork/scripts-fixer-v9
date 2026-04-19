<#
.SYNOPSIS
    Root-level script dispatcher. Runs a numbered script after pulling latest changes.

.DESCRIPTION
    Performs a git pull via the shared helper, sets $env:SCRIPTS_ROOT_RUN = "1"
    so child scripts skip their own git pull, then delegates to
    scripts/<NN>-*/run.ps1 based on the -I parameter.

    When run with no parameters, performs a git pull and shows help.
    Use -Install to run scripts by keyword (e.g. -Install vscode,python,go).
    Use -Clean to wipe all .resolved/ data before running, forcing fresh detection.
    Use -CleanOnly to wipe .resolved/ without running any script.
    Use -Help to see all available scripts and usage information.
    Use 'update' command to upgrade all Chocolatey packages.

.PARAMETER I
    The script number to run (e.g. 1, 2, 3). Maps to folders like 01-*, 02-*, etc.

.PARAMETER Install
    Comma-separated keywords to install (e.g. vscode, nodejs, python, go, git).
    See install-keywords.json for the full mapping.

.PARAMETER Clean
    Wipe all .resolved/ data before running the script.

.PARAMETER CleanOnly
    Wipe all .resolved/ data and exit without running any script.

.PARAMETER Help
    Show usage information and list all available scripts.

.EXAMPLE
    .\run.ps1                        # git pull, show help
    .\run.ps1 -Install vscode        # install VS Code
    .\run.ps1 -Install nodejs,pnpm   # install Node.js + pnpm
    .\run.ps1 -Install python        # install Python + pip
    .\run.ps1 -Install go,git,cpp    # install Go, Git, and C++
    .\run.ps1 -Install all-dev       # interactive dev tools menu
    .\run.ps1 update                 # show outdated, confirm, upgrade all
    .\run.ps1 update nodejs,git        # upgrade specific packages only
    .\run.ps1 update --check           # list outdated packages (no upgrade)
    .\run.ps1 update -y                # upgrade all, skip confirmation
    .\run.ps1 update --exclude=choco   # upgrade all except listed
    .\run.ps1 path D:\devtools       # set default dev directory
    .\run.ps1 path                   # show current dev directory
    .\run.ps1 path --reset           # clear saved path, use smart detection
    .\run.ps1 -d                     # shortcut for -I 12 (interactive menu)
    .\run.ps1 -I 1                   # run scripts/01-*/run.ps1
    .\run.ps1 -I 1 -Clean           # wipe .resolved/, then run script 01
    .\run.ps1 -CleanOnly             # wipe .resolved/ and exit
    .\run.ps1 -Help                  # show all available scripts

.NOTES
    Author : Lovable AI
    Version: 7.3.0
#>

param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Install,

    [int]$I,

    [switch]$d,

    [switch]$a,

    [switch]$h,

    [switch]$v,

    [switch]$w,

    [switch]$t,

    [switch]$M,

    [switch]$Defaults,

    [switch]$Y,

    [switch]$Merge,

    [switch]$Clean,

    [switch]$CleanOnly,

    [switch]$List,

    [switch]$Help
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ── Read project version ─────────────────────────────────────────────
function Get-ScriptVersion {
    $vf = Join-Path (Join-Path $RootDir "scripts") "version.json"
    $isPresent = Test-Path $vf
    if ($isPresent) {
        $data = Get-Content $vf -Raw | ConvertFrom-Json
        return $data.version
    }
    return $null
}

function Show-VersionHeader {
    $ver = Get-ScriptVersion
    $hasVersion = -not [string]::IsNullOrWhiteSpace($ver)
    if ($hasVersion) {
        Write-Host ""
        Write-Host "  Scripts Fixer v$ver" -ForegroundColor Magenta
    }
}

# ── Detect installed tool version (quick, no install) ────────────────
function Get-InstalledTag {
    param([string]$ToolCmd, [string]$Flag = "--version", [scriptblock]$Parse)
    $cmd = Get-Command $ToolCmd -ErrorAction SilentlyContinue
    $isMissing = -not $cmd
    if ($isMissing) { return $null }
    try {
        $raw = & $ToolCmd $Flag 2>$null
        $ver = if ($Parse) { & $Parse "$raw" } else { "$raw".Trim() }
        $hasVer = -not [string]::IsNullOrWhiteSpace($ver)
        if ($hasVer) { return $ver }
    } catch {}
    return $null
}

function Get-VersionMap {
    $map = @{}
    $tools = @(
        @{ Id = "01"; Cmd = "code";      Parse = { param($r) ($r -split '\s+')[1] } },
        @{ Id = "02"; Cmd = "choco";     Parse = { param($r) if ($r -match '(\d[\d.]+)') { $Matches[1] } else { $r } } },
        @{ Id = "03"; Cmd = "node";      Parse = { param($r) $r -replace 'v','' } },
        @{ Id = "04"; Cmd = "pnpm";      Parse = { param($r) $r.Trim() } },
        @{ Id = "05"; Cmd = "python";    Parse = { param($r) ($r -replace 'Python\s*','').Trim() } },
        @{ Id = "06"; Cmd = "go";        Flag = "version"; Parse = { param($r) if ($r -match 'go(\d[\d.]+)') { $Matches[1] } else { $r } } },
        @{ Id = "07"; Cmd = "git";       Parse = { param($r) if ($r -match '(\d[\d.]+)') { $Matches[1] } else { $r } } },
        @{ Id = "08"; Cmd = "github";    Parse = { param($r) if ($r -match '(\d[\d.]+)') { $Matches[1] } else { $r } } },
        @{ Id = "09"; Cmd = "g++";       Parse = { param($r) if ($r -match '(\d[\d.]+)') { $Matches[1] } else { $r } } },
        @{ Id = "16"; Cmd = "php";       Parse = { param($r) if ($r -match '(\d[\d.]+)') { $Matches[1] } else { $r } } },
        @{ Id = "17"; Cmd = "pwsh";      Parse = { param($r) ($r -replace 'PowerShell\s*','').Trim() } },
        @{ Id = "38"; Cmd = "flutter";   Parse = { param($r) if ($r -match '(\d[\d.]+)') { $Matches[1] } else { $r } } },
        @{ Id = "39"; Cmd = "dotnet";    Parse = { param($r) $r.Trim() } },
        @{ Id = "40"; Cmd = "java";      Flag = "-version"; Parse = { param($r) if ($r -match '(\d[\d._]+)') { $Matches[1] } else { $r } } },
        @{ Id = "42"; Cmd = "ollama";    Parse = { param($r) if ($r -match '(\d[\d.]+)') { $Matches[1] } else { $r } } }
    )
    foreach ($t in $tools) {
        $flag = if ($t.Flag) { $t.Flag } else { "--version" }
        $ver = Get-InstalledTag -ToolCmd $t.Cmd -Flag $flag -Parse $t.Parse
        $hasVer = -not [string]::IsNullOrWhiteSpace($ver)
        if ($hasVer) { $map[$t.Id] = $ver }
    }

    # Registry/file-based detection for GUI apps without CLI --version
    $regApps = @(
        @{ Id = "08"; Name = "GitHub Desktop";   Paths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GitHubDesktop",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GitHubDesktop",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\GitHubDesktop"
        )},
        @{ Id = "32"; Name = "DBeaver";          Paths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DBeaver*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DBeaver*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\DBeaver*"
        )},
        @{ Id = "33"; Name = "Notepad++";        Paths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++"
        )},
        @{ Id = "34"; Name = "Simple Sticky Notes"; Paths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Simple Sticky Notes*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Simple Sticky Notes*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Simple Sticky Notes*"
        )},
        @{ Id = "36"; Name = "OBS Studio";       Paths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OBS Studio",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OBS Studio",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OBS Studio"
        )},
        @{ Id = "37"; Name = "Windows Terminal";  Paths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*WindowsTerminal*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*WindowsTerminal*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*WindowsTerminal*",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*Windows Terminal*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*Windows Terminal*"
        )}
    )

    foreach ($app in $regApps) {
        $isAlreadyDetected = $map.ContainsKey($app.Id)
        if ($isAlreadyDetected) { continue }

        foreach ($regPath in $app.Paths) {
            $keys = Get-Item $regPath -ErrorAction SilentlyContinue
            $hasKeys = $null -ne $keys
            if (-not $hasKeys) { continue }

            foreach ($key in $keys) {
                $displayVersion = $key.GetValue("DisplayVersion")
                $hasDisplayVersion = -not [string]::IsNullOrWhiteSpace($displayVersion)
                if ($hasDisplayVersion) {
                    $map[$app.Id] = "$displayVersion".Trim()
                    break
                }
            }

            $isNowDetected = $map.ContainsKey($app.Id)
            if ($isNowDetected) { break }
        }
    }

    # Winget detection
    $isWingetMissing = -not $map.ContainsKey("14")
    if ($isWingetMissing) {
        $wingetCmd = Get-Command "winget" -ErrorAction SilentlyContinue
        $hasWinget = $null -ne $wingetCmd
        if ($hasWinget) {
            try {
                $wingetRaw = & winget --version 2>$null
                $wingetVer = "$wingetRaw".Trim() -replace '^v',''
                $hasWingetVer = -not [string]::IsNullOrWhiteSpace($wingetVer)
                if ($hasWingetVer) { $map["14"] = $wingetVer }
            } catch {}
        }
    }

    return $map
}

# ── Help function ────────────────────────────────────────────────────
function Show-RootHelp {
    Show-VersionHeader
    Write-Host ""
    Write-Host "  Dev Tools Setup Scripts" -ForegroundColor Cyan
    Write-Host "  =======================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Yellow
    Write-Host ""
    $col = 44
    Write-Host "    $(".\run.ps1 install <keywords>".PadRight($col))" -NoNewline; Write-Host "Install by keyword (bare command)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -Install <keywords>".PadRight($col))" -NoNewline; Write-Host "Install by keyword (named parameter)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 update".PadRight($col))" -NoNewline; Write-Host "Show outdated, confirm, upgrade all" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 update nodejs,git".PadRight($col))" -NoNewline; Write-Host "Upgrade specific packages only" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 update --check".PadRight($col))" -NoNewline; Write-Host "List outdated packages (no upgrade)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 update -y".PadRight($col))" -NoNewline; Write-Host "Upgrade all, skip confirmation" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 update --exclude=pkg1,pkg2".PadRight($col))" -NoNewline; Write-Host "Upgrade all except listed" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 export".PadRight($col))" -NoNewline; Write-Host "Export all app settings to repo" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 export npp,obs".PadRight($col))" -NoNewline; Write-Host "Export specific app settings" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 status".PadRight($col))" -NoNewline; Write-Host "Show dashboard of all installed tools" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 status --no-choco".PadRight($col))" -NoNewline; Write-Host "Status without outdated package check" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 doctor".PadRight($col))" -NoNewline; Write-Host "Quick health check of project setup" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 models".PadRight($col))" -NoNewline; Write-Host "Pick AI model backend (llama.cpp / Ollama), browse + install" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 models <ids>".PadRight($col))" -NoNewline; Write-Host "Direct install: CSV of model ids (auto-routes per backend)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 models list".PadRight($col))" -NoNewline; Write-Host "List all models from both catalogs" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -M".PadRight($col))" -NoNewline; Write-Host "Shortcut for 'models'" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 path <dir>".PadRight($col))" -NoNewline; Write-Host "Set default dev directory" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 path".PadRight($col))" -NoNewline; Write-Host "Show current dev directory" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 path --reset".PadRight($col))" -NoNewline; Write-Host "Clear saved path, use smart detection" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I <number>".PadRight($col))" -NoNewline; Write-Host "Run a specific script by ID" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -d".PadRight($col))" -NoNewline; Write-Host "Shortcut for -I 12 (interactive menu)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -a".PadRight($col))" -NoNewline; Write-Host "Shortcut for -I 13 (audit mode)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -h".PadRight($col))" -NoNewline; Write-Host "Shortcut for -I 13 -Report (health check)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -v".PadRight($col))" -NoNewline; Write-Host "Shortcut for -I 1  (install VS Code)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -w".PadRight($col))" -NoNewline; Write-Host "Shortcut for -I 14 (install Winget)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -t".PadRight($col))" -NoNewline; Write-Host "Shortcut for -I 15 (Windows tweaks)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -Defaults".PadRight($col))" -NoNewline; Write-Host "Use all defaults, prompt to confirm" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -Defaults -Y".PadRight($col))" -NoNewline; Write-Host "Use all defaults, skip confirmation" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I <number> -Merge".PadRight($col))" -NoNewline; Write-Host "Run with merge flag (script 02)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I <number> -Clean".PadRight($col))" -NoNewline; Write-Host "Wipe cache, then run" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -CleanOnly".PadRight($col))" -NoNewline; Write-Host "Wipe all cached data" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -Help".PadRight($col))" -NoNewline; Write-Host "Show this help" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -List".PadRight($col))" -NoNewline; Write-Host "Show keyword table only" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Install by Keyword:" -ForegroundColor Yellow
    Write-Host ""
    $kc = 44
    Write-Host "    $("install vscode".PadRight($kc))" -NoNewline; Write-Host "Install Visual Studio Code" -ForegroundColor DarkGray
    Write-Host "    $("install nodejs".PadRight($kc))" -NoNewline; Write-Host "Install Node.js + Yarn + Bun" -ForegroundColor DarkGray
    Write-Host "    $("install pnpm".PadRight($kc))" -NoNewline; Write-Host "Install Node.js + pnpm (auto-chains)" -ForegroundColor DarkGray
    Write-Host "    $("install python".PadRight($kc))" -NoNewline; Write-Host "Install Python + pip" -ForegroundColor DarkGray
    Write-Host "    $("install pylibs".PadRight($kc))" -NoNewline; Write-Host "Install Python + pip + all libraries (numpy, pandas, jupyter...)" -ForegroundColor DarkGray
    Write-Host "    $("install go".PadRight($kc))" -NoNewline; Write-Host "Install Go + configure GOPATH" -ForegroundColor DarkGray
    Write-Host "    $("install git".PadRight($kc))" -NoNewline; Write-Host "Install Git + LFS + GitHub CLI" -ForegroundColor DarkGray
    Write-Host "    $("install cpp".PadRight($kc))" -NoNewline; Write-Host "Install C++ MinGW-w64 compiler" -ForegroundColor DarkGray
    Write-Host "    $("install php".PadRight($kc))" -NoNewline; Write-Host "Install PHP via Chocolatey" -ForegroundColor DarkGray
    Write-Host "    $("install powershell".PadRight($kc))" -NoNewline; Write-Host "Install latest PowerShell" -ForegroundColor DarkGray
    Write-Host "    $("install winget".PadRight($kc))" -NoNewline; Write-Host "Install Winget package manager" -ForegroundColor DarkGray
    Write-Host "    $("install flutter".PadRight($kc))" -NoNewline; Write-Host "Install Flutter SDK + Dart" -ForegroundColor DarkGray
    Write-Host "    $("install dotnet".PadRight($kc))" -NoNewline; Write-Host "Install .NET SDK (latest)" -ForegroundColor DarkGray
    Write-Host "    $("install java".PadRight($kc))" -NoNewline; Write-Host "Install OpenJDK (latest LTS)" -ForegroundColor DarkGray
    Write-Host "    $("install settingssync".PadRight($kc))" -NoNewline; Write-Host "Sync VSCode settings + extensions" -ForegroundColor DarkGray
    Write-Host "    $("install contextmenu".PadRight($kc))" -NoNewline; Write-Host "Fix VSCode right-click context menu" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "    Python & pip libraries:" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "      Quick install:" -ForegroundColor DarkYellow
    Write-Host "    $("install pylibs".PadRight($kc))" -NoNewline; Write-Host "Install Python + all libraries in one go" -ForegroundColor DarkGray
    Write-Host "    $("install python-libs".PadRight($kc))" -NoNewline; Write-Host "Install all pip libraries only (numpy, pandas, etc.)" -ForegroundColor DarkGray
    Write-Host "    $("install python+libs".PadRight($kc))" -NoNewline; Write-Host "Install Python + all libraries in one go" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "      By purpose:" -ForegroundColor DarkYellow
    Write-Host "    $("install data-science".PadRight($kc))" -NoNewline; Write-Host "Python + data/viz libs (pandas, matplotlib, plotly)" -ForegroundColor DarkGray
    Write-Host "    $("install ai-dev".PadRight($kc))" -NoNewline; Write-Host "Python + ML libs (numpy, scipy, scikit-learn, torch)" -ForegroundColor DarkGray
    Write-Host "    $("install deep-learning".PadRight($kc))" -NoNewline; Write-Host "Python + ML libs (same as ai-dev)" -ForegroundColor DarkGray
    Write-Host "    $("install jupyter+libs".PadRight($kc))" -NoNewline; Write-Host "Jupyter only (jupyterlab, notebook, ipykernel)" -ForegroundColor DarkGray
    Write-Host "    $("install viz-libs".PadRight($kc))" -NoNewline; Write-Host "Visualization (matplotlib, seaborn, plotly)" -ForegroundColor DarkGray
    Write-Host "    $("install web-libs".PadRight($kc))" -NoNewline; Write-Host "Web frameworks (django, flask, fastapi, uvicorn)" -ForegroundColor DarkGray
    Write-Host "    $("install scraping-libs".PadRight($kc))" -NoNewline; Write-Host "Scraping (requests, beautifulsoup4)" -ForegroundColor DarkGray
    Write-Host "    $("install db-libs".PadRight($kc))" -NoNewline; Write-Host "Database (sqlalchemy)" -ForegroundColor DarkGray
    Write-Host "    $("install cv-libs".PadRight($kc))" -NoNewline; Write-Host "Computer Vision (opencv-python)" -ForegroundColor DarkGray
    Write-Host "    $("install data-libs".PadRight($kc))" -NoNewline; Write-Host "Data tools (pandas, polars)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "      With Python (auto-installs Python first):" -ForegroundColor DarkYellow
    Write-Host "    $("install python+viz".PadRight($kc))" -NoNewline; Write-Host "Python + visualization group" -ForegroundColor DarkGray
    Write-Host "    $("install python+web".PadRight($kc))" -NoNewline; Write-Host "Python + web frameworks group" -ForegroundColor DarkGray
    Write-Host "    $("install python+scraping".PadRight($kc))" -NoNewline; Write-Host "Python + scraping group" -ForegroundColor DarkGray
    Write-Host "    $("install python+db".PadRight($kc))" -NoNewline; Write-Host "Python + database group" -ForegroundColor DarkGray
    Write-Host "    $("install python+cv".PadRight($kc))" -NoNewline; Write-Host "Python + computer vision group" -ForegroundColor DarkGray
    Write-Host "    $("install python+data".PadRight($kc))" -NoNewline; Write-Host "Python + data tools group" -ForegroundColor DarkGray
    Write-Host "    $("install python+ml".PadRight($kc))" -NoNewline; Write-Host "Python + ML group" -ForegroundColor DarkGray
    Write-Host "    $("install python+jupyter".PadRight($kc))" -NoNewline; Write-Host "Python + all libraries (includes Jupyter)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "      By group (.\run.ps1 -I 41 --):" -ForegroundColor DarkYellow
    Write-Host "    $(".\run.ps1 -I 41 -- group ml".PadRight($kc))" -NoNewline; Write-Host "ML group (numpy, scipy, scikit-learn, torch...)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- group jupyter".PadRight($kc))" -NoNewline; Write-Host "Jupyter (jupyterlab, notebook, ipykernel, ipywidgets)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- group viz".PadRight($kc))" -NoNewline; Write-Host "Visualization (matplotlib, seaborn, plotly)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- group data".PadRight($kc))" -NoNewline; Write-Host "Data tools (pandas, polars)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- group web".PadRight($kc))" -NoNewline; Write-Host "Web frameworks (django, flask, fastapi, uvicorn)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- group scraping".PadRight($kc))" -NoNewline; Write-Host "Scraping (requests, beautifulsoup4)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- group cv".PadRight($kc))" -NoNewline; Write-Host "Computer Vision (opencv-python)" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- group db".PadRight($kc))" -NoNewline; Write-Host "Database (sqlalchemy)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "      Utilities:" -ForegroundColor DarkYellow
    Write-Host "    $(".\run.ps1 -I 41 -- add <pkg1> <pkg2>".PadRight($kc))" -NoNewline; Write-Host "Install specific packages by name" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- list".PadRight($kc))" -NoNewline; Write-Host "Show all available library groups" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- installed".PadRight($kc))" -NoNewline; Write-Host "Show currently installed pip packages" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- uninstall".PadRight($kc))" -NoNewline; Write-Host "Uninstall all tracked libraries" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 41 -- uninstall <pkg>".PadRight($kc))" -NoNewline; Write-Host "Uninstall specific packages" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "    Database installs:" -ForegroundColor Magenta
    Write-Host "    $("install databases".PadRight($kc))" -NoNewline; Write-Host "Open the interactive database installer menu" -ForegroundColor DarkGray
    Write-Host "    $("install mysql".PadRight($kc))" -NoNewline; Write-Host "Install MySQL database" -ForegroundColor DarkGray
    Write-Host "    $("install postgresql".PadRight($kc))" -NoNewline; Write-Host "Install PostgreSQL database" -ForegroundColor DarkGray
    Write-Host "    $("install sqlite".PadRight($kc))" -NoNewline; Write-Host "Install SQLite + DB Browser for SQLite" -ForegroundColor DarkGray
    Write-Host "    $("install mongodb,redis".PadRight($kc))" -NoNewline; Write-Host "Install MongoDB + Redis" -ForegroundColor DarkGray
    Write-Host "    $("install alldev".PadRight($kc))" -NoNewline; Write-Host "Interactive dev tools menu (pick what to install)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "    Combine keywords:" -ForegroundColor Magenta
    Write-Host "    $("install nodejs,pnpm".PadRight($kc))" -NoNewline; Write-Host "Install Node.js + pnpm" -ForegroundColor DarkGray
    Write-Host "    $("install go,git,cpp".PadRight($kc))" -NoNewline; Write-Host "Install Go, Git, and C++" -ForegroundColor DarkGray
    Write-Host "    $("install python,php".PadRight($kc))" -NoNewline; Write-Host "Install Python + PHP" -ForegroundColor DarkGray
    Write-Host "    $("install vscode,nodejs,git".PadRight($kc))" -NoNewline; Write-Host "Install VS Code, Node.js, and Git" -ForegroundColor DarkGray
    Write-Host "    $("install alldev,mysql".PadRight($kc))" -NoNewline; Write-Host "Run the alldev menu, then install MySQL" -ForegroundColor DarkGray
    Write-Host ""

    Show-KeywordTable -Inline
    Write-Host ""

    # ── Available Scripts (with installed versions) ──
    Write-Host "  Available Scripts:" -ForegroundColor Yellow
    Write-Host ""

    $vMap = Get-VersionMap
    $nc = 30

    $printRow = {
        param([string]$id, [string]$name, [string]$desc)
        $ver = $vMap[$id]
        $hasVer = -not [string]::IsNullOrWhiteSpace($ver)
        Write-Host "    $id  $($name.PadRight($nc)) " -NoNewline
        Write-Host $desc -ForegroundColor DarkGray -NoNewline
        if ($hasVer) {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "v$ver" -NoNewline -ForegroundColor Green
            Write-Host "]" -NoNewline -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    Write-Host "    ID  $("Name".PadRight($nc))  Description" -ForegroundColor DarkGray
    Write-Host "    --  $(''.PadRight($nc, '-'))  $(''.PadRight(50, '-'))" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Core Tools" -ForegroundColor Magenta
    & $printRow "01" "Install VS Code"          "Install Visual Studio Code (Stable/Insiders)"
    & $printRow "02" "Chocolatey"               "Install Chocolatey package manager"
    & $printRow "03" "Node.js + Yarn + Bun"     "Install Node.js LTS, Yarn, Bun, verify npx"
    & $printRow "04" "pnpm"                     "Install pnpm, configure global store"
    & $printRow "05" "Python"                   "Install Python, configure pip user site"
    & $printRow "41" "Python Libraries"         "Install pip packages: ML, viz, web, jupyter (by group)"
    & $printRow "06" "Golang"                   "Install Go, configure GOPATH and go env"
    & $printRow "07" "Git + LFS + gh"           "Install Git, Git LFS, GitHub CLI, configure settings"
    & $printRow "08" "GitHub Desktop"           "Install GitHub Desktop via Chocolatey"
    & $printRow "09" "C++ (MinGW-w64)"          "Install MinGW-w64 C++ compiler, verify g++/gcc/make"
    & $printRow "16" "PHP"                      "Install PHP via Chocolatey"
    & $printRow "17" "PowerShell (latest)"      "Install latest PowerShell via Winget/Chocolatey"
    & $printRow "38" "Flutter + Dart"           "Install Flutter SDK, Dart, Android toolchain"
    & $printRow "39" ".NET SDK"                 "Install .NET SDK (6/8/9), configure dotnet CLI"
    & $printRow "40" "Java (OpenJDK)"           "Install OpenJDK via Chocolatey (17/21)"
    Write-Host ""
    Write-Host "    Optional" -ForegroundColor Magenta
    & $printRow "10" "VSCode Context Menu Fix"  "Add/repair VSCode right-click context menu entries"
    & $printRow "11" "VSCode Settings Sync"     "Sync VSCode settings, keybindings, and extensions"
    & $printRow "31" "PowerShell Context Menu"  "Add Open PowerShell Here to right-click menu"
    Write-Host ""
    Write-Host "    Orchestrator" -ForegroundColor Magenta
    & $printRow "12" "Install All Dev Tools"    "Interactive grouped menu: pick tools or install everything"
    & $printRow "30" "Install Databases"        "Interactive database installer (SQL, NoSQL, file-based)"
    Write-Host ""
    Write-Host "    Utilities" -ForegroundColor Magenta
    & $printRow "13" "Audit Mode"               "Scan configs, specs, suggestions for stale IDs"
    & $printRow "14" "Install Winget"           "Install/verify Winget package manager (standalone)"
    & $printRow "15" "Windows Tweaks"           "Chris Titus Windows Utility (tweaks and debloating)"
    Write-Host ""
    Write-Host "    Desktop Tools" -ForegroundColor Magenta
    & $printRow "32" "DBeaver Community"        "Universal database visualization and management tool"
    & $printRow "33" "Notepad++ (NPP)"          "Install NPP, NPP Settings, or NPP + Settings"
    & $printRow "34" "Simple Sticky Notes"      "Install Simple Sticky Notes via Chocolatey"
    & $printRow "35" "GitMap"                   "Git repository navigator CLI tool"
    & $printRow "36" "OBS Studio"               "Install OBS, OBS Settings, or OBS + Settings"
    & $printRow "37" "Windows Terminal"          "Install WT, WT Settings, or WT + Settings"
    Write-Host ""

    Write-Host "  Script 12 (Install All Dev Tools):" -ForegroundColor Yellow
    Write-Host "    $(".\run.ps1 -I 12".PadRight($kc))" -NoNewline; Write-Host "Interactive menu -- pick what to install" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 12 -- -All".PadRight($kc))" -NoNewline; Write-Host "Install everything without prompting" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 12 -- -Skip 04,06".PadRight($kc))" -NoNewline; Write-Host "Skip pnpm and Go" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -I 12 -- -Only 02,03".PadRight($kc))" -NoNewline; Write-Host "Run only Package Managers + Node.js" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Defaults Mode:" -ForegroundColor Yellow
    Write-Host "    $(".\run.ps1 -d -Defaults".PadRight($kc))" -NoNewline; Write-Host "All-dev with defaults, prompt to confirm" -ForegroundColor DarkGray
    Write-Host "    $(".\run.ps1 -d -Defaults -Y".PadRight($kc))" -NoNewline; Write-Host "All-dev with defaults, auto-confirm" -ForegroundColor DarkGray
    Write-Host ""

    # Resolve actual default dev directory dynamically (saved path > smart detect)
    # Quiet inline detection -- avoids the noisy logging in Find-BestDevDrive.
    $resolvedDefault = $null
    $resolvedSource  = $null
    try {
        $devDirHelperPath = Join-Path $RootDir "scripts\shared\dev-dir.ps1"
        $isDevDirHelperPresent = Test-Path $devDirHelperPath
        if ($isDevDirHelperPresent) {
            . $devDirHelperPath
            $savedPath = Get-SavedDevPath
            $hasSavedPath = $null -ne $savedPath
            if ($hasSavedPath) {
                $resolvedDefault = $savedPath
                $resolvedSource  = "saved via .\run.ps1 path"
            }
        }
    } catch {}

    $isResolvedMissing = [string]::IsNullOrWhiteSpace($resolvedDefault)
    if ($isResolvedMissing) {
        # Quiet drive scan: E: > D: > best non-system fixed drive >= 10 GB free
        $minFreeGB = 10
        $sysLetter = if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { "C" } else { $env:SystemDrive.TrimEnd('\').Substring(0, 1) }
        $bestLetter = $null
        $bestSource = $null
        try {
            $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
            $diskMap = @{}
            foreach ($d in $disks) {
                $letter = $d.DeviceID.Substring(0, 1)
                $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
                $diskMap[$letter] = $freeGB
            }
            $hasGoodE = $diskMap.ContainsKey("E") -and $diskMap["E"] -ge $minFreeGB
            $hasGoodD = $diskMap.ContainsKey("D") -and $diskMap["D"] -ge $minFreeGB
            if ($hasGoodE) {
                $bestLetter = "E"; $bestSource = "auto-detected: E: drive ($($diskMap['E']) GB free)"
            } elseif ($hasGoodD) {
                $bestLetter = "D"; $bestSource = "auto-detected: D: drive ($($diskMap['D']) GB free)"
            } else {
                $best = $diskMap.GetEnumerator() |
                    Where-Object { $_.Key -ne $sysLetter -and $_.Key -ne "E" -and $_.Key -ne "D" -and $_.Value -ge $minFreeGB } |
                    Sort-Object Value -Descending | Select-Object -First 1
                $hasBest = $null -ne $best
                if ($hasBest) {
                    $bestLetter = $best.Key
                    $bestSource = "auto-detected: $($best.Key): drive ($($best.Value) GB free)"
                }
            }
        } catch {}

        $hasBestLetter = $null -ne $bestLetter
        if ($hasBestLetter) {
            $resolvedDefault = "${bestLetter}:\dev-tool"
            $resolvedSource  = $bestSource
        } else {
            $resolvedDefault = "${sysLetter}:\dev-tool"
            $resolvedSource  = "fallback to system drive (no qualified drive >= $minFreeGB GB free)"
        }
    }

    Write-Host "    Default dev directory: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$resolvedDefault " -NoNewline -ForegroundColor White
    Write-Host "($resolvedSource)" -ForegroundColor DarkGray
    Write-Host "    Override with: " -NoNewline -ForegroundColor DarkGray; Write-Host ".\run.ps1 -I 12 -- -Path F:\dev-tool" -ForegroundColor White
    Write-Host "    Default VS Code edition: " -NoNewline -ForegroundColor DarkGray; Write-Host "Stable" -ForegroundColor White
    Write-Host "    Default sync mode: " -NoNewline -ForegroundColor DarkGray; Write-Host "Overwrite" -ForegroundColor White
    Write-Host ""

    Write-Host "  Per-script help:" -ForegroundColor Yellow
    Write-Host "    $(".\run.ps1 -I <number> -- -Help".PadRight($kc))" -NoNewline; Write-Host "Show help for a specific script" -ForegroundColor DarkGray
    Write-Host ""
}

# ── Keyword table (compact view) ────────────────────────────────────
function Show-KeywordTable {
    param([switch]$Inline)

    $isStandalone = -not $Inline
    if ($isStandalone) {
        Write-Host ""
        Write-Host "  Available Keywords" -ForegroundColor Cyan
        Write-Host "  ==================" -ForegroundColor DarkGray
    } else {
        Write-Host "  Available Keywords:" -ForegroundColor Yellow
    }
    Write-Host ""

    $kwCol = 28
    $descCol = 36

    Write-Host "    $("Keyword".PadRight($kwCol))$("Description".PadRight($descCol))Script ID" -ForegroundColor DarkGray
    Write-Host "    $(''.PadRight($kwCol, '-'))$(''.PadRight($descCol, '-'))---------" -ForegroundColor DarkGray

    Write-Host "    $("vscode, vs-code".PadRight($kwCol))$("VS Code".PadRight($descCol))01"
    Write-Host "    $("choco, chocolatey".PadRight($kwCol))$("Chocolatey".PadRight($descCol))02"
    Write-Host "    $("nodejs, node".PadRight($kwCol))$("Node.js + Yarn + Bun".PadRight($descCol))03"
    Write-Host "    $("pnpm".PadRight($kwCol))$("Node.js + pnpm".PadRight($descCol))03, 04"
    Write-Host ""
    Write-Host "    Python & Libraries" -ForegroundColor Magenta
    Write-Host "    $("python, pip".PadRight($kwCol))$("Python + pip".PadRight($descCol))05"
    Write-Host "    $("pylibs".PadRight($kwCol))$("Python + all libraries".PadRight($descCol))05, 41"
    Write-Host "    $("python-libs, pip-libs".PadRight($kwCol))$("All pip libraries only".PadRight($descCol))41"
    Write-Host "    $("ml-libs, ml-full".PadRight($kwCol))$("ML libraries".PadRight($descCol))41"
    Write-Host "    $("jupyter+libs".PadRight($kwCol))$("Jupyter group only".PadRight($descCol))41"
    Write-Host "    $("viz-libs".PadRight($kwCol))$("Visualization group".PadRight($descCol))41"
    Write-Host "    $("web-libs".PadRight($kwCol))$("Web frameworks group".PadRight($descCol))41"
    Write-Host "    $("scraping-libs".PadRight($kwCol))$("Scraping group".PadRight($descCol))41"
    Write-Host "    $("db-libs".PadRight($kwCol))$("Database group".PadRight($descCol))41"
    Write-Host "    $("cv-libs".PadRight($kwCol))$("Computer Vision group".PadRight($descCol))41"
    Write-Host "    $("data-libs".PadRight($kwCol))$("Data tools group".PadRight($descCol))41"
    Write-Host "    $("python+viz".PadRight($kwCol))$("Python + viz group".PadRight($descCol))05, 41"
    Write-Host "    $("python+web".PadRight($kwCol))$("Python + web group".PadRight($descCol))05, 41"
    Write-Host "    $("python+scraping".PadRight($kwCol))$("Python + scraping group".PadRight($descCol))05, 41"
    Write-Host "    $("python+db".PadRight($kwCol))$("Python + database group".PadRight($descCol))05, 41"
    Write-Host "    $("python+cv".PadRight($kwCol))$("Python + CV group".PadRight($descCol))05, 41"
    Write-Host "    $("python+data".PadRight($kwCol))$("Python + data group".PadRight($descCol))05, 41"
    Write-Host "    $("python+ml".PadRight($kwCol))$("Python + ML group".PadRight($descCol))05, 41"
    Write-Host "    $("python+libs, ml-dev".PadRight($kwCol))$("Python + all libraries".PadRight($descCol))05, 41"
    Write-Host "    $("python+jupyter".PadRight($kwCol))$("Python + all libraries".PadRight($descCol))05, 41"
    Write-Host "    $("pip+jupyter+libs".PadRight($kwCol))$("Python + all libraries".PadRight($descCol))05, 41"
    Write-Host "    $("data-science".PadRight($kwCol))$("Python + data/viz libs".PadRight($descCol))05, 41"
    Write-Host "    $("ai-dev, deep-learning".PadRight($kwCol))$("Python + ML libs".PadRight($descCol))05, 41"
    Write-Host ""
    Write-Host "    Languages & Runtimes" -ForegroundColor Magenta
    Write-Host "    $("go, golang".PadRight($kwCol))$("Go".PadRight($descCol))06"
    Write-Host "    $("git, gh".PadRight($kwCol))$("Git + LFS + GitHub CLI".PadRight($descCol))07"
    Write-Host "    $("github-desktop".PadRight($kwCol))$("GitHub Desktop".PadRight($descCol))08"
    Write-Host "    $("cpp, c++, gcc".PadRight($kwCol))$("C++ (MinGW-w64)".PadRight($descCol))09"
    Write-Host "    $("php, php+phpmyadmin".PadRight($kwCol))$("PHP + phpMyAdmin (default)".PadRight($descCol))16"
    Write-Host "    $("php-only".PadRight($kwCol))$("PHP only".PadRight($descCol))16"
    Write-Host "    $("phpmyadmin".PadRight($kwCol))$("phpMyAdmin only".PadRight($descCol))16"
    Write-Host "    $("powershell, pwsh".PadRight($kwCol))$("PowerShell (latest)".PadRight($descCol))17"
    Write-Host "    $("flutter, dart".PadRight($kwCol))$("Flutter SDK + Dart".PadRight($descCol))38"
    Write-Host "    $("dotnet, csharp, .net".PadRight($kwCol))$(".NET SDK".PadRight($descCol))39"
    Write-Host "    $("java, openjdk, jdk".PadRight($kwCol))$("OpenJDK".PadRight($descCol))40"
    Write-Host ""
    Write-Host "    Config & Settings" -ForegroundColor Magenta
    Write-Host "    $("context-menu".PadRight($kwCol))$("VSCode context menu fix".PadRight($descCol))10"
    Write-Host "    $("settings-sync".PadRight($kwCol))$("VSCode settings sync".PadRight($descCol))11"
    Write-Host "    $("pwsh-menu".PadRight($kwCol))$("PowerShell context menu".PadRight($descCol))31"
    Write-Host "    $("all-dev, all".PadRight($kwCol))$("Interactive dev tools menu".PadRight($descCol))12"
    Write-Host "    $("audit".PadRight($kwCol))$("Audit mode".PadRight($descCol))13"
    Write-Host "    $("health, healthcheck".PadRight($kwCol))$("Health check (audit + report)".PadRight($descCol))13"
    Write-Host "    $("winget".PadRight($kwCol))$("Winget package manager".PadRight($descCol))14"
    Write-Host "    $("tweaks".PadRight($kwCol))$("Windows tweaks".PadRight($descCol))15"
    Write-Host ""
    Write-Host "    Databases" -ForegroundColor Magenta
    Write-Host "    $("mysql".PadRight($kwCol))$("MySQL".PadRight($descCol))18"
    Write-Host "    $("mariadb".PadRight($kwCol))$("MariaDB".PadRight($descCol))19"
    Write-Host "    $("postgresql, postgres".PadRight($kwCol))$("PostgreSQL".PadRight($descCol))20"
    Write-Host "    $("sqlite".PadRight($kwCol))$("SQLite + DB Browser".PadRight($descCol))21"
    Write-Host "    $("mongodb, mongo".PadRight($kwCol))$("MongoDB".PadRight($descCol))22"
    Write-Host "    $("couchdb".PadRight($kwCol))$("CouchDB".PadRight($descCol))23"
    Write-Host "    $("redis".PadRight($kwCol))$("Redis".PadRight($descCol))24"
    Write-Host "    $("cassandra".PadRight($kwCol))$("Apache Cassandra".PadRight($descCol))25"
    Write-Host "    $("neo4j".PadRight($kwCol))$("Neo4j".PadRight($descCol))26"
    Write-Host "    $("elasticsearch".PadRight($kwCol))$("Elasticsearch".PadRight($descCol))27"
    Write-Host "    $("duckdb".PadRight($kwCol))$("DuckDB".PadRight($descCol))28"
    Write-Host "    $("litedb".PadRight($kwCol))$("LiteDB".PadRight($descCol))29"
    Write-Host "    $("databases, db".PadRight($kwCol))$("Database installer menu".PadRight($descCol))30"
    Write-Host ""
    Write-Host "    Desktop Tools" -ForegroundColor Magenta
    Write-Host "    $("notepad++, npp".PadRight($kwCol))$("NPP + Settings (install + sync)".PadRight($descCol))33"
    Write-Host "    $("npp+settings".PadRight($kwCol))$("NPP + Settings (explicit)".PadRight($descCol))33"
    Write-Host "    $("npp-settings".PadRight($kwCol))$("NPP Settings (settings only)".PadRight($descCol))33"
    Write-Host "    $("install-npp".PadRight($kwCol))$("Install NPP (install only)".PadRight($descCol))33"
    Write-Host "    $("sticky-notes, sticky".PadRight($kwCol))$("Simple Sticky Notes".PadRight($descCol))34"
    Write-Host "    $("gitmap, git-map".PadRight($kwCol))$("GitMap CLI".PadRight($descCol))35"
    Write-Host "    $("obs, obs+settings".PadRight($kwCol))$("OBS + Settings (install + sync)".PadRight($descCol))36"
    Write-Host "    $("obs-settings".PadRight($kwCol))$("OBS Settings (settings only)".PadRight($descCol))36"
    Write-Host "    $("install-obs".PadRight($kwCol))$("Install OBS (install only)".PadRight($descCol))36"
    Write-Host "    $("wt, windows-terminal".PadRight($kwCol))$("WT + Settings (install + sync)".PadRight($descCol))37"
    Write-Host "    $("wt+settings".PadRight($kwCol))$("WT + Settings (explicit)".PadRight($descCol))37"
    Write-Host "    $("wt-settings".PadRight($kwCol))$("WT Settings (settings only)".PadRight($descCol))37"
    Write-Host "    $("install-wt".PadRight($kwCol))$("Install WT (install only)".PadRight($descCol))37"
    Write-Host "    $("dbeaver, db-viewer".PadRight($kwCol))$("DBeaver + Settings (install + sync)".PadRight($descCol))32"
    Write-Host "    $("dbeaver-settings".PadRight($kwCol))$("DBeaver Settings (settings only)".PadRight($descCol))32"
    Write-Host "    $("install-dbeaver".PadRight($kwCol))$("Install DBeaver (install only)".PadRight($descCol))32"
    Write-Host ""
    Write-Host "    AI & Local LLM" -ForegroundColor Magenta
    Write-Host "    $("ollama, local-llm".PadRight($kwCol))$("Ollama (local LLM runner)".PadRight($descCol))42"
    Write-Host "    $("llama-cpp, llamacpp".PadRight($kwCol))$("llama.cpp + KoboldCPP".PadRight($descCol))43"
    Write-Host "    $("llama, gguf".PadRight($kwCol))$("llama.cpp (alias)".PadRight($descCol))43"
    Write-Host "    $("llm".PadRight($kwCol))$("LLM tools (Ollama)".PadRight($descCol))42"
    Write-Host "    $("kobold, koboldcpp".PadRight($kwCol))$("KoboldCPP (llama.cpp)".PadRight($descCol))43"
    Write-Host "    $("ollama-models".PadRight($kwCol))$("Ollama model pull only".PadRight($descCol))42"
    Write-Host "    $("llama-models".PadRight($kwCol))$("llama.cpp model picker only".PadRight($descCol))43"
    Write-Host "    $("ai-tools, local-ai".PadRight($kwCol))$("Ollama + llama.cpp".PadRight($descCol))42, 43"
    Write-Host "    $("ollama+llama".PadRight($kwCol))$("Ollama + llama.cpp".PadRight($descCol))42, 43"
    Write-Host "    $("ai-full, aifull".PadRight($kwCol))$("Python + libs + Ollama + llama.cpp".PadRight($descCol))05, 41, 42, 43"
    Write-Host ""
    Write-Host "    DevOps & Containers" -ForegroundColor Magenta
    Write-Host "    $("rust, cargo".PadRight($kwCol))$("Rust + Cargo".PadRight($descCol))44"
    Write-Host "    $("docker".PadRight($kwCol))$("Docker Desktop".PadRight($descCol))45"
    Write-Host "    $("kubernetes, k8s".PadRight($kwCol))$("Kubernetes tools".PadRight($descCol))46"
    Write-Host "    $("devops".PadRight($kwCol))$("Git + Docker + Kubernetes".PadRight($descCol))07, 45, 46"
    Write-Host "    $("container-dev".PadRight($kwCol))$("Docker + Kubernetes".PadRight($descCol))45, 46"
    Write-Host "    $("systems-dev".PadRight($kwCol))$("C++ + Rust".PadRight($descCol))09, 44"
    Write-Host ""

    Write-Host "  Combo Shortcuts:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    $("vscode+settings, vscode+s".PadRight($kwCol))$("VSCode + Settings Sync".PadRight($descCol))01, 11"
    Write-Host "    $("vscode+menu+settings, vms".PadRight($kwCol))$("VSCode + Menu Fix + Sync".PadRight($descCol))01, 10, 11"
    Write-Host "    $("git+desktop, git+gh".PadRight($kwCol))$("Git + GitHub Desktop".PadRight($descCol))07, 08"
    Write-Host "    $("node+pnpm".PadRight($kwCol))$("Node.js + pnpm".PadRight($descCol))03, 04"
    Write-Host "    $("frontend".PadRight($kwCol))$("VSCode + Node + pnpm + Sync".PadRight($descCol))01, 03, 04, 11"
    Write-Host "    $("backend".PadRight($kwCol))$("Python + Go + PHP + PG + .NET + Java".PadRight($descCol))05, 06, 16, 20, 39, 40"
    Write-Host "    $("web-dev, webdev".PadRight($kwCol))$("VSCode + Node + pnpm + Git + Sync".PadRight($descCol))01, 03, 04, 07, 11"
    Write-Host "    $("essentials".PadRight($kwCol))$("VSCode + Choco + Node + Git + Sync".PadRight($descCol))01, 02, 03, 07, 11"
    Write-Host ""
    Write-Host "    Python & Libraries" -ForegroundColor Magenta
    Write-Host "    $("pylibs".PadRight($kwCol))$("Python + all libraries".PadRight($descCol))05, 41"
    Write-Host "    $("python+libs, ml-dev".PadRight($kwCol))$("Python + all libraries".PadRight($descCol))05, 41"
    Write-Host "    $("python+jupyter".PadRight($kwCol))$("Python + all libraries".PadRight($descCol))05, 41"
    Write-Host "    $("pip+jupyter+libs".PadRight($kwCol))$("Python + all libraries".PadRight($descCol))05, 41"
    Write-Host "    $("jupyter+libs".PadRight($kwCol))$("Jupyter group only".PadRight($descCol))41"
    Write-Host "    $("data-science, datascience".PadRight($kwCol))$("Python + data/viz libs".PadRight($descCol))05, 41"
    Write-Host "    $("ai-dev, aidev".PadRight($kwCol))$("Python + ML libs".PadRight($descCol))05, 41"
    Write-Host "    $("deep-learning, ml-full".PadRight($kwCol))$("Python + ML libs".PadRight($descCol))05, 41"
    Write-Host ""
    Write-Host "    General" -ForegroundColor Magenta
    Write-Host "    $("full-stack, fullstack".PadRight($kwCol))$("Everything for full-stack dev".PadRight($descCol))01-09, 11, 16, 39, 40"
    Write-Host "    $("mobile-dev".PadRight($kwCol))$("Flutter mobile dev".PadRight($descCol))38"
    Write-Host "    $("data-dev".PadRight($kwCol))$("Postgres + Redis + DuckDB + DBeaver".PadRight($descCol))20, 24, 28, 32"
    Write-Host ""
    Write-Host "  Usage: " -NoNewline -ForegroundColor Yellow; Write-Host ".\run.ps1 install <keyword>[,<keyword>,...]"
    Write-Host ""
}




function Resolve-InstallKeywords {
    param(
        [string[]]$Keywords
    )

    $keywordsFile = Join-Path $RootDir "scripts\shared\install-keywords.json"
    $isKeywordsFileMissing = -not (Test-Path $keywordsFile)
    if ($isKeywordsFileMissing) {
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "Keyword mapping not found: $keywordsFile"
        return $null
    }

    $keywordData = Get-Content $keywordsFile -Raw | ConvertFrom-Json
    $keywordMap = $keywordData.keywords
    $modesMap  = $keywordData.modes

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($keywordGroup in $Keywords) {
        $isKeywordGroupMissing = [string]::IsNullOrWhiteSpace($keywordGroup)
        if ($isKeywordGroupMissing) {
            continue
        }

        $parts = $keywordGroup -split '[,\s]+' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_.Length -gt 0 }
        foreach ($part in $parts) {
            $tokens.Add($part)
        }
    }

    # Mode priority: install+settings > install-only / settings-only > null
    # When multiple keywords target the same script WITH THE SAME mode, merge to the highest.
    # When modes DIFFER (e.g. "group ml" vs "group jupyter"), keep both as separate runs.
    $modePriority = @{
        "install+settings" = 3
        "install-only"     = 2
        "settings-only"    = 1
    }

    # Build a list of {Id, Mode} entries -- allow same script ID with different modes
    $entries = [System.Collections.Generic.List[hashtable]]::new()
    $hasError = $false

    foreach ($token in $tokens) {
        # Try exact match first, then try without hyphens
        $ids = $keywordMap.$token
        if ($null -eq $ids) {
            $stripped = $token -replace '-', ''
            $ids = $keywordMap.$stripped
        }
        $isUnknown = $null -eq $ids
        if ($isUnknown) {
            Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
            Write-Host "Unknown keyword: '$token'"
            $hasError = $true
            continue
        }

        # Determine mode override for this token (if any)
        $tokenModes = $modesMap.$token
        foreach ($id in $ids) {
            $mode = $null
            if ($null -ne $tokenModes) {
                $mode = $tokenModes."$id"
            }

            # Check if an entry with the same ID already exists
            $existingEntry = $null
            foreach ($e in $entries) {
                $isSameId = $e.Id -eq [int]$id
                if ($isSameId) {
                    # Same ID: check if mode is identical or mergeable
                    $isSameMode = $e.Mode -eq $mode
                    $isBothNull = ($null -eq $e.Mode) -and ($null -eq $mode)
                    $isBothMergePriority = ($null -ne $e.Mode -and $modePriority.ContainsKey($e.Mode)) -and ($null -ne $mode -and $modePriority.ContainsKey($mode))
                    if ($isSameMode -or $isBothNull -or $isBothMergePriority) {
                        $existingEntry = $e
                        break
                    }
                }
            }

            $isNewEntry = $null -eq $existingEntry
            if ($isNewEntry) {
                $entries.Add(@{ Id = [int]$id; Mode = $mode })
            } else {
                # Merge: keep the higher-priority mode (only for install+settings / install-only / settings-only)
                $existingPri = if ($null -ne $existingEntry.Mode -and $modePriority.ContainsKey($existingEntry.Mode)) { $modePriority[$existingEntry.Mode] } else { 0 }
                $newPri      = if ($null -ne $mode -and $modePriority.ContainsKey($mode)) { $modePriority[$mode] } else { 0 }
                $isNewHigher = $newPri -gt $existingPri
                if ($isNewHigher) {
                    $existingEntry.Mode = $mode
                }
            }
        }
    }

    if ($hasError) {
        Write-Host ""
        Write-Host "  Run .\run.ps1 -Help to see all available keywords" -ForegroundColor Cyan
        return $null
    }

    # Sort by ID, preserving order for duplicate IDs
    $sorted = $entries | Sort-Object { [int]$_.Id }
    return $sorted
}

# ── Run a single script by ID ───────────────────────────────────────
function Invoke-ScriptById {
    param(
        [int]$ScriptId,
        [hashtable]$ExtraArgs = @{}
    )

    $prefix = "{0:D2}" -f $ScriptId
    $registryPath = Join-Path $RootDir "scripts\registry.json"
    $isRegistryAvailable = Test-Path $registryPath

    $scriptDir = $null
    if ($isRegistryAvailable) {
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
        $folderName = $registry.scripts.$prefix

        $isRegistered = [bool]$folderName
        if ($isRegistered) {
            $scriptDir = Get-Item (Join-Path $RootDir "scripts\$folderName") -ErrorAction SilentlyContinue
        }
    } else {
        $pattern = Join-Path $RootDir "scripts/$prefix-*"
        $scriptDir = @(Get-Item $pattern -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -and (Test-Path (Join-Path $_.FullName "run.ps1")) }) |
            Select-Object -First 1
    }

    $isScriptMissing = -not $scriptDir -or -not (Test-Path $scriptDir.FullName)
    if ($isScriptMissing) {
        Write-Host ""
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "No script folder found for ID $prefix"
        return $false
    }

    $scriptFile = Join-Path $scriptDir.FullName "run.ps1"
    $isRunFileMissing = -not (Test-Path $scriptFile)
    if ($isRunFileMissing) {
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "run.ps1 not found in $($scriptDir.Name)"
        return $false
    }

    # Clean & create logs folder
    $logsDir = Join-Path $scriptDir.FullName "logs"
    if (Test-Path $logsDir) {
        Remove-Item -Path $logsDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $logsDir -ItemType Directory -Force | Out-Null

    Write-Host ""
    Write-Host "  [ RUN   ] " -ForegroundColor Magenta -NoNewline
    Write-Host "Executing: $($scriptDir.Name)\run.ps1"
    Write-Host ""

    & $scriptFile @ExtraArgs
    return $true
}

# ── Load choco-update helper ─────────────────────────────────────────
. (Join-Path $RootDir "scripts\shared\choco-update.ps1")

# ── Export command function ────────────────────────────────────────────
function Invoke-ExportCommand {
    param([string[]]$Args)

    Write-Host ""
    Write-Host "  Export Settings" -ForegroundColor Cyan
    Write-Host "  ===============" -ForegroundColor DarkGray
    Write-Host ""

    # Settings-capable scripts: scriptId -> keyword for display
    $exportScripts = @{
        "32" = "DBeaver"
        "33" = "Notepad++"
        "36" = "OBS Studio"
        "37" = "Windows Terminal"
    }

    # Parse filter keywords from args
    $filterKeywords = @()
    $hasArgs = $null -ne $Args -and $Args.Count -gt 0
    if ($hasArgs) {
        foreach ($arg in $Args) {
            $tokens = $arg -split '[,\s]+' | Where-Object { $_.Length -gt 0 }
            $filterKeywords += $tokens
        }
    }

    # Keyword-to-scriptId mapping for filtering
    $exportKeywordMap = @{
        "dbeaver"  = "32"; "db-viewer" = "32"; "dbviewer" = "32"
        "npp"      = "33"; "notepad++" = "33"; "notepadpp" = "33"
        "obs"      = "36"; "obs-studio" = "36"
        "wt"       = "37"; "windows-terminal" = "37"
    }

    # Resolve which scripts to export
    $scriptIds = @()
    $hasFilters = $filterKeywords.Count -gt 0
    if ($hasFilters) {
        foreach ($kw in $filterKeywords) {
            $kwLower = $kw.ToLower()
            $hasMapping = $exportKeywordMap.ContainsKey($kwLower)
            if ($hasMapping) {
                $scriptIds += $exportKeywordMap[$kwLower]
            } else {
                Write-Host "  [ WARN ] Unknown export keyword: $kw" -ForegroundColor Yellow
                Write-Host "           Available: dbeaver, npp, obs, wt" -ForegroundColor DarkGray
            }
        }
        $scriptIds = @($scriptIds | Select-Object -Unique)
    } else {
        $scriptIds = @($exportScripts.Keys | Sort-Object)
    }

    $hasNoScripts = $scriptIds.Count -eq 0
    if ($hasNoScripts) {
        Write-Host "  [ FAIL ] No valid export targets specified" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor Yellow
        Write-Host "    .\run.ps1 export              # export all settings"
        Write-Host "    .\run.ps1 export npp,obs      # export specific apps"
        Write-Host "    .\run.ps1 export dbeaver      # export DBeaver settings"
        Write-Host ""
        return
    }

    Write-Host "  Exporting $($scriptIds.Count) app(s): $($scriptIds | ForEach-Object { $exportScripts[$_] }) " -ForegroundColor Magenta
    Write-Host ""

    $successCount = 0
    $failCount = 0

    foreach ($id in $scriptIds) {
        $label = $exportScripts[$id]
        Write-Host "  [ RUN  ] Exporting: $label (script $id)..." -ForegroundColor Cyan

        try {
            $isExported = Invoke-ScriptById -ScriptId $id -ExtraArgs @("export")
            if ($isExported) {
                $successCount++
            } else {
                $failCount++
            }
        } catch {
            Write-Host "  [ FAIL ] Export failed for $label : $_" -ForegroundColor Red
            $failCount++
        }
    }

    Write-Host ""
    Write-Host "  ======================================" -ForegroundColor DarkGray
    $hasFails = $failCount -gt 0
    if ($hasFails) {
        Write-Host "  [ DONE ] $successCount of $($scriptIds.Count) exported successfully ($failCount failed)" -ForegroundColor Yellow
    } else {
        Write-Host "  [ DONE ] $successCount of $($scriptIds.Count) exported successfully" -ForegroundColor Green
    }
    Write-Host ""
}

# ── Status command function ────────────────────────────────────────────
function Invoke-StatusCommand {
    param([string[]]$Args)

    Write-Host ""
    Write-Host "  Tool Status Dashboard" -ForegroundColor Cyan
    Write-Host "  =====================" -ForegroundColor DarkGray
    Write-Host ""

    $installedDir = Join-Path $RootDir ".installed"
    $isInstalledDirMissing = -not (Test-Path $installedDir)
    if ($isInstalledDirMissing) {
        Write-Host "  No tools tracked yet. Run some install scripts first." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $records = Get-ChildItem -Path $installedDir -Filter "*.json" -File | Sort-Object Name
    $hasNoRecords = $records.Count -eq 0
    if ($hasNoRecords) {
        Write-Host "  No tools tracked yet. Run some install scripts first." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Parse --no-choco flag
    $isNoChoco = $false
    if ($null -ne $Args) {
        foreach ($arg in $Args) {
            $argLower = "$arg".Trim().ToLower()
            $isNoChocoFlag = $argLower -eq "--no-choco" -or $argLower -eq "--fast"
            if ($isNoChocoFlag) { $isNoChoco = $true }
        }
    }

    # Table header
    $nameCol = 24
    $versionCol = 24
    $statusCol = 12
    $methodCol = 12
    $header = "    {0}  {1}  {2}  {3}" -f "Tool".PadRight($nameCol), "Version".PadRight($versionCol), "Status".PadRight($statusCol), "Source".PadRight($methodCol)
    Write-Host $header -ForegroundColor DarkGray
    $separator = "    {0}  {1}  {2}  {3}" -f ("-" * $nameCol), ("-" * $versionCol), ("-" * $statusCol), ("-" * $methodCol)
    Write-Host $separator -ForegroundColor DarkGray

    $okCount = 0
    $errorCount = 0
    $unknownCount = 0

    foreach ($file in $records) {
        try {
            $record = Get-Content $file.FullName -Raw | ConvertFrom-Json
        } catch {
            continue
        }

        $toolName = if ($record.name) { $record.name } else { $file.BaseName }
        $version  = if ($record.version) { $record.version } else { "unknown" }
        $method   = if ($record.method) { $record.method } else { "--" }

        # Determine status
        $hasError = $record.lastError -and ($record.lastError -ne "")
        $isVersionUnknown = $version -eq "unknown" -or $version -eq "installed" -or $version -eq "(version pending)"

        $status = "ok"
        $statusColor = "Green"
        if ($hasError) {
            $status = "error"
            $statusColor = "Red"
            $errorCount++
        } elseif ($isVersionUnknown) {
            $status = "unverified"
            $statusColor = "Yellow"
            $unknownCount++
        } else {
            $okCount++
        }

        # Truncate long values
        $displayName = if ($toolName.Length -gt $nameCol) { $toolName.Substring(0, $nameCol - 2) + ".." } else { $toolName }
        $displayVer  = if ($version.Length -gt $versionCol) { $version.Substring(0, $versionCol - 2) + ".." } else { $version }

        Write-Host "    $($displayName.PadRight($nameCol))  $($displayVer.PadRight($versionCol))  " -NoNewline
        Write-Host $status.PadRight($statusCol) -ForegroundColor $statusColor -NoNewline
        Write-Host "  $method"
    }

    Write-Host ""
    Write-Host "  Summary: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$okCount ok" -ForegroundColor Green -NoNewline
    $hasErrors = $errorCount -gt 0
    if ($hasErrors) {
        Write-Host ", $errorCount error(s)" -ForegroundColor Red -NoNewline
    }
    $hasUnknowns = $unknownCount -gt 0
    if ($hasUnknowns) {
        Write-Host ", $unknownCount unverified" -ForegroundColor Yellow -NoNewline
    }
    Write-Host " -- $($records.Count) total tracked"

    # Optionally check choco outdated
    $isChocoCheckEnabled = -not $isNoChoco
    if ($isChocoCheckEnabled) {
        $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
        $isChocoAvailable = $null -ne $chocoCmd
        if ($isChocoAvailable) {
            Write-Host ""
            Write-Host "  Checking for outdated packages..." -ForegroundColor DarkGray
            try {
                $outdated = & choco outdated -r 2>$null | Where-Object { $_ -match '\|' }
                $hasOutdated = $null -ne $outdated -and @($outdated).Count -gt 0
                if ($hasOutdated) {
                    Write-Host ""
                    Write-Host "  Outdated Packages:" -ForegroundColor Yellow
                    foreach ($line in $outdated) {
                        $parts = $line -split '\|'
                        $hasParts = $parts.Count -ge 3
                        if ($hasParts) {
                            $pkgName = $parts[0]
                            $currentVer = $parts[1]
                            $availableVer = $parts[2]
                            Write-Host "    $($pkgName.PadRight(24))  $currentVer -> $availableVer" -ForegroundColor DarkGray
                        }
                    }
                } else {
                    Write-Host "  All Chocolatey packages are up to date." -ForegroundColor Green
                }
            } catch {
                Write-Host "  Could not check Chocolatey outdated: $_" -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""
    Write-Host "  Tip: Use '.\run.ps1 status --no-choco' to skip the outdated check." -ForegroundColor DarkGray
    Write-Host ""
}

# ── Doctor command function ────────────────────────────────────────────
function Invoke-DoctorCommand {
    <#
    .SYNOPSIS
        Quick health-check that verifies the project setup itself.
        Lighter than full audit -- runs in < 2 seconds.
    #>

    Write-Host ""
    Write-Host "  Project Doctor" -ForegroundColor Cyan
    Write-Host "  ==============" -ForegroundColor DarkGray
    Write-Host ""

    $passCount = 0
    $failCount = 0
    $warnCount = 0

    # Helper to print check results
    function Write-Check {
        param([string]$Label, [string]$Status, [string]$Detail = "")
        switch ($Status) {
            "pass" {
                Write-Host "    [PASS] " -ForegroundColor Green -NoNewline
                Write-Host $Label -NoNewline
                if ($Detail) { Write-Host " -- $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
                $script:passCount++
            }
            "fail" {
                Write-Host "    [FAIL] " -ForegroundColor Red -NoNewline
                Write-Host $Label -NoNewline
                if ($Detail) { Write-Host " -- $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
                $script:failCount++
            }
            "warn" {
                Write-Host "    [WARN] " -ForegroundColor Yellow -NoNewline
                Write-Host $Label -NoNewline
                if ($Detail) { Write-Host " -- $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
                $script:warnCount++
            }
        }
    }

    # 1. Check scripts root directory
    $scriptsRoot = Join-Path $RootDir "scripts"
    $hasScriptsDir = Test-Path $scriptsRoot
    if ($hasScriptsDir) {
        Write-Check "Scripts directory exists" "pass" $scriptsRoot
    } else {
        Write-Check "Scripts directory exists" "fail" "Not found: $scriptsRoot"
    }

    # 2. Check version.json
    $versionFile = Join-Path $scriptsRoot "version.json"
    $hasVersionFile = Test-Path $versionFile
    if ($hasVersionFile) {
        try {
            $versionData = Get-Content $versionFile -Raw | ConvertFrom-Json
            $hasVersion = -not [string]::IsNullOrWhiteSpace($versionData.version)
            if ($hasVersion) {
                Write-Check "version.json is valid" "pass" "v$($versionData.version)"
            } else {
                Write-Check "version.json is valid" "fail" "Empty version field"
            }
        } catch {
            Write-Check "version.json is valid" "fail" "Parse error: $_"
        }
    } else {
        Write-Check "version.json is valid" "fail" "Not found"
    }

    # 3. Check registry.json
    $registryFile = Join-Path $scriptsRoot "registry.json"
    $hasRegistry = Test-Path $registryFile
    if ($hasRegistry) {
        try {
            $registryData = Get-Content $registryFile -Raw | ConvertFrom-Json
            $registryCount = ($registryData.scripts.PSObject.Properties | Measure-Object).Count
            Write-Check "registry.json is valid" "pass" "$registryCount scripts registered"
        } catch {
            Write-Check "registry.json is valid" "fail" "Parse error: $_"
        }
    } else {
        Write-Check "registry.json is valid" "fail" "Not found"
    }

    # 4. Check registry IDs match existing folders
    if ($hasRegistry) {
        $missingFolders = @()
        foreach ($prop in $registryData.scripts.PSObject.Properties) {
            $folderPath = Join-Path $scriptsRoot $prop.Value
            $isFolderMissing = -not (Test-Path $folderPath)
            if ($isFolderMissing) {
                $missingFolders += "$($prop.Name):$($prop.Value)"
            }
        }
        $hasMissing = $missingFolders.Count -gt 0
        if ($hasMissing) {
            Write-Check "Registry folders exist" "fail" "Missing: $($missingFolders -join ', ')"
        } else {
            Write-Check "Registry folders exist" "pass" "All $registryCount folders present"
        }
    }

    # 5. Check .logs directory
    $logsDir = Join-Path $RootDir ".logs"
    $hasLogsDir = Test-Path $logsDir
    if ($hasLogsDir) {
        $logFiles = @(Get-ChildItem -Path $logsDir -Filter "*.json" -File -ErrorAction SilentlyContinue)
        Write-Check ".logs/ directory exists" "pass" "$($logFiles.Count) log file(s)"
    } else {
        Write-Check ".logs/ directory exists" "warn" "Will be created on first script run"
    }

    # 6. Check .installed directory
    $installedDir = Join-Path $RootDir ".installed"
    $hasInstalledDir = Test-Path $installedDir
    if ($hasInstalledDir) {
        $trackFiles = @(Get-ChildItem -Path $installedDir -Filter "*.json" -File -ErrorAction SilentlyContinue)
        Write-Check ".installed/ directory exists" "pass" "$($trackFiles.Count) tool(s) tracked"
    } else {
        Write-Check ".installed/ directory exists" "warn" "No tools tracked yet"
    }

    # 7. Check Chocolatey
    $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
    $hasChoco = $null -ne $chocoCmd
    if ($hasChoco) {
        $chocoVer = try { & choco --version 2>$null } catch { $null }
        Write-Check "Chocolatey is reachable" "pass" "v$chocoVer"
    } else {
        Write-Check "Chocolatey is reachable" "fail" "Not found in PATH"
    }

    # 8. Check admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Check "Running as Administrator" "pass"
    } else {
        Write-Check "Running as Administrator" "warn" "Some scripts require admin rights"
    }

    # 9. Check shared helpers are present
    $requiredHelpers = @("logging.ps1", "installed.ps1", "resolved.ps1", "help.ps1", "choco-utils.ps1", "path-utils.ps1", "dev-dir.ps1", "json-utils.ps1", "tool-version.ps1")
    $sharedDir = Join-Path $scriptsRoot "shared"
    $missingHelpers = @()
    foreach ($helper in $requiredHelpers) {
        $helperPath = Join-Path $sharedDir $helper
        $isHelperMissing = -not (Test-Path $helperPath)
        if ($isHelperMissing) {
            $missingHelpers += $helper
        }
    }
    $hasMissingHelpers = $missingHelpers.Count -gt 0
    if ($hasMissingHelpers) {
        Write-Check "Shared helpers present" "fail" "Missing: $($missingHelpers -join ', ')"
    } else {
        Write-Check "Shared helpers present" "pass" "$($requiredHelpers.Count) helpers found"
    }

    # 10. Check install-keywords.json
    $keywordsFile = Join-Path $sharedDir "install-keywords.json"
    $hasKeywords = Test-Path $keywordsFile
    if ($hasKeywords) {
        try {
            $kwData = Get-Content $keywordsFile -Raw | ConvertFrom-Json
            $kwCount = ($kwData.keywords.PSObject.Properties | Measure-Object).Count
            Write-Check "install-keywords.json is valid" "pass" "$kwCount keywords mapped"
        } catch {
            Write-Check "install-keywords.json is valid" "fail" "Parse error: $_"
        }
    } else {
        Write-Check "install-keywords.json is valid" "fail" "Not found"
    }

    # Summary
    Write-Host ""
    Write-Host "  Summary: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$passCount passed" -ForegroundColor Green -NoNewline
    $hasWarns = $warnCount -gt 0
    if ($hasWarns) {
        Write-Host ", $warnCount warning(s)" -ForegroundColor Yellow -NoNewline
    }
    $hasFails = $failCount -gt 0
    if ($hasFails) {
        Write-Host ", $failCount failed" -ForegroundColor Red -NoNewline
    }
    Write-Host ""

    if ($hasFails) {
        Write-Host ""
        Write-Host "  Some checks failed. Fix the issues above for a healthy setup." -ForegroundColor Red
    } elseif ($hasWarns) {
        Write-Host ""
        Write-Host "  Project looks good with minor warnings." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "  All checks passed. Project is healthy!" -ForegroundColor Green
    }
    Write-Host ""
}

# ── Path command function ─────────────────────────────────────────────
function Invoke-PathCommand {
    param([string[]]$Args)

    # Load dev-dir helper
    $devDirHelper = Join-Path $RootDir "scripts\shared\dev-dir.ps1"
    $isHelperMissing = -not (Test-Path $devDirHelper)
    if ($isHelperMissing) {
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "Shared helper not found: $devDirHelper"
        return
    }
    . $devDirHelper

    $firstArg = if ($Args -and $Args.Count -gt 0) { $Args[0].Trim() } else { "" }
    $isReset = $firstArg -eq "--reset" -or $firstArg -eq "reset"
    $isShowOnly = [string]::IsNullOrWhiteSpace($firstArg)

    if ($isReset) {
        Remove-SavedDevPath
        Write-Host ""
        Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline
        Write-Host "Saved dev directory cleared. Smart detection will be used."
        Write-Host ""
        return
    }

    if ($isShowOnly) {
        $savedPath = Get-SavedDevPath
        $hasSavedPath = $null -ne $savedPath
        Write-Host ""
        if ($hasSavedPath) {
            Write-Host "  Current dev directory: " -NoNewline -ForegroundColor DarkGray
            Write-Host "$savedPath" -ForegroundColor White
        } else {
            Write-Host "  No saved dev directory. Using smart detection (E:\dev-tool > D:\dev-tool > best drive)." -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor Yellow
        Write-Host "    .\run.ps1 path D:\devtools          " -NoNewline; Write-Host "Set default dev directory" -ForegroundColor DarkGray
        Write-Host "    .\run.ps1 path                      " -NoNewline; Write-Host "Show current dev directory" -ForegroundColor DarkGray
        Write-Host "    .\run.ps1 path --reset              " -NoNewline; Write-Host "Clear saved path, use smart detection" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Validate the path
    $targetPath = $firstArg
    $isValidFormat = $targetPath -match '^[A-Za-z]:\\'
    if (-not $isValidFormat) {
        Write-Host ""
        Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
        Write-Host "Invalid path format. Use a full path like D:\devtools or F:\dev-tool"
        Write-Host ""
        return
    }

    Set-SavedDevPath -Path $targetPath
    Write-Host ""
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline
    Write-Host "Default dev directory set to: $targetPath"
    Write-Host ""
    Write-Host "  All scripts will now use this path. Use '.\run.ps1 path --reset' to revert to smart detection." -ForegroundColor DarkGray
    Write-Host ""
}

# ── Normalize positional command mode ────────────────────────────────
# Supports:  .\run.ps1 install alldev,mysql
#             .\run.ps1 install alldev mysql
#             .\run.ps1 -Install alldev,mysql
#             .\run.ps1 update
#             .\run.ps1 path D:\devtools
$normalizedCommand = ""
$hasCommand = -not [string]::IsNullOrWhiteSpace($Command)
if ($hasCommand) {
    $normalizedCommand = $Command.Trim().ToLower()
    $isBareInstallCommand = $normalizedCommand -eq "install"
    $isBareUpdateCommand  = $normalizedCommand -eq "update" -or $normalizedCommand -eq "choco-update" -or $normalizedCommand -eq "upgrade"
    $isBarePathCommand    = $normalizedCommand -eq "path"
    $isBareExportCommand  = $normalizedCommand -eq "export"
    $isBareStatusCommand  = $normalizedCommand -eq "status"
    $isBareDoctorCommand  = $normalizedCommand -eq "doctor"
    $isBareModelsCommand  = $normalizedCommand -eq "models" -or $normalizedCommand -eq "model"
    $isBareOsCommand      = $normalizedCommand -eq "os"
    $isBareProfileCommand = $normalizedCommand -eq "profile" -or $normalizedCommand -eq "profiles"
    $isBareScriptId = $normalizedCommand -match '^\d+$'

    if ($isBareOsCommand) {
        Show-VersionHeader
        $osScript = Join-Path $RootDir "scripts\os\run.ps1"
        $isOsScriptPresent = Test-Path $osScript
        if (-not $isOsScriptPresent) {
            Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
            Write-Host "OS dispatcher missing at: $osScript"
            exit 1
        }
        & $osScript @Install
        exit $LASTEXITCODE
    }

    if ($isBareProfileCommand) {
        Show-VersionHeader
        $profileScript = Join-Path $RootDir "scripts\profile\run.ps1"
        $isProfileScriptPresent = Test-Path $profileScript
        if (-not $isProfileScriptPresent) {
            Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
            Write-Host "Profile dispatcher missing at: $profileScript"
            exit 1
        }
        & $profileScript @Install
        exit $LASTEXITCODE
    }


    if ($isBareInstallCommand) {
        # Merge positional remaining args into $Install
        $hasRemainingArgs = $null -ne $Install -and $Install.Count -gt 0
        $isNoRemainingArgs = -not $hasRemainingArgs
        if ($isNoRemainingArgs) {
            Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
            Write-Host "No keywords provided after 'install'. Usage: .\run.ps1 install <keywords>"
            Write-Host ""
            Write-Host "  Run .\run.ps1 -Help to see all available keywords" -ForegroundColor Cyan
            exit 1
        }
    } elseif ($isBareExportCommand) {
        Show-VersionHeader
        Invoke-ExportCommand -Args $Install
        exit 0
    } elseif ($isBareStatusCommand) {
        Show-VersionHeader
        Invoke-StatusCommand -Args $Install
        exit 0
    } elseif ($isBarePathCommand) {
        Show-VersionHeader
        Invoke-PathCommand -Args $Install
        exit 0
    } elseif ($isBareDoctorCommand) {
        Show-VersionHeader
        Invoke-DoctorCommand
        exit 0
    } elseif ($isBareModelsCommand) {
        Show-VersionHeader
        $modelsScript = Join-Path $RootDir "scripts\models\run.ps1"
        & $modelsScript @Install
        exit 0
    } elseif ($isBareUpdateCommand) {
        Show-VersionHeader

        # Self-update: pull latest script changes first
        Remove-Item Env:\SCRIPTS_ROOT_RUN -ErrorAction SilentlyContinue
        $sharedGitPull = Join-Path $RootDir "scripts\shared\git-pull.ps1"
        $isHelperAvailable = Test-Path $sharedGitPull
        if ($isHelperAvailable) {
            . $sharedGitPull
            Invoke-GitPull -RepoRoot $RootDir
        }

        # Parse update arguments from $Install (remaining positional args)
        $updateArgs = @{}
        $updatePackages = @()
        $updateExclude  = @()
        $isCheckOnly    = $false
        $isAutoConfirm  = $false

        if ($null -ne $Install -and $Install.Count -gt 0) {
            foreach ($arg in $Install) {
                $argLower = $arg.Trim().ToLower()

                $isCheckFlag = $argLower -eq "--check" -or $argLower -eq "-check"
                if ($isCheckFlag) { $isCheckOnly = $true; continue }

                $isYesFlag = $argLower -eq "-y" -or $argLower -eq "--yes"
                if ($isYesFlag) { $isAutoConfirm = $true; continue }

                $isExcludeFlag = $argLower.StartsWith("--exclude")
                if ($isExcludeFlag) {
                    # Handle --exclude pkg1,pkg2 or --exclude=pkg1,pkg2
                    $excludeValue = ""
                    $hasEquals = $argLower.Contains("=")
                    if ($hasEquals) {
                        $excludeValue = $arg.Substring($arg.IndexOf("=") + 1)
                    }
                    $hasExcludeValue = $excludeValue.Length -gt 0
                    if ($hasExcludeValue) {
                        $updateExclude += $excludeValue -split ','
                    }
                    continue
                }

                # Otherwise treat as package name(s)
                $pkgTokens = $arg -split '[,\s]+' | Where-Object { $_.Length -gt 0 }
                $updatePackages += $pkgTokens
            }
        }

        # Also check if -Y switch was passed at root level
        if ($Y) { $isAutoConfirm = $true }

        $updateArgs["Packages"]    = $updatePackages
        $updateArgs["Exclude"]     = $updateExclude
        if ($isCheckOnly)   { $updateArgs["CheckOnly"]   = $true }
        if ($isAutoConfirm) { $updateArgs["AutoConfirm"] = $true }

        Invoke-ChocoUpdate @updateArgs
        exit 0
    } elseif ($isBareScriptId) {
        $I = [int]$normalizedCommand
    } else {
        # Treat unknown bare command as a keyword (e.g. .\run.ps1 vscode)
        $Install = @($normalizedCommand) + @($Install | Where-Object { $_ })
    }
}

# ── No params = git pull + help ──────────────────────────────────────
$hasInstallKeywords = $null -ne $Install -and $Install.Count -gt 0
$hasNoParams = -not $hasCommand -and -not $I -and -not $hasInstallKeywords -and -not $d -and -not $a -and -not $h -and -not $v -and -not $w -and -not $t -and -not $M -and -not $Help -and -not $List -and -not $CleanOnly -and -not $Clean -and -not $Defaults
if ($hasNoParams) {
    Remove-Item Env:\SCRIPTS_ROOT_RUN -ErrorAction SilentlyContinue
    $sharedGitPull = Join-Path $RootDir "scripts\shared\git-pull.ps1"
    $isHelperAvailable = Test-Path $sharedGitPull
    if ($isHelperAvailable) {
        . $sharedGitPull
        Invoke-GitPull -RepoRoot $RootDir
    }
    Show-RootHelp
    exit 0
}

# ── List (keyword table only) ────────────────────────────────────────
if ($List) {
    Show-KeywordTable
    exit 0
}

# ── Help ─────────────────────────────────────────────────────────────
if ($Help) {
    Show-RootHelp
    exit 0
}

# ── Handle -CleanOnly (no -I required) ───────────────────────────────
if ($CleanOnly) {
    $resolvedDir = Join-Path $RootDir ".resolved"
    if (Test-Path $resolvedDir) {
        Get-ChildItem -Path $resolvedDir -Recurse -Force | Remove-Item -Recurse -Force
        Write-Host "  [ CLEAN ] " -ForegroundColor Green -NoNewline
        Write-Host "All .resolved/ data wiped"
    } else {
        Write-Host "  [ SKIP  ] " -ForegroundColor DarkGray -NoNewline
        Write-Host "Nothing to clean -- .resolved/ does not exist"
    }
    exit 0
}

# ── Handle -Clean ────────────────────────────────────────────────────
if ($Clean) {
    $resolvedDir = Join-Path $RootDir ".resolved"
    if (Test-Path $resolvedDir) {
        Get-ChildItem -Path $resolvedDir -Recurse -Force | Remove-Item -Recurse -Force
        Write-Host "  [ CLEAN ] " -ForegroundColor Green -NoNewline
        Write-Host "All .resolved/ data wiped -- fresh detection will run"
    } else {
        Write-Host "  [ SKIP  ] " -ForegroundColor DarkGray -NoNewline
        Write-Host "Nothing to clean -- .resolved/ does not exist"
    }
    Write-Host ""
}

# ── Load shared git-pull helper ──────────────────────────────────────
$sharedGitPull = Join-Path $RootDir "scripts\shared\git-pull.ps1"
$isHelperMissing = -not (Test-Path $sharedGitPull)
if ($isHelperMissing) {
    Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
    Write-Host "Shared helper not found: $sharedGitPull"
    exit 1
}
. $sharedGitPull

# ── Git Pull ─────────────────────────────────────────────────────────
Invoke-GitPull -RepoRoot $RootDir

# ── Set flag so child scripts skip git pull ──────────────────────────
$env:SCRIPTS_ROOT_RUN = "1"

# ── Handle install keyword mode (bare or named) ─────────────────────
$hasInstallKeywords = $null -ne $Install -and $Install.Count -gt 0
if ($hasInstallKeywords) {
    $resolvedEntries = Resolve-InstallKeywords -Keywords $Install

    $isResolveFailed = $null -eq $resolvedEntries
    if ($isResolveFailed) { exit 1 }

    $totalSteps = @($resolvedEntries).Count
    $idList = ($resolvedEntries | ForEach-Object {
        $label = "$($_.Id)"
        $hasMode = -not [string]::IsNullOrWhiteSpace($_.Mode)
        if ($hasMode) {
            $shortMode = ($_.Mode -replace '^group ', '')
            $label = "$label[$shortMode]"
        }
        $label
    }) -join ', '
    Write-Host ""
    Write-Host "  [ INFO ] " -ForegroundColor Cyan -NoNewline
    Write-Host "Installing $totalSteps tool(s): $idList"
    Write-Host ""

    $successCount = 0
    $failCount    = 0

    # Map script IDs to their mode env var names
    $modeEnvVars = @{
        33 = "NPP_MODE"
        16 = "PHP_MODE"
        36 = "OBS_MODE"
        37 = "WT_MODE"
        32 = "DBEAVER_MODE"
        38 = "FLUTTER_MODE"
        39 = "DOTNET_MODE"
        40 = "JAVA_MODE"
        41 = "PYTHON_LIBS_MODE"
    }

    foreach ($entry in $resolvedEntries) {
        $id      = $entry.Id
        $modeKey = $entry.Mode
        $hasModeOverride = -not [string]::IsNullOrWhiteSpace($modeKey)
        $envVarName = $modeEnvVars[$id]
        $hasEnvVar  = $null -ne $envVarName
        if ($hasModeOverride -and $hasEnvVar) {
            Set-Item "Env:\$envVarName" $modeKey
        }
        $result = Invoke-ScriptById -ScriptId $id
        if ($hasModeOverride -and $hasEnvVar) {
            Remove-Item "Env:\$envVarName" -ErrorAction SilentlyContinue
        }
        if ($result) { $successCount++ } else { $failCount++ }

        # Refresh PATH between chained scripts so newly installed tools are discoverable
        Refresh-EnvPath
    }

    Write-Host ""
    Write-Host "  ======================================" -ForegroundColor DarkGray
    Write-Host "  [ DONE ] " -ForegroundColor Green -NoNewline
    Write-Host "$successCount of $totalSteps completed successfully"
    if ($failCount -gt 0) {
        Write-Host "  [ WARN ] " -ForegroundColor Yellow -NoNewline
        Write-Host "$failCount script(s) failed"
    }

    Remove-Item Env:\SCRIPTS_ROOT_RUN -ErrorAction SilentlyContinue
    exit 0
}

# ── -M shortcut: dispatch to models orchestrator ─────────────────────
if ($M) {
    Show-VersionHeader
    $modelsScript = Join-Path $RootDir "scripts\models\run.ps1"
    & $modelsScript @Install
    exit 0
}

# ── Expand shortcuts ──────────────────────────────────────────────────
if ($d) { $I = 12 }
if ($a) { $I = 13 }
if ($v) { $I = 1 }
if ($w) { $I = 14 }
if ($t) { $I = 15 }
if ($h) { $I = 13; $scriptArgs = @{ "Report" = $true } }
# -Defaults without -I defaults to all-dev (script 12)
if ($Defaults -and -not $I) { $I = 12 }

# ── Validate -I is provided ──────────────────────────────────────────
$isMissingParam = -not $I
if ($isMissingParam) {
    Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
    Write-Host "Missing -I parameter. Usage: .\run.ps1 -I <number>"
    Write-Host ""
    Write-Host "  Run .\run.ps1 -Help to see all available scripts" -ForegroundColor Cyan
    exit 1
}

# ── Delegate to single script ────────────────────────────────────────
$isScriptArgsUndefined = -not (Test-Path variable:scriptArgs) -or $null -eq $scriptArgs
if ($isScriptArgsUndefined) { $scriptArgs = @{} }
if ($Merge) { $scriptArgs["Merge"] = $true }
if ($Defaults) { $scriptArgs["Defaults"] = $true }

# ── -Defaults -Y confirmation logic ──────────────────────────────────
if ($Defaults -and -not $Y) {
    Write-Host ""
    Write-Host "  Defaults Mode" -ForegroundColor Cyan
    Write-Host "  =============" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Dev directory     : " -NoNewline -ForegroundColor DarkGray; Write-Host "auto (E:\dev-tool -- smart detection)" -ForegroundColor White
    Write-Host "    VS Code edition   : " -NoNewline -ForegroundColor DarkGray; Write-Host "Stable" -ForegroundColor White
    Write-Host "    Settings sync     : " -NoNewline -ForegroundColor DarkGray; Write-Host "Overwrite" -ForegroundColor White
    Write-Host ""
    $confirm = Read-Host "  Proceed with these defaults? [Y/n]"
    $isAborted = $confirm.Trim().ToUpper() -eq "N"
    if ($isAborted) {
        Write-Host "  [ SKIP ] Aborted by user." -ForegroundColor Yellow
        exit 0
    }
}

$result = Invoke-ScriptById -ScriptId $I -ExtraArgs $scriptArgs

$isScriptFailed = -not $result
if ($isScriptFailed) { exit 1 }

# ── Clean up env flag ────────────────────────────────────────────────
Remove-Item Env:\SCRIPTS_ROOT_RUN -ErrorAction SilentlyContinue
