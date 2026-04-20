<# Bucket F: gradle-cache -- ~/.gradle/caches + ~/.gradle/daemon + ~/.gradle/.tmp
   Equivalent to 'gradle --stop' + cache wipe. Build outputs and wrapper jars
   under each project's own .gradle/ are NOT touched (project-local cache).
   SAFE: gradle.properties, init.d scripts, the wrapper distribution itself.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "gradle-cache" -Label "Gradle user cache + daemon (gradle.properties + wrappers SAFE)" -Bucket "F"

$gradleRoot = Join-Path (Get-UserProfilePath) ".gradle"
$hasGradle = Test-Path -LiteralPath $gradleRoot
if (-not $hasGradle) {
    $result.Notes += "Gradle user dir not present (no $gradleRoot)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Stop daemons before wiping (best effort -- only on live runs)
if (-not $DryRun) {
    $gradleCmd = Get-Command "gradle" -ErrorAction SilentlyContinue
    if ($null -ne $gradleCmd) {
        try {
            & gradle --stop 2>$null | Out-Null
            $result.Notes += "Stopped Gradle daemons via 'gradle --stop'"
        } catch {
            Write-Log "gradle --stop failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

foreach ($sub in @("caches", "daemon", ".tmp", "native")) {
    $target = Join-Path $gradleRoot $sub
    $isPresent = Test-Path -LiteralPath $target
    if (-not $isPresent) { continue }
    Invoke-PathSweep -Path $target -Result $result -DryRun:$DryRun -LogPrefix "gradle/$sub"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
