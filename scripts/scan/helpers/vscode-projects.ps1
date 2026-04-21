<#
.SYNOPSIS
    Locate, read, upsert, and atomically write the VS Code Project Manager
    projects.json file for the alefragnani.project-manager extension.
#>

function Get-VSCodeProjectsJsonPath {
    <#
    .SYNOPSIS
        Returns the per-OS path to the VS Code Project Manager projects.json.
    #>
    $isWindowsHost = $env:OS -eq "Windows_NT" -or $IsWindows
    $isMacHost     = $false
    if (Get-Variable -Name IsMacOS -Scope Global -ErrorAction SilentlyContinue) {
        $isMacHost = $IsMacOS
    }
    $isLinuxHost = $false
    if (Get-Variable -Name IsLinux -Scope Global -ErrorAction SilentlyContinue) {
        $isLinuxHost = $IsLinux
    }

    if ($isWindowsHost) {
        $appData = $env:APPDATA
        $hasAppData = -not [string]::IsNullOrWhiteSpace($appData)
        if (-not $hasAppData) {
            $appData = Join-Path $env:USERPROFILE "AppData\Roaming"
        }
        return Join-Path $appData "Code\User\globalStorage\alefragnani.project-manager\projects.json"
    }

    if ($isMacHost) {
        return Join-Path $HOME "Library/Application Support/Code/User/globalStorage/alefragnani.project-manager/projects.json"
    }

    # Linux / fallback
    $xdg = $env:XDG_CONFIG_HOME
    $hasXdg = -not [string]::IsNullOrWhiteSpace($xdg)
    if (-not $hasXdg) { $xdg = Join-Path $HOME ".config" }
    return Join-Path $xdg "Code/User/globalStorage/alefragnani.project-manager/projects.json"
}

function Initialize-VSCodeProjectsJson {
    <#
    .SYNOPSIS
        Ensure the projects.json file (and its parent directory) exists.
        Seeds the file with an empty JSON array if missing.
    #>
    param([Parameter(Mandatory)] [string]$Path)

    $parentDir = Split-Path $Path -Parent
    $isParentMissing = -not (Test-Path $parentDir)
    if ($isParentMissing) {
        try {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        } catch {
            Write-FileError -FilePath $parentDir -Operation "create directory" -Reason $_ -Module "Initialize-VSCodeProjectsJson"
            throw
        }
    }

    $isFileMissing = -not (Test-Path $Path)
    if ($isFileMissing) {
        try {
            [System.IO.File]::WriteAllText($Path, "[]`n", [System.Text.UTF8Encoding]::new($false))
            Write-Log "Created empty projects.json at: $Path" -Level "info"
        } catch {
            Write-FileError -FilePath $Path -Operation "create" -Reason $_ -Module "Initialize-VSCodeProjectsJson"
            throw
        }
    }
}

function Read-VSCodeProjects {
    <#
    .SYNOPSIS
        Read projects.json into an array of PSCustomObject entries.
        Returns @() on empty file. Throws on parse failure (caller decides).
    #>
    param([Parameter(Mandatory)] [string]$Path)

    $isFilePresent = Test-Path $Path
    if (-not $isFilePresent) { return @() }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    } catch {
        Write-FileError -FilePath $Path -Operation "read" -Reason $_ -Module "Read-VSCodeProjects"
        throw
    }

    $hasContent = -not [string]::IsNullOrWhiteSpace($raw)
    if (-not $hasContent) { return @() }

    try {
        $parsed = $raw | ConvertFrom-Json
    } catch {
        Write-FileError -FilePath $Path -Operation "parse JSON" -Reason $_ -Module "Read-VSCodeProjects"
        throw
    }

    # Ensure array shape (single-object JSON would otherwise become a scalar)
    $isArray = $parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])
    if (-not $isArray) { return @($parsed) }
    return @($parsed)
}

function ConvertTo-RootPathKey {
    <#
    .SYNOPSIS
        Normalize a rootPath into a comparison key.
        Windows -> lowercase, no trailing slash. Unix -> trim trailing slash, case sensitive.
    #>
    param([string]$Value)
    $hasValue = -not [string]::IsNullOrWhiteSpace($Value)
    if (-not $hasValue) { return "" }

    $trimmed = $Value.TrimEnd([char]'\\', [char]'/')
    $isWindowsHost = $env:OS -eq "Windows_NT" -or $IsWindows
    if ($isWindowsHost) { return $trimmed.ToLowerInvariant() }
    return $trimmed
}

function Add-OrUpdateVSCodeProject {
    <#
    .SYNOPSIS
        Upsert a single discovered project into an in-memory array.
        Returns a string status: "added" | "updated" | "noop".
        On update, preserves user-managed fields (name, paths, tags, enabled, profile).
    #>
    param(
        [Parameter(Mandatory)] [System.Collections.ArrayList]$Entries,
        [Parameter(Mandatory)] [string]$RootPath,
        [Parameter(Mandatory)] [string]$DefaultName
    )

    $key = ConvertTo-RootPathKey -Value $RootPath
    $matchIndex = -1
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $e = $Entries[$i]
        $hasRoot = $null -ne $e -and $e.PSObject.Properties['rootPath']
        if (-not $hasRoot) { continue }
        $existingKey = ConvertTo-RootPathKey -Value "$($e.rootPath)"
        if ($existingKey -eq $key) {
            $matchIndex = $i
            break
        }
    }

    $isExisting = $matchIndex -ge 0
    if ($isExisting) {
        # Preserve everything; we never overwrite user-managed fields on scan.
        return "noop"
    }

    # New entry -- add with the schema fields VS Code Project Manager expects.
    $newEntry = [PSCustomObject][ordered]@{
        name     = $DefaultName
        rootPath = $RootPath
        paths    = @()
        tags     = @()
        enabled  = $true
        profile  = ""
    }
    [void]$Entries.Add($newEntry)
    return "added"
}

function Save-VSCodeProjects {
    <#
    .SYNOPSIS
        Atomically serialize the entries array to projects.json:
          1. Write to <path>.tmp-<pid>-<ticks>
          2. Move-Item -Force over the original
        Leaves the original untouched on any error.
    #>
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Entries
    )

    $entriesArr = @($Entries)
    try {
        $json = $entriesArr | ConvertTo-Json -Depth 10
        # ConvertTo-Json on an empty array yields "" -- normalize.
        $hasJson = -not [string]::IsNullOrWhiteSpace($json)
        if (-not $hasJson) { $json = "[]" }
        # If a single entry was serialized, ConvertTo-Json may emit an object
        # literal (no surrounding [...]). Guard against that.
        $trimmed = $json.TrimStart()
        if (-not $trimmed.StartsWith("[")) {
            $json = "[`n$json`n]"
        }
    } catch {
        Write-FileError -FilePath $Path -Operation "serialize JSON" -Reason $_ -Module "Save-VSCodeProjects"
        throw
    }

    $dir = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    $tmpName = "$leaf.tmp-$PID-$([DateTime]::UtcNow.Ticks)"
    $tmpPath = Join-Path $dir $tmpName

    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($tmpPath, $json + "`n", $utf8NoBom)
    } catch {
        Write-FileError -FilePath $tmpPath -Operation "write temp file" -Reason $_ -Module "Save-VSCodeProjects"
        if (Test-Path $tmpPath) {
            try { Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue } catch {}
        }
        throw
    }

    try {
        Move-Item -LiteralPath $tmpPath -Destination $Path -Force
    } catch {
        Write-FileError -FilePath $Path -Operation "move temp into place" -Reason $_ -Module "Save-VSCodeProjects"
        if (Test-Path $tmpPath) {
            try { Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue } catch {}
        }
        throw
    }
}
