# 11 -- PSReadLine (folded into Base profile)

**Type**: not a separate script -- single inline action inside the Base profile recipe
**Trigger**: Base profile (subdoc 12) and any standalone `.\run.ps1 install psreadline` keyword

## What it does

```powershell
Install-Module -Name PSReadLine -Force -SkipPublisherCheck
```

## Why no dedicated script folder

Single one-line action with no settings, no choco, no verification beyond `Get-Module PSReadLine -ListAvailable`. Inlining inside the Base profile recipe keeps the script count down and aligns with the "skip dev-dir, OS-dir install" decision (PowerShell Gallery installs to `$HOME\Documents\PowerShell\Modules`).

## Implementation

### Inside `scripts/profile/helpers/base.ps1`
```powershell
function Install-PSReadLineLatest {
    Write-Log -Level "info" -Message "Installing PSReadLine module..."
    try {
        Install-Module -Name PSReadLine -Force -SkipPublisherCheck -Scope CurrentUser -ErrorAction Stop
        $v = (Get-Module PSReadLine -ListAvailable | Select-Object -First 1).Version
        Write-Log -Level "ok" -Message "PSReadLine $v installed"
    } catch {
        Write-Log -Level "fail" -Message "PSReadLine install failed: $($_.Exception.Message)"
    }
}
```

## Optional standalone keyword

Add to `scripts/shared/install-keywords.json`:
```json
"psreadline": ["inline:psreadline"]
```
where `"inline:..."` is a new convention for actions that don't have a script ID. The dispatcher routes `inline:psreadline` to `scripts/profile/helpers/base.ps1::Install-PSReadLineLatest`.

**If inline-keyword routing adds too much complexity, drop the standalone keyword and keep PSReadLine purely as a Base-profile inclusion.** Decision deferred to implementation step.

## Verification

```powershell
.\run.ps1 profile base
Get-Module PSReadLine -ListAvailable | Select-Object Name, Version
```

## Open questions

- Should `psreadline` be a standalone keyword, or only available via `profile base`? Lean: standalone too, with `inline:` prefix support added to the dispatcher (small infra cost).
