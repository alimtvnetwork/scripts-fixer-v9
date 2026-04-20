<# Bucket E: whatsapp -- Cache only (NOT chat history, NOT media library, NOT login) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "whatsapp" -Label "WhatsApp cache (chats + login safe)" -Bucket "E"

$local = Get-LocalAppDataPath
if ([string]::IsNullOrWhiteSpace($local)) {
    $result.Notes += "LOCALAPPDATA not set"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Two install variants:
# 1. MSIX/Store: %LOCALAPPDATA%\Packages\5319275A.WhatsAppDesktop_*\LocalCache\
# 2. Win32: %LOCALAPPDATA%\WhatsApp\Cache, Code Cache, GPUCache
$roots = @()

# Store package
$pkgRoot = Join-Path $local "Packages"
if (Test-Path -LiteralPath $pkgRoot) {
    try {
        Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter "*WhatsApp*" -ErrorAction SilentlyContinue | ForEach-Object {
            $cache = Join-Path $_.FullName "LocalCache\Roaming\WhatsApp\Cache"
            if (Test-Path -LiteralPath $cache) { $roots += $cache }
            $gpu = Join-Path $_.FullName "LocalCache\Roaming\WhatsApp\GPUCache"
            if (Test-Path -LiteralPath $gpu) { $roots += $gpu }
            $codeCache = Join-Path $_.FullName "LocalCache\Roaming\WhatsApp\Code Cache"
            if (Test-Path -LiteralPath $codeCache) { $roots += $codeCache }
            $acTemp = Join-Path $_.FullName "AC\Temp"
            if (Test-Path -LiteralPath $acTemp) { $roots += $acTemp }
            $acINet = Join-Path $_.FullName "AC\INetCache"
            if (Test-Path -LiteralPath $acINet) { $roots += $acINet }
        }
    } catch {
        Write-Log "whatsapp store enumeration failed at ${pkgRoot}: $($_.Exception.Message)" -Level "warn"
    }
}

# Win32 install
$win32Root = Join-Path $local "WhatsApp"
if (Test-Path -LiteralPath $win32Root) {
    foreach ($sub in @("Cache", "Code Cache", "GPUCache")) {
        $p = Join-Path $win32Root $sub
        if (Test-Path -LiteralPath $p) { $roots += $p }
    }
}

if ($roots.Count -eq 0) {
    $result.Notes += "WhatsApp not installed (no cache dirs found)"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

foreach ($p in $roots) {
    Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "whatsapp"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
