# 05 -- `git-safe-all` (`gsa`) Subcommand

**Type**: top-level subcommand
**Folder**: `scripts/git-tools/`
**Invocation**: `.\run.ps1 gsa` or `.\run.ps1 git-safe-all`

## What it does

Two modes (per locked decision):

### Default (wildcard)
```powershell
git config --global --add safe.directory '*'
```
Adds the wildcard entry to `~/.gitconfig` `[safe]` section. Idempotent -- checks for existing entry first via `git config --global --get-all safe.directory`.

### `--scan <path>` (per-repo)
```powershell
.\run.ps1 gsa --scan C:\Users\Alim\GitHub
```
1. Walk `<path>` recursively to depth 4 (configurable)
2. For each `.git` folder found, derive the repo root (parent of `.git`)
3. Run `git config --global --add safe.directory '<full-repo-path>'` for each (idempotent)
4. Print summary: "Added 17 repos, 3 already present, scanned 2,341 directories in 4.2s"

## Implementation

### `scripts/git-tools/run.ps1` (new dispatcher)
```powershell
param(
    [Parameter(Position=0)][string]$Action,
    [string]$Scan,
    [int]$Depth = 4,
    [Parameter(ValueFromRemainingArguments=$true)]$Rest
)
. "$PSScriptRoot\..\shared\logging.ps1"
switch ($Action) {
    "safe-all" { & "$PSScriptRoot\helpers\safe-all.ps1" -Scan $Scan -Depth $Depth }
    default    { Show-GitToolsHelp }
}
```

### `scripts/git-tools/helpers/safe-all.ps1`
```powershell
param([string]$Scan, [int]$Depth = 4)
Initialize-Logging -ScriptName "git-safe-all"

if (-not $Scan) {
    # Wildcard mode
    $existing = git config --global --get-all safe.directory
    if ($existing -contains '*') {
        Write-Log -Level "ok" -Message "safe.directory '*' already set"
    } else {
        git config --global --add safe.directory '*'
        Write-Log -Level "ok" -Message "Added safe.directory '*'"
    }
} else {
    # Scan mode
    if (-not (Test-Path $Scan)) {
        Write-Log -Level "fail" -Message "Path not found: $Scan"
        Save-LogFile -Status "fail"; return
    }
    $existing = @(git config --global --get-all safe.directory)
    $repos = Get-ChildItem -Path $Scan -Filter ".git" -Directory -Recurse -Depth $Depth -Force -ErrorAction SilentlyContinue
    $added = 0; $skipped = 0
    foreach ($g in $repos) {
        $repoPath = $g.Parent.FullName.Replace('\', '/')
        if ($existing -contains $repoPath) { $skipped++; continue }
        git config --global --add safe.directory $repoPath
        $added++
    }
    Write-Log -Level "ok" -Message "Added $added repos, $skipped already present, scanned $($repos.Count) .git folders"
}
Save-LogFile -Status "ok"
```

## Root dispatcher wiring (`run.ps1`)

```powershell
if ($Command -in @("gsa", "git-safe-all")) {
    & "$PSScriptRoot\scripts\git-tools\run.ps1" "safe-all" @Rest
    return
}
```

## Verification

```powershell
.\run.ps1 gsa
git config --global --get-all safe.directory   # should include *

.\run.ps1 gsa --scan C:\Users\Alim\GitHub
git config --global --get-all safe.directory   # should now include each repo path
```

## Open questions

None.
