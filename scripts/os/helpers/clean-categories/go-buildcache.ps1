<# Bucket F: go-buildcache -- Go's compiler build cache + module download cache.
   Cleans:
     %LOCALAPPDATA%\go-build                    (Go build cache -- 'go env GOCACHE')
     %USERPROFILE%\go\pkg\mod\cache\download    (module zip cache -- 'go env GOMODCACHE')
     'go clean -cache' + 'go clean -modcache' invoked when CLI is on PATH (best effort).
   SAFE: %USERPROFILE%\go\bin (installed binaries via 'go install'),
         project source code, go.mod / go.sum files.
#>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "go-buildcache" -Label "Go build cache + module downloads (~/go/bin SAFE)" -Bucket "F"

# Resolve via 'go env' when CLI is on PATH -- more accurate than guessing
$goCacheDir = $null
$goModCache = $null
$goCmd = Get-Command "go" -ErrorAction SilentlyContinue
if ($null -ne $goCmd) {
    try {
        $goCacheDir = (& go env GOCACHE 2>$null).Trim()
        $goModCache = (& go env GOMODCACHE 2>$null).Trim()
    } catch {
        Write-Log "go env probe failed: $($_.Exception.Message)" -Level "warn"
    }
    if (-not $DryRun) {
        try {
            & go clean -cache 2>$null | Out-Null
            & go clean -modcache 2>$null | Out-Null
            $result.Notes += "Invoked 'go clean -cache' + 'go clean -modcache' before path sweep"
        } catch {
            Write-Log "go clean failed: $($_.Exception.Message)" -Level "warn"
        }
    }
}

# Fallback defaults if 'go env' didn't answer
if ([string]::IsNullOrWhiteSpace($goCacheDir)) {
    $goCacheDir = Join-Path (Get-LocalAppDataPath) "go-build"
}
if ([string]::IsNullOrWhiteSpace($goModCache)) {
    $goModCache = Join-Path (Get-UserProfilePath) "go\pkg\mod"
}

$buildCache = $goCacheDir
$modDownload = Join-Path $goModCache "cache\download"

$foundAny = $false
if (Test-Path -LiteralPath $buildCache) {
    $foundAny = $true
    Invoke-PathSweep -Path $buildCache -Result $result -DryRun:$DryRun -LogPrefix "go/build-cache"
}
if (Test-Path -LiteralPath $modDownload) {
    $foundAny = $true
    Invoke-PathSweep -Path $modDownload -Result $result -DryRun:$DryRun -LogPrefix "go/mod-download"
}

if (-not $foundAny) {
    $result.Notes += "Go cache not present (no $buildCache, no $modDownload)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
