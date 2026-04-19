<# Bucket F: docker-dangling -- docker system prune -f #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "docker-dangling" -Label "Docker dangling images/containers/networks" -Bucket "F"

$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($null -eq $docker) {
    $result.Notes += "Docker CLI not installed"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Verify daemon is running before invoking prune
try {
    & docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $result.Notes += "Docker daemon not running -- skipped"
        Set-CleanResultStatus -Result $result -DryRun:$DryRun
        return $result
    }
} catch {
    $result.Notes += "Docker daemon unreachable: $($_.Exception.Message)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

if ($DryRun) {
    try {
        $danglingCount = (@(& docker images -f "dangling=true" -q 2>$null) | Where-Object { $_ }).Count
        $result.WouldCount = $danglingCount
        $result.Notes += "DRY-RUN: would run 'docker system prune -f' (dangling images: $danglingCount)"
    } catch {
        $result.Notes += "DRY-RUN: would run 'docker system prune -f' (count probe failed)"
    }
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

try {
    $output = & docker system prune -f 2>&1
    $result.Count = 1
    $result.Notes += "docker system prune output: $($output -join ' | ')"
    # Parse "Total reclaimed space: 1.234GB"
    if ($output -join "`n" -match "Total reclaimed space:\s*([\d.]+)\s*([KMGT]?B)") {
        $val = [double]$Matches[1]
        $unit = $Matches[2].ToUpper()
        $bytes = switch ($unit) {
            "B"  { $val }
            "KB" { $val * 1KB }
            "MB" { $val * 1MB }
            "GB" { $val * 1GB }
            "TB" { $val * 1TB }
            default { 0 }
        }
        $result.Bytes = [long]$bytes
    }
} catch {
    $result.Status = "fail"
    $result.Notes += "docker prune failed: $($_.Exception.Message)"
    Write-Log "docker prune failed: $($_.Exception.Message)" -Level "fail"
}
Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
