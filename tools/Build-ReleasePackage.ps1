# Build-ReleasePackage.ps1 - Builds production release zip and updates WinGet manifests
[CmdletBinding()]
param(
    [string]$Version = "0.1.0-preview1",
    [string]$OutputDir,
    [switch]$SkipZip
)

$ErrorActionPreference = "Stop"

$projectDir = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $projectDir "dist"
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TerminalAI: Release Packaging & WinGet Manifest Generator  " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# 1. Build and publish launcher if not published
$launcherPublishDir = Join-Path $projectDir "Launcher\bin\Release\net10.0\win-x64\publish"
$launcherPublishExe = Join-Path $launcherPublishDir "terminalai.exe"
if (-not (Test-Path $launcherPublishExe)) {
    Write-Host "• Publishing self-contained win-x64 launcher executable..." -ForegroundColor Yellow
    dotnet publish (Join-Path $projectDir "Launcher\TerminalAI.Launcher.csproj") -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true | Out-Null
}

# Ensure compat location for testing
$launcherCompatDir = Join-Path $projectDir "Launcher\bin\Release\net10.0"
if (Test-Path $launcherPublishExe) {
    Copy-Item -Path $launcherPublishExe -Destination (Join-Path $launcherCompatDir "terminalai.exe") -Force -ErrorAction SilentlyContinue
}

# 2. Prepare output and staging directories
$stagingDir = Join-Path $OutputDir "staging"
if (Test-Path $stagingDir) {
    Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
}
$null = New-Item -ItemType Directory -Path $stagingDir -Force

# 3. Stage runtime files
Write-Host "1. Staging release artifacts..." -ForegroundColor Yellow

$filesToStage = @(
    "TerminalAI.psd1",
    "TerminalAI.psm1",
    "TerminalAiConfig.ps1",
    "TerminalAiAssistant.ps1",
    "TerminalAiAgent.ps1",
    "TerminalAI.Aot.dll",
    "TerminalAI.Aot.dll-Help.xml",
    "terminalai.json",
    "Install-TerminalAi.ps1",
    "Uninstall-TerminalAi.ps1",
    "bootstrap.ps1",
    "TerminalAI-Portable.cmd",
    "README.md",
    "LICENSE"
)

# Optional docs
if (Test-Path (Join-Path $projectDir "README.en.md")) {
    $filesToStage += "README.en.md"
}

foreach ($f in $filesToStage) {
    $src = Join-Path $projectDir $f
    if (-not (Test-Path $src)) {
        throw "Missing required release file: $src"
    }
    $dest = Join-Path $stagingDir $f
    Copy-Item -Path $src -Destination $dest -Force
    Write-Host "   ✔ Staged: $f" -ForegroundColor DarkGray
}

# Stage launcher executable from win-x64 publish directory
if (-not (Test-Path $launcherPublishExe)) {
    throw "Published launcher executable not found: $launcherPublishExe"
}
Copy-Item -Path $launcherPublishExe -Destination (Join-Path $stagingDir "terminalai.exe") -Force
Write-Host "   ✔ Staged launcher: terminalai.exe (self-contained win-x64)" -ForegroundColor DarkGray

# Stage installers folder
$installersSrc = Join-Path $projectDir "installers"
if (Test-Path $installersSrc) {
    $installersDest = Join-Path $stagingDir "installers"
    $null = New-Item -ItemType Directory -Path $installersDest -Force
    Copy-Item -Path "$installersSrc\*" -Destination $installersDest -Recurse -Force
    Write-Host "   ✔ Staged directory: installers/" -ForegroundColor DarkGray
}

# 4. Create zip archive
$zipFileName = "TerminalAI-v$Version-win-x64.zip"
$zipFilePath = Join-Path $OutputDir $zipFileName

if (-not $SkipZip) {
    Write-Host "`n2. Compressing release archive: $zipFileName" -ForegroundColor Yellow
    if (Test-Path $zipFilePath) {
        Remove-Item -Path $zipFilePath -Force
    }
    Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipFilePath -CompressionLevel Optimal
    Write-Host "   ✔ Archive created successfully." -ForegroundColor Green
}

# 5. Compute SHA-256 hash and write checksum manifest
Write-Host "`n3. Computing cryptographic SHA-256 checksum..." -ForegroundColor Yellow
$hashResult = Get-FileHash -Path $zipFilePath -Algorithm SHA256
$sha256 = $hashResult.Hash
Write-Host "   ✔ SHA256: $sha256" -ForegroundColor Green

$checksumFile = Join-Path $OutputDir "SHA256SUMS.txt"
$checksumContent = "$sha256  $zipFileName`n"
[System.IO.File]::WriteAllText($checksumFile, $checksumContent, [System.Text.Encoding]::ASCII)
Write-Host "   ✔ Checksum manifest written to: $checksumFile" -ForegroundColor Green

# 6. Generate / Update WinGet Manifests
Write-Host "`n4. Generating WinGet Package Manifests (Schema 1.9.0)..." -ForegroundColor Yellow
$wingetDir = Join-Path $projectDir "manifests\t\TiredRebel\TerminalAI\$Version"
if (-not (Test-Path $wingetDir)) {
    $null = New-Item -ItemType Directory -Path $wingetDir -Force
}

$releaseDownloadUrl = "https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/download/v$Version/$zipFileName"

# A. Version manifest
$versionYaml = @"
# Created with WinGet Automation Tooling
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.1.9.0.schema.json

PackageIdentifier: TiredRebel.TerminalAI
PackageVersion: $Version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.9.0
"@

# B. Installer manifest
$installerYaml = @"
# Created with WinGet Automation Tooling
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.1.9.0.schema.json

PackageIdentifier: TiredRebel.TerminalAI
PackageVersion: $Version
MinimumOSVersion: 10.0.19041.0
InstallerType: zip
NestedInstallerType: portable
NestedInstallerFiles:
  - RelativeFilePath: terminalai.exe
    PortableCommandAlias: terminalai
Installers:
  - Architecture: x64
    InstallerUrl: $releaseDownloadUrl
    InstallerSha256: $sha256
    UpgradeBehavior: install
ManifestType: installer
ManifestVersion: 1.9.0
"@

# C. Locale en-US manifest
$localeEnYaml = @"
# Created with WinGet Automation Tooling
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.1.9.0.schema.json

PackageIdentifier: TiredRebel.TerminalAI
PackageVersion: $Version
PackageLocale: en-US
Publisher: TiredRebel
PublisherUrl: https://github.com/TiredRebel
PublisherSupportUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/issues
PackageName: TerminalAI
PackageUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin
License: MIT
LicenseUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/blob/main/LICENSE
Copyright: (c) 2026 TiredRebel. All rights reserved.
ShortDescription: TerminalAI is a local-by-default AI assistant for Windows Terminal and PowerShell powered by Ollama. Features command generation, script synthesis, error fixing, and compiled .NET 10 helper.
Description: |-
  TerminalAI is a local-by-default AI assistant for Windows Terminal and PowerShell powered by Ollama. Features command generation, script synthesis, error fixing, and compiled .NET 10 helper.
Tags:
  - ai
  - ollama
  - terminal
  - windows-terminal
  - powershell
  - copilot
  - llm
  - local-ai
ReleaseNotesUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/tag/v$Version
ManifestType: defaultLocale
ManifestVersion: 1.9.0
"@

# D. Locale uk-UA manifest
$localeUkYaml = @"
# Created with WinGet Automation Tooling
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.locale.1.9.0.schema.json

PackageIdentifier: TiredRebel.TerminalAI
PackageVersion: $Version
PackageLocale: uk-UA
Publisher: TiredRebel
PublisherUrl: https://github.com/TiredRebel
PublisherSupportUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/issues
PackageName: TerminalAI
PackageUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin
License: MIT
LicenseUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/blob/main/LICENSE
Copyright: (c) 2026 TiredRebel. All rights reserved.
ShortDescription: Локальний за замовчуванням AI-помічник для Windows Terminal та PowerShell на базі Ollama.
Description: |-
  TerminalAI — це локальний за замовчуванням AI-асистент для Windows Terminal та PowerShell на базі Ollama. Він забезпечує генерацію команд, синтез скриптів, виправлення помилок та скомпільований модуль-помічник .NET 10.
Tags:
  - ai
  - ollama
  - terminal
  - windows-terminal
  - powershell
  - copilot
  - llm
  - штучний-інтелект
ReleaseNotesUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/tag/v$Version
ManifestType: locale
ManifestVersion: 1.9.0
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText((Join-Path $wingetDir "TiredRebel.TerminalAI.yaml"), $versionYaml.Trim() + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $wingetDir "TiredRebel.TerminalAI.installer.yaml"), $installerYaml.Trim() + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $wingetDir "TiredRebel.TerminalAI.locale.en-US.yaml"), $localeEnYaml.Trim() + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $wingetDir "TiredRebel.TerminalAI.locale.uk-UA.yaml"), $localeUkYaml.Trim() + "`n", $utf8NoBom)

Write-Host "   ✔ Generated WinGet manifests in: $wingetDir" -ForegroundColor Green
Write-Host "     • TiredRebel.TerminalAI.yaml" -ForegroundColor DarkGray
Write-Host "     • TiredRebel.TerminalAI.installer.yaml" -ForegroundColor DarkGray
Write-Host "     • TiredRebel.TerminalAI.locale.en-US.yaml" -ForegroundColor DarkGray
Write-Host "     • TiredRebel.TerminalAI.locale.uk-UA.yaml" -ForegroundColor DarkGray

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Release Package and WinGet Manifests generated successfully! " -ForegroundColor Green
Write-Host "  ZIP Package: $zipFilePath" -ForegroundColor Cyan
Write-Host "  Package Size: $([Math]::Round((Get-Item $zipFilePath).Length / 1KB, 1)) KB" -ForegroundColor Cyan
Write-Host "  SHA-256 Hash: $sha256" -ForegroundColor Cyan
Write-Host "  Checksum File: $checksumFile" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
