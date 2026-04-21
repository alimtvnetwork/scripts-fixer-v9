<#
.SYNOPSIS
    Verbose registry-change trace logger.

.DESCRIPTION
    Dot-source this in any script that mutates the Windows registry so that
    `-Verbose` produces a per-script trace file under `.logs/` recording every
    Set / Get / Remove of a registry value or key, with timestamp, user,
    operation, full HKLM:\... or HKCU:\... path, value name, old value, new
    value, and outcome (OK / FAIL + reason).

    The trace is independent of the structured JSON log produced by
    `logging.ps1`. It is a plain-text sidecar designed to be tailed in a second
    terminal during troubleshooting:

        Get-Content .logs\os-fix-long-path-registry-trace.log -Wait -Tail 20

    Activation:
        Pass -Verbose to the host script (PowerShell CommonParameter). The
        trace file is created on the first call to Write-RegistryTrace; if
        -Verbose was never set, the function is a no-op and no file is
        created.

    Log file naming:
        .logs/<sanitised-script-name>-registry-trace.log

        Example:
          .logs/os-fix-long-path-registry-trace.log
          .logs/os-clean-explorer-mru-registry-trace.log

    CODE RED: every failure entry includes the exact failing registry path +
    the exception message verbatim. Never swallow a path on failure.
#>

# ── Module-scoped state ─────────────────────────────────────────────────────
$script:_RegTraceEnabled = $false
$script:_RegTracePath    = $null
$script:_RegTraceScript  = $null
# Counters + tail buffer for the end-of-run summary
$script:_RegTraceCounts  = @{ OK = 0; FAIL = 0; SKIP = 0 }
$script:_RegTraceTail    = New-Object System.Collections.Generic.Queue[string]
$script:_RegTraceTailMax = 20

function Initialize-RegistryTrace {
    <#
    .SYNOPSIS
        Wire the trace logger to a host script. Call once near the top of
        run.ps1 / longpath.ps1 / explorer-mru.ps1 after Initialize-Logging.

    .PARAMETER ScriptName
        Human-readable script name; sanitised into the log filename. Should
        match the value passed to Initialize-Logging so both files share a
        prefix.

    .PARAMETER VerboseEnabled
        Pass `$PSBoundParameters.ContainsKey('Verbose')` from the host script
        (StrictMode-safe; $VerbosePreference inheritance can be unreliable
        across `&` invocations).
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter(Mandatory)][bool]$VerboseEnabled
    )

    $script:_RegTraceEnabled = $VerboseEnabled
    $script:_RegTraceScript  = $ScriptName
    # Reset counters + tail buffer for this run
    $script:_RegTraceCounts  = @{ OK = 0; FAIL = 0; SKIP = 0 }
    $script:_RegTraceTail    = New-Object System.Collections.Generic.Queue[string]

    if (-not $VerboseEnabled) { return }

    # .logs/ at repo root (parent of scripts/) -- matches logging.ps1 layout
    $here = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $repoRoot = (Resolve-Path (Join-Path $here "..\..")).Path
    $logsDir = Join-Path $repoRoot ".logs"

    if (-not (Test-Path -LiteralPath $logsDir)) {
        try {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        } catch {
            Write-Host "  [ WARN ] Failed to create .logs/ at ${logsDir}: $($_.Exception.Message)" -ForegroundColor Yellow
            $script:_RegTraceEnabled = $false
            return
        }
    }

    $sanitised = ($ScriptName.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($sanitised)) { $sanitised = "registry" }
    $script:_RegTracePath = Join-Path $logsDir "$sanitised-registry-trace.log"

    $header = @(
        "================================================================================",
        "  Registry trace -- $ScriptName",
        "  Started:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
        "  User:     $env:USERDOMAIN\$env:USERNAME    (PID $PID)",
        "  Host:     $env:COMPUTERNAME",
        "  PSVer:    $($PSVersionTable.PSVersion)",
        "  Logfile:  $($script:_RegTracePath)",
        "================================================================================",
        ""
    ) -join [Environment]::NewLine

    try {
        Add-Content -LiteralPath $script:_RegTracePath -Value $header -Encoding UTF8
    } catch {
        Write-Host "  [ WARN ] Registry trace disabled -- cannot write $($script:_RegTracePath): $($_.Exception.Message)" -ForegroundColor Yellow
        $script:_RegTraceEnabled = $false
        return
    }

    Write-Host "  [ INFO ] Verbose registry trace enabled -> $($script:_RegTracePath)" -ForegroundColor Cyan
}

function Test-RegistryTraceEnabled {
    return [bool]$script:_RegTraceEnabled
}

function Write-RegistryTrace {
    <#
    .SYNOPSIS
        Append one trace line. No-op when -Verbose was not set.

    .PARAMETER Op
        One of: SET, GET, REMOVE-VALUE, REMOVE-KEY, READ-ONLY.

    .PARAMETER Path
        Full registry path (e.g. HKLM:\SYSTEM\CurrentControlSet\...).

    .PARAMETER Name
        Value name (omit for whole-key operations).

    .PARAMETER OldValue / NewValue
        Stringified old/new values for SET; either may be $null.

    .PARAMETER Status
        OK | FAIL | SKIP. Defaults to OK.

    .PARAMETER Reason
        Free-text reason; for FAIL this MUST contain the exception message.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet("SET","GET","REMOVE-VALUE","REMOVE-KEY","READ-ONLY")][string]$Op,
        [Parameter(Mandatory)][string]$Path,
        [string]$Name,
        $OldValue,
        $NewValue,
        [ValidateSet("OK","FAIL","SKIP")][string]$Status = "OK",
        [string]$Reason
    )

    $hasTrace = $script:_RegTraceEnabled -and $script:_RegTracePath
    if (-not $hasTrace) { return }

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"

    $oldStr = if ($null -eq $OldValue) { "<null>" } else { "$OldValue" }
    $newStr = if ($null -eq $NewValue) { "<null>" } else { "$NewValue" }
    $nameStr = if ([string]::IsNullOrEmpty($Name)) { "<key>" } else { $Name }

    $line = "[{0}] [{1,-12}] [{2,-4}] {3} :: {4}" -f $ts, $Op, $Status, $Path, $nameStr
    if ($Op -eq "SET") {
        $line += "  old=$oldStr  new=$newStr"
    } elseif ($Op -eq "GET" -or $Op -eq "READ-ONLY") {
        $line += "  value=$newStr"
    }
    $hasReason = -not [string]::IsNullOrWhiteSpace($Reason)
    if ($hasReason) {
        $line += "  reason=$Reason"
    }

    # Tally + remember tail (always, even if disk write fails afterwards)
    if ($script:_RegTraceCounts.ContainsKey($Status)) {
        $script:_RegTraceCounts[$Status]++
    }
    [void]$script:_RegTraceTail.Enqueue($line)
    while ($script:_RegTraceTail.Count -gt $script:_RegTraceTailMax) {
        [void]$script:_RegTraceTail.Dequeue()
    }

    try {
        Add-Content -LiteralPath $script:_RegTracePath -Value $line -Encoding UTF8
    } catch {
        # Last-ditch: complain to host once, then disable to avoid spam
        Write-Host "  [ WARN ] Registry trace write failed at $($script:_RegTracePath): $($_.Exception.Message)" -ForegroundColor Yellow
        $script:_RegTraceEnabled = $false
    }
}

function Get-RegistryTraceCounts {
    <#
    .SYNOPSIS
        Returns a hashtable @{ OK = N; FAIL = N; SKIP = N; Total = N } for the
        current run. Available even when -Verbose was not set (all zeros).
    #>
    $c = $script:_RegTraceCounts
    return @{
        OK    = [int]$c.OK
        FAIL  = [int]$c.FAIL
        SKIP  = [int]$c.SKIP
        Total = [int]($c.OK + $c.FAIL + $c.SKIP)
    }
}

function Show-RegistryTraceSummary {
    <#
    .SYNOPSIS
        Print the last <=20 trace lines and the OK/FAIL/SKIP totals to the
        host. Also appended to the trace logfile (when enabled). Safe to call
        when -Verbose was not set: prints a one-line "no operations" notice
        and returns.

    .PARAMETER TailLines
        How many recent lines to show. Defaults to 20.
    #>
    param([int]$TailLines = 20)

    $counts = Get-RegistryTraceCounts
    $hasTrace = $script:_RegTraceEnabled -and $script:_RegTracePath
    $hasOps   = $counts.Total -gt 0

    Write-Host ""
    Write-Host "  Registry trace summary" -ForegroundColor Cyan
    Write-Host "  ----------------------" -ForegroundColor DarkGray

    if (-not $hasOps) {
        if ($hasTrace) {
            Write-Host "    no registry operations recorded this run" -ForegroundColor DarkGray
        } else {
            Write-Host "    -Verbose not set; no trace collected (pass -Verbose to enable)" -ForegroundColor DarkGray
        }
        Write-Host ""
        return
    }

    # Print tail (most-recent-last)
    $maxShow = [Math]::Min($TailLines, $script:_RegTraceTail.Count)
    Write-Host "    last $maxShow of $($counts.Total) trace line(s):" -ForegroundColor DarkGray
    $tailArr = @($script:_RegTraceTail.ToArray())
    $start = [Math]::Max(0, $tailArr.Count - $TailLines)
    for ($i = $start; $i -lt $tailArr.Count; $i++) {
        $ln = $tailArr[$i]
        $color = "Gray"
        if     ($ln -match '\[FAIL\]') { $color = "Red" }
        elseif ($ln -match '\[SKIP\]') { $color = "Yellow" }
        elseif ($ln -match '\[OK\s*\]') { $color = "Green" }
        Write-Host "      $ln" -ForegroundColor $color
    }

    Write-Host ""
    Write-Host ("    totals: OK={0}  FAIL={1}  SKIP={2}  (total {3})" -f `
        $counts.OK, $counts.FAIL, $counts.SKIP, $counts.Total) -ForegroundColor Cyan
    if ($hasTrace) {
        Write-Host "    full log: $($script:_RegTracePath)" -ForegroundColor DarkGray
    }
    Write-Host ""

    # Mirror the summary into the trace logfile so it stays self-describing
    if ($hasTrace) {
        $block = @()
        $block += ""
        $block += "  --- summary (last $maxShow of $($counts.Total)) ---"
        for ($i = $start; $i -lt $tailArr.Count; $i++) {
            $block += "    " + $tailArr[$i]
        }
        $block += ("  totals: OK={0}  FAIL={1}  SKIP={2}  (total {3})" -f `
            $counts.OK, $counts.FAIL, $counts.SKIP, $counts.Total)
        $block += ""
        try {
            Add-Content -LiteralPath $script:_RegTracePath -Value ($block -join [Environment]::NewLine) -Encoding UTF8
        } catch {
            Write-Host "  [ WARN ] Could not append summary to $($script:_RegTracePath): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

function Close-RegistryTrace {
    <#
    .SYNOPSIS
        Append a footer with a one-line summary. Optional; safe if no trace.
    #>
    param(
        [string]$Status = "ok",
        [switch]$NoSummary
    )

    # Always print the one-command summary (last 20 + totals) unless suppressed.
    # Safe when -Verbose was not set: prints a one-line "no trace" notice.
    if (-not $NoSummary) {
        Show-RegistryTraceSummary -TailLines $script:_RegTraceTailMax
    }

    $hasTrace = $script:_RegTraceEnabled -and $script:_RegTracePath
    if (-not $hasTrace) { return }
    $footer = @(
        "",
        "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')   Status: $Status",
        "================================================================================",
        ""
    ) -join [Environment]::NewLine
    try { Add-Content -LiteralPath $script:_RegTracePath -Value $footer -Encoding UTF8 } catch {}
}

# ── Sweep-helper parser: detect -Verbose / --verbose in $Argv ───────────────
function Test-VerboseSwitch {
    <#
    .SYNOPSIS
        Same shape as Test-DryRunSwitch / Test-YesSwitch in _sweep.ps1.
        Recognises -Verbose, --verbose, -v (long form only -- we do NOT
        accept bare `-v` because cleaner CLIs already use `-y`).
    #>
    param([string[]]$Argv)
    if ($null -eq $Argv) { return $false }
    foreach ($a in $Argv) {
        $t = "$a".Trim().ToLower()
        if ($t -in @("--verbose","-verbose","/verbose")) { return $true }
    }
    return $false
}
