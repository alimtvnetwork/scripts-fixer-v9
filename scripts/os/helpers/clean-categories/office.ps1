<# Bucket E: office -- MS Office cache (NOT documents, NOT recent file lists) #>
param([switch]$DryRun, [switch]$Yes, [int]$Days = 30, [hashtable]$SharedResult)

$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $here "_sweep.ps1")

$result = New-CleanResult -Category "office" -Label "MS Office cache (documents safe)" -Bucket "E"

$local = Get-LocalAppDataPath
$roam  = Get-AppDataPath
if ([string]::IsNullOrWhiteSpace($local) -or [string]::IsNullOrWhiteSpace($roam)) {
    $result.Notes += "APPDATA / LOCALAPPDATA not set"
    Set-CleanResultStatus -Result $result -DryRun:$DryRun
    return $result
}

# Office Document Cache (Upload Center) -- NOT user docs themselves
$officeCacheRoots = @(
    (Join-Path $local "Microsoft\Office\16.0\OfficeFileCache"),
    (Join-Path $local "Microsoft\Office\16.0\Wef"),
    (Join-Path $local "Microsoft\Office\16.0\PowerPoint\PptCache"),
    (Join-Path $local "Microsoft\Office\16.0\OneNote\Backup\OfficeFileCache"),
    (Join-Path $local "Microsoft\Office\OTele"),
    (Join-Path $local "Microsoft\Office\16.0\Licensing\Backup")
)

# Office diagnostic / setup cache
$officeCacheRoots += (Join-Path $local "Microsoft\Office\16.0\Telemetry")
$officeCacheRoots += (Join-Path $local "Microsoft\Office\16.0\OfficeSetup")

$anyFound = $false
foreach ($p in $officeCacheRoots) {
    if (Test-Path -LiteralPath $p) {
        $anyFound = $true
        $rel = $p.Substring($local.Length).TrimStart("\")
        Invoke-PathSweep -Path $p -Result $result -DryRun:$DryRun -LogPrefix "office/$rel"
    }
}

if (-not $anyFound) {
    $result.Notes += "MS Office cache directories not found (Office not installed?)"
}

Set-CleanResultStatus -Result $result -DryRun:$DryRun
return $result
