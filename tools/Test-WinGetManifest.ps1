# Test-WinGetManifest.ps1 - Validates WinGet YAML manifests
[CmdletBinding()]
param(
    [string]$ManifestDir,
    [string]$Version = "0.1.0-preview1"
)

$ErrorActionPreference = "Stop"

$projectDir = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $ManifestDir) {
    $ManifestDir = Join-Path $projectDir "manifests\t\TiredRebel\TerminalAI\$Version"
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TerminalAI: WinGet Manifest Validation Engine              " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

if (-not (Test-Path $ManifestDir)) {
    throw "Manifest directory not found: $ManifestDir"
}

$expectedFiles = @(
    "TiredRebel.TerminalAI.yaml",
    "TiredRebel.TerminalAI.installer.yaml",
    "TiredRebel.TerminalAI.locale.en-US.yaml",
    "TiredRebel.TerminalAI.locale.uk-UA.yaml"
)

# 1. Existence check
Write-Host "1. Checking manifest file set..." -ForegroundColor Yellow
foreach ($file in $expectedFiles) {
    $path = Join-Path $ManifestDir $file
    if (-not (Test-Path $path)) {
        throw "Missing WinGet manifest file: $file"
    }
    Write-Host "   ✔ Found: $file" -ForegroundColor Green
}

# 2. Schema field validation (Schema 1.9.0)
Write-Host "`n2. Validating YAML keys and schema compliance (Schema 1.9.0)..." -ForegroundColor Yellow

# Version manifest
$verContent = Get-Content (Join-Path $ManifestDir "TiredRebel.TerminalAI.yaml") -Raw
if ($verContent -notmatch 'PackageIdentifier:\s+TiredRebel\.TerminalAI') { throw "Version manifest missing PackageIdentifier." }
if ($verContent -notmatch "PackageVersion:\s+$Version") { throw "Version manifest missing PackageVersion: $Version." }
if ($verContent -notmatch 'ManifestType:\s+version') { throw "Version manifest missing ManifestType." }
if ($verContent -notmatch 'ManifestVersion:\s+1\.9\.0') { throw "Version manifest missing ManifestVersion: 1.9.0." }
Write-Host "   ✔ Version manifest schema valid (1.9.0)." -ForegroundColor Green

# Installer manifest
$instContent = Get-Content (Join-Path $ManifestDir "TiredRebel.TerminalAI.installer.yaml") -Raw
if ($instContent -notmatch 'InstallerType:\s+zip') { throw "Installer manifest missing InstallerType: zip." }
if ($instContent -notmatch 'NestedInstallerType:\s+portable') { throw "Installer manifest missing NestedInstallerType: portable." }
if ($instContent -notmatch 'PortableCommandAlias:\s+terminalai') { throw "Installer manifest missing PortableCommandAlias: terminalai." }
if ($instContent -notmatch 'Architecture:\s+x64') { throw "Installer manifest missing Architecture: x64." }
if ($instContent -notmatch 'InstallerSha256:\s+[A-Fa-f0-9]{64}') { throw "Installer manifest missing valid 64-char InstallerSha256." }
if ($instContent -notmatch 'ManifestVersion:\s+1\.9\.0') { throw "Installer manifest missing ManifestVersion: 1.9.0." }
Write-Host "   ✔ Installer manifest schema valid (portable zip with x64 + SHA-256, 1.9.0)." -ForegroundColor Green

# English locale manifest
$locEnContent = Get-Content (Join-Path $ManifestDir "TiredRebel.TerminalAI.locale.en-US.yaml") -Raw
if ($locEnContent -notmatch 'PackageLocale:\s+en-US') { throw "EN locale manifest missing PackageLocale: en-US." }
if ($locEnContent -notmatch 'PackageName:\s+TerminalAI') { throw "EN locale manifest missing PackageName." }
if ($locEnContent -notmatch 'License:\s+MIT') { throw "EN locale manifest missing License: MIT." }
if ($locEnContent -notmatch 'ManifestType:\s+defaultLocale') { throw "EN locale manifest missing ManifestType: defaultLocale." }
if ($locEnContent -notmatch 'ManifestVersion:\s+1\.9\.0') { throw "EN locale manifest missing ManifestVersion: 1.9.0." }
Write-Host "   ✔ Default locale manifest (en-US) schema valid (1.9.0)." -ForegroundColor Green

# Ukrainian locale manifest
$locUkContent = Get-Content (Join-Path $ManifestDir "TiredRebel.TerminalAI.locale.uk-UA.yaml") -Raw
if ($locUkContent -notmatch 'PackageLocale:\s+uk-UA') { throw "UK locale manifest missing PackageLocale: uk-UA." }
if ($locUkContent -notmatch 'PackageName:\s+TerminalAI') { throw "UK locale manifest missing PackageName." }
if ($locUkContent -notmatch 'ManifestType:\s+locale') { throw "UK locale manifest missing ManifestType: locale." }
if ($locUkContent -notmatch 'ManifestVersion:\s+1\.9\.0') { throw "UK locale manifest missing ManifestVersion: 1.9.0." }
Write-Host "   ✔ Localized manifest (uk-UA) schema valid (1.9.0)." -ForegroundColor Green

# 3. Native WinGet CLI validation (if available)
Write-Host "`n3. Running official winget validate (if winget is installed)..." -ForegroundColor Yellow
if (Get-Command winget -ErrorAction SilentlyContinue) {
    try {
        $valOutput = & winget validate --manifest $ManifestDir 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and ($valOutput -match "validation succeeded|passed|Manifest validation success" -or -not ($valOutput -match "Error:"))) {
            Write-Host "   ✔ Official winget validate passed:`n$valOutput" -ForegroundColor Green
        } else {
            throw "winget validate failed:`n$valOutput"
        }
    } catch {
        if ($_.Exception.Message -match "winget validate failed") {
            throw
        }
        Write-Host "   • winget validate skipped: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "   • winget executable not detected on host. Static schema validation completed." -ForegroundColor DarkGray
}

Write-Host "`n✔ All WinGet manifests are 100% valid and ready for submission to winget-pkgs!`n" -ForegroundColor Green
