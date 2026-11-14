<#
.SYNOPSIS
  Checks that this project builds and passes its tests on this PC, and saves a
  full log on the Desktop (bkdash_verify.txt) that can be sent for support.

.USAGE
  From the project folder:
    powershell -ExecutionPolicy Bypass -File tool\verify.ps1
  Options:
    -SkipBuild   do not build the debug APK (faster)
    -Run         after the checks, start the app on the connected phone

  The script only reads and builds; it never changes your data or settings.
#>
param(
    [switch]$SkipBuild,
    [switch]$Run
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$log = Join-Path ([Environment]::GetFolderPath('Desktop')) 'bkdash_verify.txt'
Set-Content -LiteralPath $log -Value ("bkdash verify - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8

$summary = New-Object System.Collections.Generic.List[string]
$failed = $false

function Write-Log([string]$Text) {
    Write-Host $Text
    Add-Content -LiteralPath $log -Value $Text -Encoding UTF8
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Command)
    Write-Log ''
    Write-Log "=== $Name ==="
    $global:LASTEXITCODE = 0
    & $Command 2>&1 | ForEach-Object { Write-Log "$_" }
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        $summary.Add("PASS  $Name")
    } else {
        $summary.Add("FAIL  $Name (exit code $code)")
        $script:failed = $true
    }
    return ($code -eq 0)
}

# 1) The classic Windows problem: project and Pub cache on different drives.
$pub = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
$projectDrive = [IO.Path]::GetPathRoot($root)
$pubDrive = [IO.Path]::GetPathRoot($pub)
Write-Log "Project   : $root"
Write-Log "Pub cache : $pub"
if ($projectDrive -ne $pubDrive) {
    $summary.Add("WARN  Pub cache ($pubDrive) and project ($projectDrive) are on different drives")
    Write-Log 'WARNING: the Pub cache and the project are on different drives. The Android build can fail with'
    Write-Log '         "this and base files have different roots". Set PUB_CACHE to a folder on the project drive.'
} else {
    $summary.Add('PASS  Pub cache and project are on the same drive')
}

# 2) The real checks.
$ok = Invoke-Step 'flutter --version' { flutter --version }
if ($ok) {
    $ok = Invoke-Step 'flutter pub get' { flutter pub get }
}
if ($ok) {
    [void](Invoke-Step 'flutter analyze' { flutter analyze })
    [void](Invoke-Step 'flutter test' { flutter test })
    if (-not $SkipBuild) {
        [void](Invoke-Step 'flutter build apk --debug' { flutter build apk --debug })
    }
}

Write-Log ''
Write-Log '=============== SUMMARY ==============='
foreach ($line in $summary) { Write-Log $line }
Write-Log '======================================='
if ($failed) {
    Write-Log "Some steps failed. Send the file: $log"
    exit 1
}
Write-Log "Everything passed. Full log: $log"

if ($Run) {
    Write-Log ''
    Write-Log 'Starting the app on the connected device (press q to quit)...'
    flutter run
}
exit 0
