<#
.SYNOPSIS
    Reusable confirmation helper for context-menu / scripted launches.

.DESCRIPTION
    Invoke-ConfirmedLaunch shows a countdown and then runs a script (or any
    command). Press Ctrl+C during the countdown to cancel; press any key to
    skip the countdown and proceed immediately.

    Designed to be invoked from a context-menu command line such as:

      pwsh -NoExit -ExecutionPolicy Bypass -Command
        ". 'C:\repo\scripts\shared\confirm-launch.ps1';
         Invoke-ConfirmedLaunch -RepoRoot 'C:\repo' -ScriptId '52'
                                -ScriptLabel '52 -- vscode-folder-repair'
                                -CountdownSeconds 5"

    Any caller (script 53, future menus, anything) can reuse it -- this file
    is the single source of truth for "ask first, then run".
#>

Set-StrictMode -Version Latest

function Invoke-ConfirmedLaunch {
    <#
    .SYNOPSIS
        Show a countdown, then invoke the project dispatcher with -I <id>.

    .PARAMETER RepoRoot
        Absolute path to the repo root (where run.ps1 lives).

    .PARAMETER ScriptId
        Numeric ID from scripts/registry.json (e.g. "52").

    .PARAMETER ScriptLabel
        Friendly label shown in the prompt (e.g. "52 -- vscode-folder-repair").

    .PARAMETER CountdownSeconds
        Seconds to wait before auto-proceeding. <= 0 means "no prompt, run now".

    .PARAMETER Bypass
        Skip the countdown entirely (for Shift-click "no prompt" leaves).

    .PARAMETER ExtraArgs
        Additional positional args appended to `& .\run.ps1 -I <id>`.
    #>
    param(
        [Parameter(Mandatory)] [string]$RepoRoot,
        [Parameter(Mandatory)] [string]$ScriptId,
        [string]$ScriptLabel = "",
        [int]$CountdownSeconds = 5,
        [switch]$Bypass,
        [string[]]$ExtraArgs = @()
    )

    $isRepoMissing = -not (Test-Path -LiteralPath $RepoRoot)
    if ($isRepoMissing) {
        Write-Host ""
        Write-Host "[confirm-launch] FATAL: repo root not found: $RepoRoot" -ForegroundColor Red
        return
    }

    $runPs1 = Join-Path $RepoRoot "run.ps1"
    $isRunMissing = -not (Test-Path -LiteralPath $runPs1)
    if ($isRunMissing) {
        Write-Host ""
        Write-Host "[confirm-launch] FATAL: dispatcher not found: $runPs1" -ForegroundColor Red
        return
    }

    if ([string]::IsNullOrWhiteSpace($ScriptLabel)) { $ScriptLabel = "script $ScriptId" }

    $isBypass = $Bypass.IsPresent -or ($CountdownSeconds -le 0)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host (" Script Fixer launcher") -ForegroundColor Cyan
    Write-Host (" Target  : {0}" -f $ScriptLabel) -ForegroundColor White
    Write-Host (" Repo    : {0}" -f $RepoRoot)    -ForegroundColor DarkGray
    Write-Host (" Command : run.ps1 -I {0} {1}" -f $ScriptId, ($ExtraArgs -join ' ')) -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor DarkCyan

    if (-not $isBypass) {
        Write-Host ""
        Write-Host (" Auto-proceeding in {0}s. Press Ctrl+C to cancel, any key to skip." -f $CountdownSeconds) -ForegroundColor Yellow

        $isCancelled = $false
        try {
            for ($remaining = $CountdownSeconds; $remaining -gt 0; $remaining--) {
                Write-Host (" -> {0}..." -f $remaining) -ForegroundColor Yellow -NoNewline
                # Poll for keypress in 100ms slices for snappy skip-to-proceed
                $isKeyPressed = $false
                for ($i = 0; $i -lt 10; $i++) {
                    if ([Console]::KeyAvailable) {
                        [void][Console]::ReadKey($true)
                        $isKeyPressed = $true
                        break
                    }
                    Start-Sleep -Milliseconds 100
                }
                Write-Host ""
                if ($isKeyPressed) {
                    Write-Host " Key pressed -- proceeding now." -ForegroundColor Green
                    break
                }
            }
        } catch {
            $isCancelled = $true
        }

        if ($isCancelled) {
            Write-Host ""
            Write-Host " Cancelled by user -- script NOT executed." -ForegroundColor Red
            return
        }
    } else {
        Write-Host ""
        Write-Host " Bypass mode -- proceeding immediately (no prompt)." -ForegroundColor DarkGreen
    }

    Write-Host ""
    Write-Host (" Launching {0}..." -f $ScriptLabel) -ForegroundColor Green
    Write-Host ""

    Set-Location -LiteralPath $RepoRoot
    & $runPs1 -I $ScriptId @ExtraArgs
}

function Invoke-ConfirmedCommand {
    <#
    .SYNOPSIS
        Sibling of Invoke-ConfirmedLaunch for callers that already have a
        fully-formed command line (e.g. script 54 launching VS Code directly,
        not the project dispatcher). Same countdown / Ctrl+C / any-key
        behavior, no -I dispatch.

    .PARAMETER CommandLine
        The full command to run after the countdown. Executed via cmd.exe /c
        so quoting matches what Explorer would have run.

    .PARAMETER Label
        Friendly label shown in the prompt.

    .PARAMETER CountdownSeconds
        Seconds to wait before auto-proceeding. <= 0 means "no prompt".

    .PARAMETER Bypass
        Skip the countdown entirely.
    #>
    param(
        [Parameter(Mandatory)] [string]$CommandLine,
        [string]$Label = "command",
        [int]$CountdownSeconds = 5,
        [switch]$Bypass
    )

    $isBypass = $Bypass.IsPresent -or ($CountdownSeconds -le 0)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host (" Script Fixer launcher (generic)") -ForegroundColor Cyan
    Write-Host (" Target  : {0}" -f $Label)       -ForegroundColor White
    Write-Host (" Command : {0}" -f $CommandLine) -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor DarkCyan

    if (-not $isBypass) {
        Write-Host ""
        Write-Host (" Auto-proceeding in {0}s. Press Ctrl+C to cancel, any key to skip." -f $CountdownSeconds) -ForegroundColor Yellow

        $isCancelled = $false
        try {
            for ($remaining = $CountdownSeconds; $remaining -gt 0; $remaining--) {
                Write-Host (" -> {0}..." -f $remaining) -ForegroundColor Yellow -NoNewline
                $isKeyPressed = $false
                for ($i = 0; $i -lt 10; $i++) {
                    if ([Console]::KeyAvailable) {
                        [void][Console]::ReadKey($true)
                        $isKeyPressed = $true
                        break
                    }
                    Start-Sleep -Milliseconds 100
                }
                Write-Host ""
                if ($isKeyPressed) {
                    Write-Host " Key pressed -- proceeding now." -ForegroundColor Green
                    break
                }
            }
        } catch {
            $isCancelled = $true
        }

        if ($isCancelled) {
            Write-Host ""
            Write-Host " Cancelled by user -- command NOT executed." -ForegroundColor Red
            return
        }
    } else {
        Write-Host ""
        Write-Host " Bypass mode -- proceeding immediately (no prompt)." -ForegroundColor DarkGreen
    }

    Write-Host ""
    Write-Host (" Launching {0}..." -f $Label) -ForegroundColor Green
    Write-Host ""

    & cmd.exe /c $CommandLine
}
