<#
.SYNOPSIS
    Bumps the project version in scripts/version.json (the single source of truth).

.DESCRIPTION
    Updates the version in scripts/version.json using semantic versioning.
    Supports major, minor, and patch bumps, or an explicit version string.

.PARAMETER Major
    Bump the major version (e.g. 0.3.0 -> 1.0.0).

.PARAMETER Minor
    Bump the minor version (e.g. 0.3.0 -> 0.4.0).

.PARAMETER Patch
    Bump the patch version (e.g. 0.3.0 -> 0.3.1).

.PARAMETER Set
    Set an explicit version string (e.g. -Set "2.1.0").

.EXAMPLE
    .\bump-version.ps1 -Patch
    .\bump-version.ps1 -Minor
    .\bump-version.ps1 -Major
    .\bump-version.ps1 -Set "1.0.0"
#>

param(
    [switch]$Major,
    [switch]$Minor,
    [switch]$Patch,
    [string]$Set
)

$ErrorActionPreference = "Stop"

$versionFile = Join-Path $PSScriptRoot "scripts" "version.json"

$isVersionFilePresent = Test-Path $versionFile
if (-not $isVersionFilePresent) {
    Write-Host "[ FAIL ] scripts/version.json not found." -ForegroundColor Red
    exit 1
}

$versionData = Get-Content $versionFile -Raw | ConvertFrom-Json
$currentVersion = $versionData.version

Write-Host "Current version: $currentVersion" -ForegroundColor Cyan

# ── Determine new version ────────────────────────────────────────────────────

$parts = $currentVersion -split "\."
$vMajor = [int]$parts[0]
$vMinor = [int]$parts[1]
$vPatch = [int]$parts[2]

if ($Set) {
    $isValidFormat = $Set -match "^\d+\.\d+\.\d+$"
    if (-not $isValidFormat) {
        Write-Host "[ FAIL ] Invalid version format. Use Major.Minor.Patch (e.g. 1.2.3)." -ForegroundColor Red
        exit 1
    }
    $newVersion = $Set
}
elseif ($Major) {
    $vMajor++
    $vMinor = 0
    $vPatch = 0
    $newVersion = "$vMajor.$vMinor.$vPatch"
}
elseif ($Minor) {
    $vMinor++
    $vPatch = 0
    $newVersion = "$vMajor.$vMinor.$vPatch"
}
elseif ($Patch) {
    $vPatch++
    $newVersion = "$vMajor.$vMinor.$vPatch"
}
else {
    Write-Host "Usage: .\bump-version.ps1 -Major | -Minor | -Patch | -Set <version>" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  -Major   Bump major (e.g. 0.3.0 -> 1.0.0)"
    Write-Host "  -Minor   Bump minor (e.g. 0.3.0 -> 0.4.0)"
    Write-Host "  -Patch   Bump patch (e.g. 0.3.0 -> 0.3.1)"
    Write-Host '  -Set     Explicit version (e.g. -Set "2.1.0")'
    exit 0
}

$isSameVersion = $newVersion -eq $currentVersion
if ($isSameVersion) {
    Write-Host "[ SKIP ] Version is already $currentVersion." -ForegroundColor Yellow
    exit 0
}

# ── Write scripts/version.json ───────────────────────────────────────────────

$newData = @{ version = $newVersion } | ConvertTo-Json -Depth 1
Set-Content -Path $versionFile -Value $newData -Encoding UTF8

Write-Host "[ OK ] scripts/version.json: $currentVersion -> $newVersion" -ForegroundColor Green

# ── Regenerate spec/script-registry-summary.md ───────────────────────────────
# Keeps the registry summary in lock-step with scripts/registry.json +
# per-script config.json. CI also runs this and fails on drift -- doing it
# here means a local `bump-version.ps1` push will never trip the CI check.

$generatorScript = Join-Path $PSScriptRoot "scripts" "_internal" "generate-registry-summary.cjs"
$isGeneratorPresent = Test-Path $generatorScript
if ($isGeneratorPresent) {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    $isNodeAvailable = $null -ne $nodeCmd
    if ($isNodeAvailable) {
        Write-Host ""
        Write-Host "Regenerating spec/script-registry-summary.md ..." -ForegroundColor Cyan
        & node $generatorScript | Out-Host
        $isGeneratorOk = $LASTEXITCODE -eq 0
        if ($isGeneratorOk) {
            Write-Host "[ OK ] spec/script-registry-summary.md regenerated" -ForegroundColor Green
        }
        else {
            Write-Host "[ WARN ] generate-registry-summary.cjs exited with code $LASTEXITCODE" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[ SKIP ] node not found on PATH -- skipping registry summary regen." -ForegroundColor Yellow
        Write-Host "         Run manually before tagging: node scripts/_internal/generate-registry-summary.cjs" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "[ SKIP ] $generatorScript not found -- skipping registry summary regen." -ForegroundColor Yellow
}

# ── Update changelog badge in readme.md ──────────────────────────────────────

$readmeFile = Join-Path $PSScriptRoot "readme.md"
$isReadmePresent = Test-Path $readmeFile
if ($isReadmePresent) {
    $readmeContent = Get-Content $readmeFile -Raw
    $badgePattern = "Changelog-v[\d\.]+-(orange|blue|green|red|yellow)"
    $badgeReplacement = "Changelog-v$newVersion-orange"
    $updatedReadme = $readmeContent -replace $badgePattern, $badgeReplacement
    $isReadmeChanged = $updatedReadme -ne $readmeContent
    if ($isReadmeChanged) {
        Set-Content -Path $readmeFile -Value $updatedReadme -Encoding UTF8
        Write-Host "[ OK ] readme.md: Changelog badge -> v$newVersion" -ForegroundColor Green
    }
    else {
        Write-Host "[ SKIP ] readme.md: No Changelog badge found to update." -ForegroundColor Yellow
    }
}

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Version bumped to $newVersion" -ForegroundColor Magenta
Write-Host "All scripts will pick up the new version via Write-Banner automatically." -ForegroundColor DarkGray
