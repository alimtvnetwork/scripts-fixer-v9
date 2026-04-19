<#
.SYNOPSIS
    Recursively expand a profile into a flat list of concrete steps.
    Cycle-safe: aborts (returns $null) on circular profile references.
#>

function Expand-Profile {
    param(
        [Parameter(Mandatory)][PSObject]$Config,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][PSObject]$LogMessages,
        [System.Collections.Generic.HashSet[string]]$Visited,
        [System.Collections.Generic.List[string]]$Chain
    )

    $isVisitedNew = -not $Visited
    if ($isVisitedNew) { $Visited = [System.Collections.Generic.HashSet[string]]::new() }
    $isChainNew = -not $Chain
    if ($isChainNew)   { $Chain   = [System.Collections.Generic.List[string]]::new() }

    $isCycle = $Visited.Contains($Name)
    if ($isCycle) {
        $Chain.Add($Name) | Out-Null
        $msg = $LogMessages.messages.cycleDetected -replace '\{chain\}', ($Chain -join ' -> ')
        Write-Log $msg -Level "fail"
        return $null
    }

    $hasProfile = $null -ne $Config.profiles.$Name
    if (-not $hasProfile) {
        $msg = $LogMessages.messages.profileNotFound -replace '\{name\}', $Name
        Write-Log $msg -Level "fail"
        return $null
    }

    [void]$Visited.Add($Name)
    $Chain.Add($Name) | Out-Null

    $flat = [System.Collections.Generic.List[hashtable]]::new()
    $prof = $Config.profiles.$Name
    $steps = $prof.steps

    foreach ($s in $steps) {
        $kind = "$($s.kind)".ToLower()
        if ($kind -eq "profile") {
            $childName = "$($s.name)".ToLower()
            $childExpanded = Expand-Profile -Config $Config -Name $childName -LogMessages $LogMessages -Visited $Visited -Chain $Chain
            $isChildFailed = $null -eq $childExpanded
            if ($isChildFailed) { return $null }
            foreach ($c in $childExpanded) { $flat.Add($c) }
            continue
        }

        # Convert PSObject step to a hashtable copy for downstream mutation safety
        $entry = @{ kind = $kind }
        foreach ($p in $s.PSObject.Properties) {
            if ($p.Name -eq "kind") { continue }
            $entry[$p.Name] = $p.Value
        }
        # Synthesize a label if absent
        $hasLabel = -not [string]::IsNullOrWhiteSpace($entry.label)
        if (-not $hasLabel) {
            $entry.label = switch ($kind) {
                "script"     { "script id=$($entry.id)" }
                "choco"      { "choco install $($entry.package)" }
                "subcommand" { "$($entry.path)" }
                "inline"     { "$($entry.function)" }
                default      { "(unknown)" }
            }
        }
        $flat.Add($entry)
    }

    # Pop chain on the way out so siblings don't see this name as a "cycle"
    $idx = $Chain.Count - 1
    if ($idx -ge 0 -and $Chain[$idx] -eq $Name) {
        $Chain.RemoveAt($idx)
    }
    [void]$Visited.Remove($Name)

    return $flat
}
