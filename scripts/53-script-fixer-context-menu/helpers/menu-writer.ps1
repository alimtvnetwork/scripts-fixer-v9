<#
.SYNOPSIS
    Builds and tears down the cascading right-click menu registry tree
    for the Script Fixer context menu (script 53).

.DESCRIPTION
    All registry writes go through Microsoft.Win32.Registry::ClassesRoot
    (handles the HKCR\* wildcard correctly) except deletes, which use
    reg.exe delete /f for fully recursive removal.
#>

$_sharedDir   = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "shared"
$_loggingPath = Join-Path $_sharedDir "logging.ps1"
if ((Test-Path $_loggingPath) -and -not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . $_loggingPath
}

function ConvertTo-RegExePath {
    param([string]$PsPath)
    $p = $PsPath -replace '^Registry::', ''
    $p = $p -replace '^HKEY_CLASSES_ROOT',  'HKCR'
    $p = $p -replace '^HKEY_CURRENT_USER',  'HKCU'
    $p = $p -replace '^HKEY_LOCAL_MACHINE', 'HKLM'
    return $p
}

function Get-HkcrSubkeyPath {
    <#
    .SYNOPSIS
        Strips the "Registry::HKEY_CLASSES_ROOT\" prefix from a path so it
        can be passed to [Registry]::ClassesRoot.CreateSubKey(...).
    #>
    param([string]$PsPath)
    return ($PsPath -replace '^Registry::HKEY_CLASSES_ROOT\\', '')
}

function Remove-MenuTree {
    <#
    .SYNOPSIS
        Recursively removes a menu tree at $TopKey via reg.exe delete /f.
        Returns $true on success or when the key was already absent.
    #>
    param(
        [string]$TopKey,
        $LogMsgs
    )

    $regPath = ConvertTo-RegExePath $TopKey
    $null = reg.exe query $regPath 2>&1
    $isPresent = ($LASTEXITCODE -eq 0)

    if (-not $isPresent) {
        Write-Log ($LogMsgs.messages.wipeNothingToDo -replace '\{topKey\}', $regPath) -Level "info"
        return $true
    }

    Write-Log ($LogMsgs.messages.wipingPrevious -replace '\{topKey\}', $regPath) -Level "info"
    $null = reg.exe delete $regPath /f 2>&1
    $hasFailed = ($LASTEXITCODE -ne 0)
    if ($hasFailed) {
        $msg = ($LogMsgs.messages.regDeleteFailed -replace '\{path\}', $regPath) -replace '\{error\}', ("reg.exe exit " + $LASTEXITCODE)
        Write-Log $msg -Level "error"
        return $false
    }
    Write-Log ($LogMsgs.messages.wipeOk -replace '\{topKey\}', $regPath) -Level "success"
    return $true
}

function New-CascadingParent {
    <#
    .SYNOPSIS
        Writes a registry key configured as a cascading-menu parent
        (MUIVerb + SubCommands="").
    #>
    param(
        [string]$PsPath,
        [string]$Label,
        [string]$IconPath,
        [bool]$WithLuaShield = $false,
        $LogMsgs
    )

    $sub = Get-HkcrSubkeyPath $PsPath
    try {
        $hkcr = [Microsoft.Win32.Registry]::ClassesRoot
        $key  = $hkcr.CreateSubKey($sub)
        $key.SetValue("",            $Label)
        $key.SetValue("MUIVerb",     $Label)
        $key.SetValue("SubCommands", "")
        if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
            $key.SetValue("Icon", $IconPath)
        }
        if ($WithLuaShield) {
            $key.SetValue("HasLUAShield", "")
        }
        $key.Close()
        return $true
    } catch {
        $msg = ($LogMsgs.messages.regWriteFailed -replace '\{path\}', $PsPath) -replace '\{error\}', $_
        Write-Log $msg -Level "error"
        return $false
    }
}

function New-LeafEntry {
    <#
    .SYNOPSIS
        Writes a leaf menu entry (label + Icon + HasLUAShield) and its
        \command subkey with the supplied command line.

    .PARAMETER Extended
        When $true, sets the 'Extended' registry value (empty string), which
        makes the leaf appear ONLY when the user holds SHIFT while
        right-clicking. Used for the "no prompt" twin of each script leaf.
    #>
    param(
        [string]$ParentPsPath,
        [string]$LeafSubkey,
        [string]$Label,
        [string]$IconPath,
        [string]$CommandLine,
        [bool]$Extended = $false,
        $LogMsgs
    )

    $leafPs = "$ParentPsPath\$LeafSubkey"
    $leafSub = Get-HkcrSubkeyPath $leafPs
    try {
        $hkcr = [Microsoft.Win32.Registry]::ClassesRoot
        $key  = $hkcr.CreateSubKey($leafSub)
        $key.SetValue("",             $Label)
        $key.SetValue("HasLUAShield", "")
        if ($Extended) {
            # Windows hides this entry unless SHIFT is held during right-click
            $key.SetValue("Extended", "")
        }
        if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
            $key.SetValue("Icon", $IconPath)
        }
        $key.Close()

        $cmdKey = $hkcr.CreateSubKey("$leafSub\command")
        $cmdKey.SetValue("", $CommandLine)
        $cmdKey.Close()
        return $true
    } catch {
        $msg = ($LogMsgs.messages.regWriteFailed -replace '\{path\}', $leafPs) -replace '\{error\}', $_
        Write-Log $msg -Level "error"
        return $false
    }
}

function Test-MenuKeyExists {
    param([string]$PsPath)
    $regPath = ConvertTo-RegExePath $PsPath
    $null = reg.exe query $regPath 2>&1
    return ($LASTEXITCODE -eq 0)
}
