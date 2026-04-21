<#
.SYNOPSIS
    Directory walker that discovers project folders by marker files / dirs.
#>

function Test-IsProjectFolder {
    <#
    .SYNOPSIS
        Return $true if the given directory contains any project marker
        from $Markers. $Markers is a hashtable: @{ files=@(); patterns=@(); dirs=@() }.
    #>
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Markers
    )

    foreach ($f in @($Markers.files)) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        $candidate = Join-Path $Path $f
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true }
    }
    foreach ($d in @($Markers.dirs)) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        $candidate = Join-Path $Path $d
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $true }
    }
    foreach ($p in @($Markers.patterns)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $matches = Get-ChildItem -LiteralPath $Path -Filter $p -File -ErrorAction SilentlyContinue
        $hasMatches = $null -ne $matches -and @($matches).Count -gt 0
        if ($hasMatches) { return $true }
    }
    return $false
}

function Find-Projects {
    <#
    .SYNOPSIS
        Walk $Root recursively (bounded by $MaxDepth) and yield every directory
        that qualifies as a project (Test-IsProjectFolder). Once a directory
        qualifies, it is NOT descended into.
    #>
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] $Markers,
        [Parameter(Mandatory)] [string[]]$SkipDirs,
        [int]$MaxDepth = 5,
        [switch]$IncludeHidden
    )

    $results = New-Object System.Collections.Generic.List[string]
    $skipSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($s in $SkipDirs) {
        if (-not [string]::IsNullOrWhiteSpace($s)) { [void]$skipSet.Add($s) }
    }

    # Iterative DFS via stack of @{ Path; Depth }.
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push(@{ Path = $Root; Depth = 0 })

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $curPath = $current.Path
        $curDepth = $current.Depth

        $isPathPresent = Test-Path -LiteralPath $curPath -PathType Container
        if (-not $isPathPresent) { continue }

        # If this folder itself qualifies as a project, record it and DO NOT
        # descend further (avoids picking up nested node_modules-style noise).
        $isProject = Test-IsProjectFolder -Path $curPath -Markers $Markers
        if ($isProject) {
            [void]$results.Add($curPath)
            continue
        }

        # Depth guard
        if ($curDepth -ge $MaxDepth) { continue }

        $children = $null
        try {
            $children = Get-ChildItem -LiteralPath $curPath -Directory -Force -ErrorAction Stop
        } catch {
            Write-Log "Skipping unreadable directory: $curPath -- $_" -Level "warn"
            continue
        }

        foreach ($child in $children) {
            $name = $child.Name
            $isSkipped = $skipSet.Contains($name)
            if ($isSkipped) { continue }

            $isHidden = $name.StartsWith(".")
            if ($isHidden -and -not $IncludeHidden) { continue }

            $stack.Push(@{ Path = $child.FullName; Depth = $curDepth + 1 })
        }
    }

    return $results
}
