<#
.SYNOPSIS
    Builds an ordered category -> scripts mapping from scripts/registry.json.

.DESCRIPTION
    Auto-categorizes each registry entry. Strategy:
      1. Strip the leading 'NN-' numeric prefix from the folder name.
      2. Look up the stripped name in $CategoryMap (from config.json).
      3. Fall back to the heuristic Get-CategoryFromFolder.
    Sorts categories alphabetically. Within a category, sorts by numeric ID.
    Optionally flattens single-item categories into a top-level "_root" bucket.
#>

$_sharedDir   = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "shared"
$_loggingPath = Join-Path $_sharedDir "logging.ps1"
if ((Test-Path $_loggingPath) -and -not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . $_loggingPath
}

function Get-StrippedFolderName {
    param([string]$Folder)
    return ($Folder -replace '^\d+-', '')
}

function Get-CategoryFromFolder {
    <#
    .SYNOPSIS
        Heuristic fallback when the folder is not in $CategoryMap.
    #>
    param([string]$Folder)
    $stripped = Get-StrippedFolderName $Folder
    switch -Regex ($stripped) {
        '^(databases|install-(mysql|mariadb|postgresql|mongodb|redis|couchdb|cassandra|neo4j|elasticsearch|duckdb|litedb|sqlite))$' { return "Databases" }
        '^(install-ollama|install-llama-cpp|models)$'                                                                                 { return "AI Models" }
        '^(install-vscode|vscode-settings-sync|install-notepadpp|install-dbeaver|install-gitmap|install-windows-terminal|install-conemu)$' { return "Editors & IDEs" }
        '(context-menu|folder-repair)'                                                                                                { return "Context Menu Fixers" }
        '^(windows-tweaks|install-winget|install-powershell|install-ubuntu-font)$'                                                    { return "Windows" }
        '^(install-docker|install-kubernetes)$'                                                                                       { return "Containers" }
        '^install-(nodejs|pnpm|python|golang|cpp|php|flutter|dotnet|java|rust|python-libs)$'                                          { return "Languages & Runtimes" }
        '^(install-git|install-github-desktop|git-tools)$'                                                                            { return "Git" }
        '^install-all-dev-tools$'                                                                                                     { return "Bundles" }
        '^(audit)$'                                                                                                                   { return "Audit" }
        '^(scan)$'                                                                                                                    { return "Scan" }
        '^(os)$'                                                                                                                      { return "OS Utilities" }
        '^(profile)$'                                                                                                                 { return "Profile" }
        '^install-'                                                                                                                   { return "Apps" }
        default                                                                                                                       { return "Other" }
    }
}

function Get-LeafLabel {
    <#
    .SYNOPSIS
        Visible label for a script leaf. Format: "NN -- pretty-name".
    #>
    param([string]$Id, [string]$Folder)
    $pretty = Get-StrippedFolderName $Folder
    return "$Id -- $pretty"
}

function ConvertTo-SafeSubkey {
    <#
    .SYNOPSIS
        Returns a string usable as a registry subkey name.
        Strips characters that cause issues with reg.exe / Explorer.
    #>
    param([string]$Name, [int]$MaxLen = 60)
    $clean = $Name -replace '[\\\/\:\*\?\"\<\>\|]', ''
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()
    if ($clean.Length -gt $MaxLen) { $clean = $clean.Substring(0, $MaxLen).TrimEnd() }
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = "Item" }
    return $clean
}

function Get-ScriptCategorization {
    <#
    .SYNOPSIS
        Reads registry.json and returns an ordered list of:
          @{ Category = "Databases"; Items = @( @{Id="18"; Folder="18-install-mysql"; Label="18 -- install-mysql"}, ... ) }

    .PARAMETER RegistryJsonPath
        Absolute path to scripts/registry.json
    .PARAMETER CategoryMap
        Hashtable / PSObject from config.json (folder-stripped-name -> category label).
    .PARAMETER FlattenSingletons
        When $true, categories that contain exactly 1 item are flattened into a
        single "_root" bucket which the menu writer renders at the top level
        instead of inside its own one-item submenu.
    #>
    param(
        [string]$RegistryJsonPath,
        $CategoryMap,
        [bool]$FlattenSingletons = $true
    )

    $isRegistryPresent = Test-Path $RegistryJsonPath
    if (-not $isRegistryPresent) {
        throw "registry.json not found at $RegistryJsonPath"
    }

    $reg = Get-Content -LiteralPath $RegistryJsonPath -Raw | ConvertFrom-Json

    # Build hashtable lookup from PSCustomObject (config.json categoryMap)
    $mapLookup = @{}
    if ($CategoryMap) {
        foreach ($prop in $CategoryMap.PSObject.Properties) {
            $isComment = $prop.Name -eq '_comment'
            if ($isComment) { continue }
            $mapLookup[$prop.Name] = $prop.Value
        }
    }

    # Group scripts by category
    $byCategory = @{}
    foreach ($prop in $reg.scripts.PSObject.Properties) {
        $id     = $prop.Name
        $folder = $prop.Value

        $strip = Get-StrippedFolderName $folder
        $cat   = $null
        if ($mapLookup.ContainsKey($strip)) {
            $cat = $mapLookup[$strip]
        } else {
            $cat = Get-CategoryFromFolder $folder
        }

        if (-not $byCategory.ContainsKey($cat)) {
            $byCategory[$cat] = @()
        }
        $byCategory[$cat] += [PSCustomObject]@{
            Id     = $id
            Folder = $folder
            Label  = Get-LeafLabel -Id $id -Folder $folder
        }
    }

    # Sort items inside each category by numeric ID where possible, else lexical.
    foreach ($cat in @($byCategory.Keys)) {
        $byCategory[$cat] = $byCategory[$cat] | Sort-Object @{Expression = {
            $n = 0
            $isNumeric = [int]::TryParse($_.Id, [ref]$n)
            if ($isNumeric) { $n } else { 999999 }
        }}, Id
    }

    # Flatten singletons into a special "_root" bucket
    $rootItems = @()
    if ($FlattenSingletons) {
        foreach ($cat in @($byCategory.Keys)) {
            $count = @($byCategory[$cat]).Count
            $isSingleton = ($count -eq 1)
            if ($isSingleton) {
                $rootItems += $byCategory[$cat][0]
                $byCategory.Remove($cat)
            }
        }
        if ($rootItems.Count -gt 0) {
            $rootItems = $rootItems | Sort-Object @{Expression = {
                $n = 0
                $isNumeric = [int]::TryParse($_.Id, [ref]$n)
                if ($isNumeric) { $n } else { 999999 }
            }}, Id
        }
    }

    # Build ordered output: alphabetical categories, then "_root" (singletons) at the end.
    $ordered = @()
    foreach ($cat in ($byCategory.Keys | Sort-Object)) {
        $ordered += [PSCustomObject]@{
            Category = $cat
            Items    = @($byCategory[$cat])
        }
    }
    if ($rootItems.Count -gt 0) {
        $ordered += [PSCustomObject]@{
            Category = "_root"
            Items    = @($rootItems)
        }
    }

    return $ordered
}
