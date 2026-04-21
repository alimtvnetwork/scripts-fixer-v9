# --------------------------------------------------------------------------
#  Script 53 -- Script Fixer Context Menu
#  Opt-in cascading right-click menu titled "Script Fixer v{version}".
#  Reads scripts/registry.json, auto-categorizes, and writes a tree of
#  registry keys under each enabled scope (file / directory / background /
#  desktop). Each leaf launches an elevated pwsh that runs run.ps1 -I <id>.
# --------------------------------------------------------------------------
param(
    [Parameter(Position = 0)]
    [string]$Command = "install",

    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sharedDir = Join-Path (Split-Path -Parent $scriptDir) "shared"
$repoRoot  = Split-Path -Parent (Split-Path -Parent $scriptDir)

# -- Dot-source shared helpers ------------------------------------------------
. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "resolved.ps1")
. (Join-Path $sharedDir "git-pull.ps1")
. (Join-Path $sharedDir "help.ps1")
. (Join-Path $sharedDir "installed.ps1")

# -- Dot-source script helpers ------------------------------------------------
. (Join-Path $scriptDir "helpers\categorize.ps1")
. (Join-Path $scriptDir "helpers\shell-detect.ps1")
. (Join-Path $scriptDir "helpers\menu-writer.ps1")

# -- Load config & log messages -----------------------------------------------
$config      = Import-JsonConfig (Join-Path $scriptDir "config.json")
$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")

# -- Help ---------------------------------------------------------------------
if ($Help -or $Command -eq "--help") {
    Show-ScriptHelp -LogMessages $logMessages
    return
}

# -- Banner -------------------------------------------------------------------
Write-Banner -Title $logMessages.scriptName

# -- Initialize logging -------------------------------------------------------
Initialize-Logging -ScriptName $logMessages.scriptName

function Get-ProjectVersion {
    param([string]$RepoRoot, $LogMsgs)
    $verFile = Join-Path $RepoRoot "scripts\version.json"
    Write-Log ($LogMsgs.messages.loadingVersion -replace '\{path\}', $verFile) -Level "info"
    $isPresent = Test-Path -LiteralPath $verFile
    if (-not $isPresent) {
        Write-Log ($LogMsgs.messages.versionMissing -replace '\{path\}', $verFile) -Level "warn"
        return "unknown"
    }
    try {
        $data = Get-Content -LiteralPath $verFile -Raw | ConvertFrom-Json
        $v = $data.version
        Write-Log ($LogMsgs.messages.versionLoaded -replace '\{version\}', $v) -Level "success"
        return $v
    } catch {
        Write-Log ("Failed to parse version.json at {0} -- {1}" -f $verFile, $_) -Level "error"
        return "unknown"
    }
}

function Invoke-Uninstall {
    param($Config, $LogMsgs)
    Write-Log $LogMsgs.messages.uninstalling -Level "info"
    $isAllOk = $true
    foreach ($scopeName in $Config.scopes.PSObject.Properties.Name) {
        $scope  = $Config.scopes.$scopeName
        $topKey = $scope.topKey
        Write-Log ($LogMsgs.messages.uninstallScope -replace '\{topKey\}', (ConvertTo-RegExePath $topKey)) -Level "info"
        $ok = Remove-MenuTree -TopKey $topKey -LogMsgs $LogMsgs
        if (-not $ok) { $isAllOk = $false }
    }
    Remove-InstalledRecord -Name "script-fixer-context-menu" -ErrorAction SilentlyContinue
    Remove-ResolvedData    -ScriptFolder "53-script-fixer-context-menu" -ErrorAction SilentlyContinue
    Write-Log $LogMsgs.messages.uninstallComplete -Level "success"
    return $isAllOk
}

function Invoke-Install {
    param(
        $Config,
        $LogMsgs,
        [string]$RepoRoot,
        [string]$ScriptDir
    )

    # -- Disabled check --
    $isDisabled = -not $Config.enabled
    if ($isDisabled) {
        Write-Log $LogMsgs.messages.scriptDisabled -Level "warn"
        return $true
    }

    # -- Version + label --
    $version = Get-ProjectVersion -RepoRoot $RepoRoot -LogMsgs $LogMsgs
    $topLabel = $Config.titleTemplate -replace '\{version\}', $version
    Write-Log ($LogMsgs.messages.topLevelLabel -replace '\{label\}', $topLabel) -Level "info"

    # -- Shell exe --
    Write-Log $LogMsgs.messages.detectingShell -Level "info"
    $shellExe = Resolve-ShellExe -ShellConfig $Config.shell -LogMsgs $LogMsgs
    $isShellMissing = -not $shellExe
    if ($isShellMissing) { return $false }

    # -- Categorize --
    $regPath = Join-Path $RepoRoot "scripts\registry.json"
    Write-Log ($LogMsgs.messages.loadingRegistry -replace '\{path\}', $regPath) -Level "info"
    $isRegPresent = Test-Path -LiteralPath $regPath
    if (-not $isRegPresent) {
        Write-Log ($LogMsgs.messages.registryMissing -replace '\{path\}', $regPath) -Level "error"
        return $false
    }

    $categorized = Get-ScriptCategorization `
        -RegistryJsonPath $regPath `
        -CategoryMap      $Config.categoryMap `
        -FlattenSingletons ([bool]$Config.flattenSingletonCategories)

    $totalScripts = 0
    foreach ($c in $categorized) { $totalScripts += @($c.Items).Count }
    $catCount = ($categorized | Where-Object { $_.Category -ne "_root" }).Count
    $singletonAction = if ($Config.flattenSingletonCategories) { "flattened" } else { "kept" }

    Write-Log ($LogMsgs.messages.categorizing -replace '\{count\}', $totalScripts) -Level "info"
    $countMsg = ($LogMsgs.messages.categoryCount -replace '\{catCount\}',    $catCount) `
                                                  -replace '\{scriptCount\}', $totalScripts `
                                                  -replace '\{action\}',      $singletonAction
    Write-Log $countMsg -Level "success"

    $iconPath        = $Config.iconPath
    $cmdTemplate     = $Config.shell.commandTemplate
    $maxLen          = [int]$Config.categorySubkeyMaxLen
    $isAllSuccessful = $true
    $totalLeaves     = 0
    $scopeCount      = 0

    foreach ($scopeName in $Config.scopes.PSObject.Properties.Name) {
        $scope = $Config.scopes.$scopeName
        $topKey = $scope.topKey
        $isScopeEnabled = [bool]$scope.enabled

        if (-not $isScopeEnabled) {
            Write-Log ($LogMsgs.messages.scopeDisabled -replace '\{scope\}', $scopeName) -Level "warn"
            # Clean up any prior install for this scope
            $null = Remove-MenuTree -TopKey $topKey -LogMsgs $LogMsgs
            continue
        }

        Write-Log (($LogMsgs.messages.scopeStart -replace '\{scope\}', $scopeName) -replace '\{topKey\}', (ConvertTo-RegExePath $topKey)) -Level "info"

        # Idempotent: wipe any pre-existing tree first
        $null = Remove-MenuTree -TopKey $topKey -LogMsgs $LogMsgs

        # 1. Top-level cascading parent
        Write-Log ($LogMsgs.messages.writingTopLevel -replace '\{topKey\}', (ConvertTo-RegExePath $topKey)) -Level "info"
        $ok = New-CascadingParent `
            -PsPath        $topKey `
            -Label         $topLabel `
            -IconPath      $iconPath `
            -WithLuaShield $false `
            -LogMsgs       $LogMsgs
        if (-not $ok) { $isAllSuccessful = $false; continue }

        # 2. Categories + leaves
        foreach ($catGroup in $categorized) {
            $items = @($catGroup.Items)
            $isRootGroup = ($catGroup.Category -eq "_root")

            if ($isRootGroup) {
                # Singletons go directly under topKey\shell\<id>
                $parentForLeaves = "$topKey\shell"
                foreach ($item in $items) {
                    $leafLabel  = $item.Label
                    $cmdLine    = ($cmdTemplate -replace '\{shellExe\}', $shellExe) `
                                                -replace '\{repoRoot\}', $repoRoot `
                                                -replace '\{scriptId\}', $item.Id
                    $leafSub = ConvertTo-SafeSubkey -Name $item.Id -MaxLen $maxLen
                    Write-Log ((($LogMsgs.messages.writingLeaf -replace '\{id\}', $item.Id) -replace '\{folder\}', $item.Folder) -replace '\{path\}', "$parentForLeaves\$leafSub") -Level "info"
                    Write-Log ($LogMsgs.messages.leafCommand -replace '\{command\}', $cmdLine) -Level "info"
                    $okLeaf = New-LeafEntry `
                        -ParentPsPath $parentForLeaves `
                        -LeafSubkey   $leafSub `
                        -Label        $leafLabel `
                        -IconPath     $shellExe `
                        -CommandLine  $cmdLine `
                        -LogMsgs      $LogMsgs
                    if (-not $okLeaf) { $isAllSuccessful = $false } else { $totalLeaves++ }
                }
                continue
            }

            $catSafe   = ConvertTo-SafeSubkey -Name $catGroup.Category -MaxLen $maxLen
            $catKey    = "$topKey\shell\$catSafe"
            Write-Log (($LogMsgs.messages.writingCategory -replace '\{category\}', $catGroup.Category) -replace '\{path\}', (ConvertTo-RegExePath $catKey)) -Level "info"

            $okCat = New-CascadingParent `
                -PsPath        $catKey `
                -Label         $catGroup.Category `
                -IconPath      $iconPath `
                -WithLuaShield $false `
                -LogMsgs       $LogMsgs
            if (-not $okCat) { $isAllSuccessful = $false; continue }

            $parentForLeaves = "$catKey\shell"
            foreach ($item in $items) {
                $leafSub  = ConvertTo-SafeSubkey -Name $item.Id -MaxLen $maxLen
                $cmdLine  = ($cmdTemplate -replace '\{shellExe\}', $shellExe) `
                                          -replace '\{repoRoot\}', $repoRoot `
                                          -replace '\{scriptId\}', $item.Id
                Write-Log ((($LogMsgs.messages.writingLeaf -replace '\{id\}', $item.Id) -replace '\{folder\}', $item.Folder) -replace '\{path\}', (ConvertTo-RegExePath "$parentForLeaves\$leafSub")) -Level "info"
                Write-Log ($LogMsgs.messages.leafCommand -replace '\{command\}', $cmdLine) -Level "info"
                $okLeaf = New-LeafEntry `
                    -ParentPsPath $parentForLeaves `
                    -LeafSubkey   $leafSub `
                    -Label        $item.Label `
                    -IconPath     $shellExe `
                    -CommandLine  $cmdLine `
                    -LogMsgs      $LogMsgs
                if (-not $okLeaf) { $isAllSuccessful = $false } else { $totalLeaves++ }
            }
        }

        # 3. Verify
        Write-Log ($LogMsgs.messages.verifyStart -replace '\{scope\}', $scopeName) -Level "info"
        $isTopOk = Test-MenuKeyExists -PsPath $topKey
        if ($isTopOk) {
            Write-Log ((($LogMsgs.messages.verifyPass -replace '\{label\}', "top") -replace '\{path\}', (ConvertTo-RegExePath $topKey))) -Level "success"
        } else {
            Write-Log ((($LogMsgs.messages.verifyMiss -replace '\{label\}', "top") -replace '\{path\}', (ConvertTo-RegExePath $topKey))) -Level "error"
            $isAllSuccessful = $false
        }
        $scopeCount++
    }

    # -- Save resolved state --
    Save-ResolvedData -ScriptFolder "53-script-fixer-context-menu" -Data @{
        installedAt   = (Get-Date -Format "o")
        version       = $version
        topLevelLabel = $topLabel
        shellExe      = $shellExe
        scopes        = (@($Config.scopes.PSObject.Properties | Where-Object { $_.Value.enabled } | ForEach-Object { $_.Name }) -join ',')
        leafCount     = $totalLeaves
        categories    = $catCount
    }

    # -- Summary --
    if ($isAllSuccessful) {
        $msg = (($LogMsgs.messages.summaryInstalled -replace '\{label\}', $topLabel) `
                                                    -replace '\{scopeCount\}', $scopeCount) `
                                                    -replace '\{catCount\}',  $catCount
        $msg = $msg -replace '\{leafCount\}', $totalLeaves
        Write-Log $msg -Level "success"
        Write-Log $LogMsgs.messages.tipRefresh -Level "info"
    } else {
        Write-Log $LogMsgs.messages.summaryFailed -Level "error"
    }

    return $isAllSuccessful
}

try {
    # -- Git pull -------------------------------------------------------------
    Invoke-GitPull

    # -- Assert admin ---------------------------------------------------------
    Write-Log $logMessages.messages.checkingAdmin -Level "info"
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $hasAdminRights = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Log ($logMessages.messages.currentUser -replace '\{name\}', $identity.Name) -Level "info"
    Write-Log ($logMessages.messages.isAdministrator -replace '\{value\}', $hasAdminRights) -Level $(if ($hasAdminRights) { "success" } else { "error" })

    $isNotAdmin = -not $hasAdminRights
    if ($isNotAdmin) {
        Write-Log $logMessages.messages.notAdmin -Level "error"
        return
    }

    $cmd = $Command.ToLower()

    switch ($cmd) {
        "uninstall" {
            $null = Invoke-Uninstall -Config $config -LogMsgs $logMessages
        }
        "refresh" {
            Write-Log $logMessages.messages.refreshing -Level "info"
            $null = Invoke-Uninstall -Config $config -LogMsgs $logMessages
            $null = Invoke-Install   -Config $config -LogMsgs $logMessages -RepoRoot $repoRoot -ScriptDir $scriptDir
        }
        default {
            # "install" or "all"
            $null = Invoke-Install -Config $config -LogMsgs $logMessages -RepoRoot $repoRoot -ScriptDir $scriptDir
        }
    }

} catch {
    Write-Log "Unhandled error: $_" -Level "error"
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level "error"
} finally {
    $hasAnyErrors = $script:_LogErrors.Count -gt 0
    Save-LogFile -Status $(if ($hasAnyErrors) { "fail" } else { "ok" })
}
