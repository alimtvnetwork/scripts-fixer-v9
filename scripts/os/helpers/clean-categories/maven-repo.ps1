<# Bucket F: maven-repo -- Maven local repository + wrapper distributions.
   Cleans:
     %USERPROFILE%\.m2\repository    (downloaded artifacts -- redownloaded on next build)
     %USERPROFILE%\.m2\wrapper\dists (mvnw distributions)
   SAFE: %USERPROFILE%\.m2\settings.xml, %USERPROFILE%\.m2\settings-security.xml,
         project pom.xml / target/, the wrapper script itself.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "maven-repo" -Label "Maven local repo + wrapper dists (settings.xml SAFE)" -Bucket "F"

$m2Root = Join-Path (Get-UserProfilePath) ".m2"
$hasM2 = Test-Path -LiteralPath $m2Root
if (-not $hasM2) {
    $result.Notes += "Maven not present (no $m2Root)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

foreach ($sub in @("repository", "wrapper\dists")) {
    $target = Join-Path $m2Root $sub
    $isPresent = Test-Path -LiteralPath $target
    if (-not $isPresent) { continue }
    Invoke-PathSweep -Path $target -Result $result -DryRun:$DryRun -LogPrefix "maven/$sub"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
