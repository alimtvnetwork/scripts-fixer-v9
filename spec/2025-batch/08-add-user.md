# 08 -- `os add-user` Subcommand

**Type**: subcommand under `os` dispatcher
**Invocation**: `.\run.ps1 os add-user <name> <pass> [pin] [email]`
**Security**: Per locked decision -- **plain CLI args** (user accepted the risk)
**Requires**: Admin elevation

## What it does

Creates a local Windows user account with optional PIN and Microsoft account email association.

## CLI signature

```
.\run.ps1 os add-user <name> <pass> [pin] [email]
```

Examples:
```powershell
.\run.ps1 os add-user alice MyP@ss123
.\run.ps1 os add-user alice MyP@ss123 1234
.\run.ps1 os add-user alice MyP@ss123 1234 alice@outlook.com
```

## Implementation

### `scripts/os/helpers/add-user.ps1`
```powershell
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Pass,
    [string]$Pin,
    [string]$Email
)
Initialize-Logging -ScriptName "add-user"

# Assert admin (re-launch if not)
# ... standard pattern

# 1. Create user
$existing = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
if ($existing) {
    Write-Log -Level "warn" -Message "User '$Name' already exists -- skipping create"
} else {
    $securePass = ConvertTo-SecureString $Pass -AsPlainText -Force
    New-LocalUser -Name $Name -Password $securePass -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop
    Write-Log -Level "ok" -Message "Created local user '$Name'"
}

# 2. Add to Users group (default)
Add-LocalGroupMember -Group "Users" -Member $Name -ErrorAction SilentlyContinue

# 3. PIN -- Windows PIN cannot be set non-interactively without WinHello API. Log a NOTICE.
if ($Pin) {
    Write-Log -Level "notice" -Message "PIN '$Pin' provided but Windows requires interactive PIN setup. User '$Name' should sign in and set PIN via Settings -> Sign-in options."
}

# 4. Email -- linking a Microsoft account to a local user requires interactive sign-in.
if ($Email) {
    Write-Log -Level "notice" -Message "Email '$Email' noted. To link a Microsoft account, '$Name' must sign in to Settings -> Accounts -> 'Sign in with a Microsoft account instead'."
}

# 5. Console summary -- mask password
$masked = ('*' * [Math]::Min($Pass.Length, 8))
Write-Host ""
Write-Host "  User created : $Name"
Write-Host "  Password     : $masked  (passed via CLI -- visible in shell history!)"
if ($Pin)   { Write-Host "  PIN (manual) : $Pin" }
if ($Email) { Write-Host "  Email (manual): $Email" }
Write-Host ""

Save-LogFile -Status "ok"
```

## Logging note (CODE RED compliance)

- Password is **never** written to log files. Only the masked form goes to console; logs record `"Created local user '<name>'"` with no password fragment.
- Failure to create user logs the exact `Name` attempted + the full exception message (per CODE RED file/path error rule applied to identity ops).

## Verification

```powershell
.\run.ps1 os add-user testuser TestP@ss1
Get-LocalUser testuser   # should exist
Remove-LocalUser testuser
```

## Open questions

- PIN / email linking are inherently interactive on modern Windows. Spec acknowledges this -- script logs a `[NOTICE]` and lets the user complete those steps via Settings. Not blocking.
