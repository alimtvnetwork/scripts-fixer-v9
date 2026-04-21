<#
.SYNOPSIS
    Install logic for the VS Code menu installer (script 54).

.DESCRIPTION
    Writes the three context menu registry keys per edition (file, folder,
    folder background). Does NOT enumerate or touch any other registry
    location. Caller passes the resolved VS Code executable path.
#>

$_sharedDir   = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "shared"
$_loggingPath = Join-Path $_sharedDir "logging.ps1"
if ((Test-Path $_loggingPath) -and -not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . $_loggingPath
}

function Get-HkcrSubkeyPath {
    param([string]$PsPath)
    return ($PsPath -replace '^Registry::HKEY_CLASSES_ROOT\\', '')
}

function ConvertTo-RegExePath {
    param([string]$PsPath)
    $p = $PsPath -replace '^Registry::', ''
    return ($p -replace '^HKEY_CLASSES_ROOT', 'HKCR')
}

function Register-VsCodeMenuEntry {
    <#
    .SYNOPSIS
        Writes a single context menu entry: parent key with (Default)+Icon,
        and a \command subkey with the command line.
    #>
    param(
        [string]$TargetName,         # "file" | "directory" | "background"
        [string]$RegistryPath,       # full Registry:: path from config
        [string]$Label,              # menu label
        [string]$VsCodeExe,          # resolved exe path
        [string]$CommandTemplate,    # template with {exe}
        $LogMsgs
    )

    $cmdLine = $CommandTemplate -replace '\{exe\}', $VsCodeExe
    Write-Log (($LogMsgs.messages.writingTarget -replace '\{target\}', $TargetName) -replace '\{path\}', $RegistryPath) -Level "info"
    Write-Log ($LogMsgs.messages.writingCommand -replace '\{command\}', $cmdLine) -Level "info"

    try {
        $sub  = Get-HkcrSubkeyPath $RegistryPath
        $hkcr = [Microsoft.Win32.Registry]::ClassesRoot

        $key = $hkcr.CreateSubKey($sub)
        $key.SetValue("",     $Label)
        $key.SetValue("Icon", "`"$VsCodeExe`"")
        $key.Close()

        $cmdKey = $hkcr.CreateSubKey("$sub\command")
        $cmdKey.SetValue("", $cmdLine)
        $cmdKey.Close()

        Write-Log ($LogMsgs.messages.writeOk -replace '\{path\}', $RegistryPath) -Level "success"
        return $true
    } catch {
        $msg = ($LogMsgs.messages.writeFailed -replace '\{path\}', $RegistryPath) -replace '\{error\}', $_
        Write-Log $msg -Level "error"
        return $false
    }
}

function Test-VsCodeMenuEntry {
    param(
        [string]$TargetName,
        [string]$RegistryPath,
        $LogMsgs
    )

    $regPath = ConvertTo-RegExePath $RegistryPath
    $null = reg.exe query $regPath 2>&1
    $isPresent = ($LASTEXITCODE -eq 0)
    if ($isPresent) {
        Write-Log ((($LogMsgs.messages.verifyPass -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath)) -Level "success"
        return $true
    }
    Write-Log ((($LogMsgs.messages.verifyMiss -replace '\{target\}', $TargetName) -replace '\{path\}', $regPath)) -Level "error"
    return $false
}

function Resolve-VsCodeExecutable {
    <#
    .SYNOPSIS
        Resolves the VS Code exe for an edition.
        Override > config path expansion.
    #>
    param(
        [string]$EditionName,
        [string]$ConfigPath,
        [string]$Override,
        $LogMsgs
    )

    Write-Log ($LogMsgs.messages.resolvingExe -replace '\{name\}', $EditionName) -Level "info"

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        Write-Log ($LogMsgs.messages.exeOverride -replace '\{path\}', $Override) -Level "info"
        $isOverridePresent = Test-Path -LiteralPath $Override
        if ($isOverridePresent) {
            Write-Log ($LogMsgs.messages.exeOk -replace '\{path\}', $Override) -Level "success"
            return $Override
        }
        $msg = ($LogMsgs.messages.exeMissing -replace '\{path\}', $Override) -replace '\{name\}', $EditionName
        Write-Log $msg -Level "error"
        return $null
    }

    $expanded = [System.Environment]::ExpandEnvironmentVariables($ConfigPath)
    Write-Log ($LogMsgs.messages.exeFromConfig -replace '\{path\}', $expanded) -Level "info"
    $isPresent = Test-Path -LiteralPath $expanded
    if (-not $isPresent) {
        $msg = ($LogMsgs.messages.exeMissing -replace '\{path\}', $expanded) -replace '\{name\}', $EditionName
        Write-Log $msg -Level "error"
        return $null
    }
    Write-Log ($LogMsgs.messages.exeOk -replace '\{path\}', $expanded) -Level "success"
    return $expanded
}
