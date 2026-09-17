# Build-ReleasePackage.ps1 - fresh source build, provenance, ZIP, and WinGet manifests
[CmdletBinding()]
param(
    [string]$Version = "0.1.0-preview2",
    [string]$OutputDir,
    [string]$CertificateThumbprint,
    [switch]$AllowUnsigned,
    [switch]$AllowDirty,
    [switch]$SkipZip
)
$ErrorActionPreference = "Stop"
$projectDir = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $OutputDir) { $OutputDir = Join-Path $projectDir "dist" }
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
$commit = (& git -C $projectDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw "Unable to resolve current git commit." }
$dirty = @(& git -C $projectDir status --porcelain)
if ($dirty.Count -gt 0 -and -not $AllowDirty) { throw "Release packaging requires a clean git tree; use -AllowDirty only for local candidate tests." }
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ("TerminalAI-release-" + [guid]::NewGuid().ToString("N"))
$launcherOut = Join-Path $buildRoot "launcher"
$aotOut = Join-Path $buildRoot "aot"
$stagingDir = Join-Path $OutputDir "staging"
New-Item -ItemType Directory -Path $buildRoot,$launcherOut,$aotOut,$OutputDir -Force | Out-Null
try {
    Write-Host "Building TerminalAI $Version from $commit"
    dotnet build (Join-Path $projectDir "AOT\TerminalAI.Aot.csproj") -c Release -t:Rebuild -p:SkipRootCopy=true -o $aotOut --nologo | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "AOT build failed." }
    $launcherProject = Join-Path $projectDir "Launcher\TerminalAI.Launcher.csproj"
    dotnet build $launcherProject -c Release -t:Rebuild -r win-x64 --self-contained true -p:PublishSingleFile=true -o $launcherOut --nologo | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Launcher rebuild failed." }
    dotnet publish $launcherProject -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true --no-build -o $launcherOut --nologo | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Launcher publish failed." }
    $aotDll = Join-Path $aotOut "TerminalAI.Aot.dll"; $launcherExe = Join-Path $launcherOut "terminalai.exe"
    if (-not (Test-Path $aotDll)) { throw "Fresh AOT output missing: $aotDll" }
    if (-not (Test-Path $launcherExe)) { throw "Fresh launcher output missing: $launcherExe" }
    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    $files = @("TerminalAI.psd1","TerminalAI.psm1","TerminalAiConfig.ps1","TerminalAiAssistant.ps1","TerminalAiAgent.ps1","terminalai.json","Install-TerminalAi.ps1","Uninstall-TerminalAi.ps1","bootstrap.ps1","TerminalAI-Portable.cmd","README.md","README.uk.md","LICENSE")
    foreach ($relative in $files) { $source = Join-Path $projectDir $relative; if (-not (Test-Path $source)) { throw "Missing release file: $relative" }; Copy-Item $source (Join-Path $stagingDir $relative) -Force }
    Copy-Item $aotDll (Join-Path $stagingDir "TerminalAI.Aot.dll") -Force
    $help = Join-Path $projectDir "TerminalAI.Aot.dll-Help.xml"; if (Test-Path $help) { Copy-Item $help (Join-Path $stagingDir "TerminalAI.Aot.dll-Help.xml") -Force }
    Copy-Item $launcherExe (Join-Path $stagingDir "terminalai.exe") -Force
    $docsDir = Join-Path $stagingDir "docs"; $aotDocsDir = Join-Path $stagingDir "AOT"; New-Item -ItemType Directory -Path $docsDir,$aotDocsDir -Force | Out-Null
    Copy-Item (Join-Path $projectDir "docs\TECHNICAL.md") (Join-Path $docsDir "TECHNICAL.md") -Force
    Copy-Item (Join-Path $projectDir "AOT\README.md") (Join-Path $aotDocsDir "README.md") -Force
    Copy-Item (Join-Path $projectDir "AOT\README.uk.md") (Join-Path $aotDocsDir "README.uk.md") -Force
    $installersSrc = Join-Path $projectDir "installers"; if (Test-Path $installersSrc) { Copy-Item $installersSrc (Join-Path $stagingDir "installers") -Recurse -Force }
    $cert = $null
    if ($CertificateThumbprint) {
        $normalized = $CertificateThumbprint -replace '\s',''; $cert = Get-ChildItem Cert:\CurrentUser\My,Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $normalized } | Select-Object -First 1
        if (-not $cert) { throw "Code-signing certificate thumbprint not found: $normalized" }
        foreach ($binary in @((Join-Path $stagingDir "terminalai.exe"),(Join-Path $stagingDir "TerminalAI.Aot.dll"))) { $signed = Set-AuthenticodeSignature -FilePath $binary -Certificate $cert; if ($signed.Status -ne "Valid") { throw "Signing failed for ${binary}: $($signed.Status)" } }
        Write-Host "Signed staged EXE/DLL with certificate $($cert.Thumbprint)."
    } elseif (-not $AllowUnsigned) { throw "No code-signing certificate supplied. Re-run with -CertificateThumbprint or explicit -AllowUnsigned." }
    else { Write-Host "UNSIGNED: no code-signing certificate supplied; -AllowUnsigned acknowledged." -ForegroundColor Yellow }
    $artifactHashes = [ordered]@{}
    $artifactHashes["terminalai.exe"] = (Get-FileHash (Join-Path $stagingDir "terminalai.exe") -Algorithm SHA256).Hash
    $artifactHashes["TerminalAI.Aot.dll"] = (Get-FileHash (Join-Path $stagingDir "TerminalAI.Aot.dll") -Algorithm SHA256).Hash
    $sourceHashes = [ordered]@{}
    foreach ($relative in $files) { $sourceHashes[$relative] = (Get-FileHash (Join-Path $projectDir $relative) -Algorithm SHA256).Hash }
    $sourceHashes["docs/TECHNICAL.md"] = (Get-FileHash (Join-Path $projectDir "docs\TECHNICAL.md") -Algorithm SHA256).Hash
    $sourceHashes["AOT/README.md"] = (Get-FileHash (Join-Path $projectDir "AOT\README.md") -Algorithm SHA256).Hash
    $sourceHashes["AOT/README.uk.md"] = (Get-FileHash (Join-Path $projectDir "AOT\README.uk.md") -Algorithm SHA256).Hash
    $provenance = [ordered]@{ version=$Version; commit=$commit; dirty=($dirty.Count -gt 0); signed=([bool]$cert); certificateThumbprint=if($cert){$cert.Thumbprint}else{$null}; artifactHashes=$artifactHashes; sourceHashes=$sourceHashes }
    [IO.File]::WriteAllText((Join-Path $stagingDir "RELEASE-PROVENANCE.json"), (($provenance | ConvertTo-Json -Depth 3) + "`n"), (New-Object Text.UTF8Encoding($false)))
    if ($SkipZip) { Write-Host "Candidate staging complete; -SkipZip prevents archive/hash/manifest reuse."; return }
    $zipName = "TerminalAI-v$Version-win-x64.zip"; $zipPath = Join-Path $OutputDir $zipName
    if (-not $SkipZip) { if (Test-Path $zipPath) { Remove-Item $zipPath -Force }; Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -CompressionLevel Optimal }
    if (-not (Test-Path $zipPath)) { throw "Release ZIP missing: $zipPath" }
    $sha = (Get-FileHash $zipPath -Algorithm SHA256).Hash; [IO.File]::WriteAllText((Join-Path $OutputDir "SHA256SUMS.txt"), "$sha  $zipName`n", [Text.Encoding]::ASCII)
    $wingetDir = Join-Path $projectDir "manifests\t\TiredRebel\TerminalAI\$Version"; New-Item -ItemType Directory -Path $wingetDir -Force | Out-Null; $url = "https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/download/v$Version/$zipName"; $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $wingetDir "TiredRebel.TerminalAI.yaml"), "# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.1.9.0.schema.json`nPackageIdentifier: TiredRebel.TerminalAI`nPackageVersion: $Version`nDefaultLocale: en-US`nManifestType: version`nManifestVersion: 1.9.0`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $wingetDir "TiredRebel.TerminalAI.installer.yaml"), "# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.1.9.0.schema.json`nPackageIdentifier: TiredRebel.TerminalAI`nPackageVersion: $Version`nMinimumOSVersion: 10.0.19041.0`nInstallerType: zip`nNestedInstallerType: portable`nNestedInstallerFiles:`n  - RelativeFilePath: terminalai.exe`n    PortableCommandAlias: terminalai`nInstallers:`n  - Architecture: x64`n    InstallerUrl: $url`n    InstallerSha256: $sha`n    UpgradeBehavior: install`nManifestType: installer`nManifestVersion: 1.9.0`n", $utf8)
    $text = "# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.1.9.0.schema.json`nPackageIdentifier: TiredRebel.TerminalAI`nPackageVersion: $Version`nPackageLocale: en-US`nPublisher: TiredRebel`nPublisherUrl: https://github.com/TiredRebel`nPackageName: TerminalAI`nPackageUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin`nLicense: MIT`nLicenseUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/blob/main/LICENSE`nShortDescription: TerminalAI is a local-by-default AI assistant for Windows Terminal and PowerShell powered by Ollama.`nDescription: TerminalAI is a local-by-default AI assistant for Windows Terminal and PowerShell powered by Ollama.`nReleaseNotesUrl: https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/tag/v$Version`nManifestType: defaultLocale`nManifestVersion: 1.9.0`n"
    [IO.File]::WriteAllText((Join-Path $wingetDir "TiredRebel.TerminalAI.locale.en-US.yaml"), $text, $utf8)
    Write-Host "ZIP: $zipPath`nSHA256: $sha`nWinGet: $wingetDir"
} finally { if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue } }
