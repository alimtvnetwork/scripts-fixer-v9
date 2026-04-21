<#
.SYNOPSIS
    Resolves which PowerShell executable to use for launching scripts from
    the Script Fixer right-click menu.

.DESCRIPTION
    Order:
      1. pwsh.exe on PATH (Get-Command)
      2. Each path in $ShellConfig.pwshSearchPaths (env vars expanded)
      3. Legacy powershell.exe ($ShellConfig.legacyPath)
    Logs the exact failure path on each miss (CODE RED rule).
#>

$_sharedDir   = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "shared"
$_loggingPath = Join-Path $_sharedDir "logging.ps1"
if ((Test-Path $_loggingPath) -and -not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . $_loggingPath
}

function Resolve-ShellExe {
    param(
        $ShellConfig,
        $LogMsgs
    )

    $tried = @()

    # 1. PATH discovery
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $isFoundOnPath = $null -ne $cmd
    if ($isFoundOnPath -and (Test-Path $cmd.Source)) {
        Write-Log ($LogMsgs.messages.shellResolved -replace '\{path\}', $cmd.Source) -Level "success"
        return $cmd.Source
    }
    $tried += "PATH (Get-Command pwsh)"

    # 2. Configured search paths
    foreach ($raw in @($ShellConfig.pwshSearchPaths)) {
        $expanded = [System.Environment]::ExpandEnvironmentVariables($raw)
        $tried += $expanded
        $isPresent = Test-Path -LiteralPath $expanded -ErrorAction SilentlyContinue
        if ($isPresent) {
            Write-Log ($LogMsgs.messages.shellResolved -replace '\{path\}', $expanded) -Level "success"
            return $expanded
        }
    }

    # 3. Legacy powershell.exe
    $legacyExpanded = [System.Environment]::ExpandEnvironmentVariables($ShellConfig.legacyPath)
    $tried += $legacyExpanded
    $isLegacyPresent = Test-Path -LiteralPath $legacyExpanded -ErrorAction SilentlyContinue
    if ($isLegacyPresent) {
        Write-Log ($LogMsgs.messages.shellResolved -replace '\{path\}', $legacyExpanded) -Level "warn"
        return $legacyExpanded
    }

    Write-Log ($LogMsgs.messages.shellNotFound -replace '\{paths\}', ($tried -join '; ')) -Level "error"
    return $null
}
