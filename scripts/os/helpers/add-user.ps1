<#
.SYNOPSIS
    os add-user -- Create a local Windows user with optional PIN/email notice.

.DESCRIPTION
    Usage: .\run.ps1 os add-user <name> <pass> [pin] [email]

    Per locked decision: password is passed as a plain CLI arg
    (visible in shell history -- accepted risk). PIN and email cannot
    be set non-interactively on modern Windows; the script logs a
    [NOTICE] and saves a one-time PIN hint to %TEMP%.
#>
param(
    [Parameter(Position = 0)][string]$Name,
    [Parameter(Position = 1)][string]$Pass,
    [Parameter(Position = 2)][string]$Pin,
    [Parameter(Position = 3)][string]$Email
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$helpersDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptDir  = Split-Path -Parent $helpersDir
$sharedDir  = Join-Path (Split-Path -Parent $scriptDir) "shared"

. (Join-Path $sharedDir "logging.ps1")
. (Join-Path $sharedDir "json-utils.ps1")
. (Join-Path $helpersDir "_common.ps1")

$config      = Import-JsonConfig (Join-Path $scriptDir "config.json")
$logMessages = Import-JsonConfig (Join-Path $scriptDir "log-messages.json")
$script:LogMessages = $logMessages

Initialize-Logging -ScriptName "Add User"

# Validate args BEFORE elevation -- avoid pointless UAC prompts
if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Log $logMessages.addUser.missingName -Level "fail"
    Save-LogFile -Status "fail"
    exit 2
}
if ([string]::IsNullOrWhiteSpace($Pass)) {
    Write-Log $logMessages.addUser.missingPass -Level "fail"
    Save-LogFile -Status "fail"
    exit 2
}

$forwardArgs = @($Name, $Pass)
if ($Pin)   { $forwardArgs += $Pin }
if ($Email) { $forwardArgs += $Email }

$isAdminOk = Assert-Admin -ScriptPath $MyInvocation.MyCommand.Definition -ForwardArgs $forwardArgs -LogMessages $logMessages
if (-not $isAdminOk) {
    Save-LogFile -Status "fail"
    exit 1
}

# 1. Create user (or skip if exists)
$existing = $null
try { $existing = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue } catch {}

if ($existing) {
    $msg = $logMessages.addUser.userExists -replace '\{name\}', $Name
    Write-Log $msg -Level "warn"
} else {
    try {
        $securePass = ConvertTo-SecureString $Pass -AsPlainText -Force
        $createParams = @{
            Name              = $Name
            Password          = $securePass
            ErrorAction       = 'Stop'
        }
        if ($config.addUser.passwordNeverExpires) { $createParams['PasswordNeverExpires'] = $true }
        if ($config.addUser.accountNeverExpires)  { $createParams['AccountNeverExpires']  = $true }
        New-LocalUser @createParams | Out-Null
        $msg = $logMessages.addUser.userCreated -replace '\{name\}', $Name
        Write-Log $msg -Level "success"
    } catch {
        $errMsg = $logMessages.addUser.userCreateFailed `
            -replace '\{name\}', $Name `
            -replace '\{error\}', $_.Exception.Message
        Write-Log $errMsg -Level "fail"
        Save-LogFile -Status "fail"
        exit 1
    }
}

# 2. Add to default group
$group = $config.addUser.defaultGroup
try {
    $alreadyMember = $false
    try {
        $members = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue
        foreach ($m in $members) {
            if ($m.Name -like "*\$Name" -or $m.Name -eq $Name) { $alreadyMember = $true; break }
        }
    } catch {}

    if (-not $alreadyMember) {
        Add-LocalGroupMember -Group $group -Member $Name -ErrorAction Stop
    }
    $msg = $logMessages.addUser.addedToGroup -replace '\{name\}', $Name -replace '\{group\}', $group
    Write-Log $msg -Level "success"
} catch {
    $errMsg = $logMessages.addUser.groupAddFailed `
        -replace '\{name\}', $Name `
        -replace '\{group\}', $group `
        -replace '\{error\}', $_.Exception.Message
    Write-Log $errMsg -Level "warn"
}

# 3. PIN -- save hint file, log NOTICE
if (-not [string]::IsNullOrWhiteSpace($Pin)) {
    $pinMasked = ('*' * [Math]::Min($Pin.Length, 6))
    $hintFolder = [Environment]::ExpandEnvironmentVariables($config.addUser.pinHintFolder)
    if (-not (Test-Path $hintFolder)) { $hintFolder = $env:TEMP }
    $hintFile = Join-Path $hintFolder "$Name-pin-hint.txt"

    try {
        $hintBody = @(
            "PIN hint for Windows user '$Name'",
            "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "",
            "Provided PIN: $Pin",
            "",
            "Windows Hello PIN cannot be set non-interactively.",
            "Sign in as '$Name' and use:",
            "  Settings -> Accounts -> Sign-in options -> PIN (Windows Hello) -> Add",
            "",
            "DELETE THIS FILE after the PIN is set."
        ) -join "`r`n"
        Set-Content -Path $hintFile -Value $hintBody -Encoding UTF8 -ErrorAction Stop

        $msg = $logMessages.addUser.pinNotice `
            -replace '\{pinMasked\}', $pinMasked `
            -replace '\{hintFile\}', $hintFile `
            -replace '\{name\}', $Name
        Write-Log $msg -Level "info"
    } catch {
        $errMsg = $logMessages.addUser.pinHintWriteFailed `
            -replace '\{path\}', $hintFile `
            -replace '\{error\}', $_.Exception.Message
        Write-Log $errMsg -Level "fail"
    }
}

# 4. Email -- store as user comment + log NOTICE
if (-not [string]::IsNullOrWhiteSpace($Email)) {
    try {
        & net.exe user $Name /comment:"$Email" 2>&1 | Out-Null
    } catch {}
    $msg = $logMessages.addUser.emailNotice `
        -replace '\{email\}', $Email `
        -replace '\{name\}', $Name
    Write-Log $msg -Level "info"
}

# 5. Console summary -- masked password
$passMasked = ('*' * [Math]::Min($Pass.Length, 8))
Write-Host ""
Write-Host "  $($logMessages.addUser.summaryHeader)" -ForegroundColor Cyan
Write-Host "  ===============================" -ForegroundColor DarkGray
Write-Host "    User created : $Name"
Write-Host "    Password     : $passMasked  " -NoNewline
Write-Host "(passed via CLI -- visible in shell history!)" -ForegroundColor Yellow
Write-Host "    Group        : $group"
if ($Pin)   { Write-Host "    PIN (manual) : <hint saved to %TEMP%\$Name-pin-hint.txt>" -ForegroundColor DarkYellow }
if ($Email) { Write-Host "    Email (manual): $Email" -ForegroundColor DarkYellow }
Write-Host ""

Save-LogFile -Status "ok"
exit 0
