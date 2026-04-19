# 04 -- `os clean` Subcommand

**Type**: subcommand under new `os` dispatcher
**Folder**: `scripts/os/`
**Invocation**: `.\run.ps1 os clean` (also `.\run.ps1 os-clean` keyword)
**Requires**: Admin elevation

## What it does

Performs Windows housekeeping:

```powershell
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $env:TEMP -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
wevtutil el | ForEach-Object { wevtutil cl "$_" }
Remove-Item (Get-PSReadLineOption).HistorySavePath -ErrorAction SilentlyContinue
Clear-History
```

## Implementation

### `scripts/os/run.ps1` (new dispatcher)
```powershell
param([Parameter(Position=0)][string]$Action, [Parameter(ValueFromRemainingArguments=$true)]$Rest)
. "$PSScriptRoot\..\shared\logging.ps1"
. "$PSScriptRoot\..\shared\help.ps1"

switch ($Action) {
    "clean"             { & "$PSScriptRoot\helpers\clean.ps1" @Rest }
    "hib-off"           { & "$PSScriptRoot\helpers\hibernate.ps1" -Off }
    "hibernate-off"     { & "$PSScriptRoot\helpers\hibernate.ps1" -Off }
    "fix-long-path"     { & "$PSScriptRoot\helpers\longpath.ps1" }
    "flp"               { & "$PSScriptRoot\helpers\longpath.ps1" }
    "add-user"          { & "$PSScriptRoot\helpers\add-user.ps1" @Rest }
    default             { Show-OsHelp }
}
```

### `scripts/os/helpers/clean.ps1`
- Initialize logging as `"OS Clean"`
- Assert Admin (re-launch with `-Verb RunAs` if not, like script 10)
- Run each step inside a `try/catch` -- log per-step counts (e.g. "Removed 142 temp files (28.4 MB)")
- Wrap each path in **CODE RED** error logging: every Remove-Item failure logs the exact path and reason
- Emit a summary table at the end: rows = step, columns = items removed, bytes freed
- `Save-LogFile -Status "ok"` (or `partial` if any step had errors)

### Per-step details
| Step | Action | Counter |
|------|--------|---------|
| 1 | Clear `C:\Windows\SoftwareDistribution\Download\*` | bytes freed |
| 2 | Clear `$env:TEMP` recursively | bytes freed + file count |
| 3 | Clear all event logs (`wevtutil el | wevtutil cl`) | log count |
| 4 | Remove PSReadLine history file | bytes freed |
| 5 | `Clear-History` | (current session only) |

### Safety
- Skip in-use files silently (`-ErrorAction SilentlyContinue` per step, but log the count of skipped items)
- Never touch `C:\Windows\Temp` unless explicitly opted in via `--include-windows-temp`
- Confirm prompt unless `-Force` / `-Yes` flag is passed

## Root dispatcher wiring (`run.ps1`)

```powershell
if ($Command -eq "os") {
    & "$PSScriptRoot\scripts\os\run.ps1" @Rest
    return
}
```

## Verification

```powershell
.\run.ps1 os clean -Yes
.\run.ps1 os clean       # should prompt for confirmation
```

## Open questions

None.
