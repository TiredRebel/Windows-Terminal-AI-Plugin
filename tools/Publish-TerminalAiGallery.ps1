# Publish-TerminalAiGallery.ps1 - Packages and publishes TerminalAI to PowerShell Gallery
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$StagingPath,
    [string]$NuGetApiKey,
    [string]$Repository = "PSGallery",
    [switch]$DryRun,
    [switch]$CreateLocalRepo,
    [switch]$Force,
    [string]$CertificateThumbprint,
    [switch]$AllowUnsigned
)

$ErrorActionPreference = "Stop"

$projectDir = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $StagingPath) {
    $StagingPath = Join-Path $projectDir "dist\PowerShellGallery\TerminalAI"
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TerminalAI: PowerShell Gallery Packaging & Staging Engine  " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$galleryBuildRoot = Join-Path ([IO.Path]::GetTempPath()) ("TerminalAI-gallery-" + [guid]::NewGuid().ToString("N"))
$galleryAotOut = Join-Path $galleryBuildRoot "aot"
try {
# 1. Prepare clean staging directory
Write-Host "1. Preparing staging directory: $StagingPath" -ForegroundColor Yellow
if (Test-Path $StagingPath) {
    if ($Force -or $DryRun) {
        Remove-Item -Path $StagingPath -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning "Staging path already exists. Use -Force to overwrite."
        return
    }
}
$null = New-Item -ItemType Directory -Path $StagingPath -Force

# 2. Build and stage production runtime files only (exclude tests, dev tools, and build outputs)
Write-Host "2. Staging production runtime artifacts..." -ForegroundColor Yellow
$null = New-Item -ItemType Directory -Path $galleryAotOut -Force
dotnet build (Join-Path $projectDir "AOT\TerminalAI.Aot.csproj") -c Release -t:Rebuild -p:SkipRootCopy=true -o $galleryAotOut --nologo | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Fresh Gallery AOT build failed." }
$freshAotDll = Join-Path $galleryAotOut "TerminalAI.Aot.dll"
if (-not (Test-Path $freshAotDll)) { throw "Fresh Gallery AOT output missing: $freshAotDll" }
$runtimeFiles = @(
    "TerminalAI.psd1",
    "TerminalAI.psm1",
    "TerminalAiConfig.ps1",
    "TerminalAiAssistant.ps1",
    "TerminalAiAgent.ps1",
    "TerminalAI.Aot.dll-Help.xml",
    "terminalai.json",
    "README.md",
    "README.uk.md",
    "LICENSE"
)

foreach ($file in $runtimeFiles) {
    $src = Join-Path $projectDir $file
    if (-not (Test-Path $src)) {
        throw "Required production file missing: $src"
    }
    $dest = Join-Path $StagingPath $file
    Copy-Item -Path $src -Destination $dest -Force
    Write-Host "   ✔ Staged: $file" -ForegroundColor DarkGray
}
Copy-Item $freshAotDll (Join-Path $StagingPath "TerminalAI.Aot.dll") -Force
Write-Host "   ✔ Staged fresh AOT build: TerminalAI.Aot.dll" -ForegroundColor DarkGray

# Keep every local Markdown target linked by the README in the Gallery package.
$docFiles = @(
    @{ Source = "docs\TECHNICAL.md"; Destination = "docs\TECHNICAL.md" },
    @{ Source = "AOT\README.md"; Destination = "AOT\README.md" },
    @{ Source = "AOT\README.uk.md"; Destination = "AOT\README.uk.md" }
)
foreach ($doc in $docFiles) {
    $source = Join-Path $projectDir $doc.Source
    if (-not (Test-Path $source)) { throw "Required documentation missing: $source" }
    $destination = Join-Path $StagingPath $doc.Destination
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item $source $destination -Force
}

$cert = $null
if ($CertificateThumbprint) {
    $normalized = $CertificateThumbprint -replace '\s',''
    $cert = Get-ChildItem Cert:\CurrentUser\My,Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $normalized } | Select-Object -First 1
    if (-not $cert) { throw "Code-signing certificate thumbprint not found: $normalized" }
    $signed = Set-AuthenticodeSignature -FilePath (Join-Path $StagingPath "TerminalAI.Aot.dll") -Certificate $cert
    if ($signed.Status -ne "Valid") { throw "Signing failed for staged TerminalAI.Aot.dll: $($signed.Status)" }
    Write-Host "Signed staged TerminalAI.Aot.dll with certificate $($cert.Thumbprint)."
} elseif (-not $AllowUnsigned) {
    throw "No code-signing certificate supplied. Re-run with -CertificateThumbprint or explicit -AllowUnsigned."
} else {
    Write-Host "UNSIGNED: no code-signing certificate supplied; -AllowUnsigned acknowledged." -ForegroundColor Yellow
}
$galleryCommit = (& git -C $projectDir rev-parse HEAD).Trim()
$galleryProvenance = [ordered]@{
    commit = $galleryCommit
    dirty = (@(& git -C $projectDir status --porcelain).Count -gt 0)
    signed = ([bool]$cert)
    artifactHashes = [ordered]@{ "TerminalAI.Aot.dll" = (Get-FileHash (Join-Path $StagingPath "TerminalAI.Aot.dll") -Algorithm SHA256).Hash }
}
[IO.File]::WriteAllText((Join-Path $StagingPath "GALLERY-PROVENANCE.json"), (($galleryProvenance | ConvertTo-Json -Depth 3) + "`n"), (New-Object Text.UTF8Encoding($false)))

# 3. Validate staged module manifest
Write-Host "`n3. Validating staged module manifest..." -ForegroundColor Yellow
$stagedManifest = Join-Path $StagingPath "TerminalAI.psd1"
$manifestInfo = Test-ModuleManifest -Path $stagedManifest -ErrorAction Stop
Write-Host "   ✔ Name: $($manifestInfo.Name)" -ForegroundColor Green
Write-Host "   ✔ Version: $($manifestInfo.Version)" -ForegroundColor Green
Write-Host "   ✔ Author: $($manifestInfo.Author)" -ForegroundColor Green
Write-Host "   ✔ Exported Functions: $($manifestInfo.ExportedFunctions.Count)" -ForegroundColor Green
Write-Host "   ✔ Exported Cmdlets: $($manifestInfo.ExportedCmdlets.Count)" -ForegroundColor Green
Write-Host "   ✔ Exported Aliases: $($manifestInfo.ExportedAliases.Count)" -ForegroundColor Green

# PSGallery mandatory metadata check
$psData = $manifestInfo.PrivateData.PSData
if (-not $psData.ProjectUri) { throw "PSGallery requires ProjectUri in PSData." }
if (-not $psData.LicenseUri) { throw "PSGallery requires LicenseUri in PSData." }
if (-not $psData.Tags -or $psData.Tags.Count -eq 0) { throw "PSGallery requires Tags in PSData." }
Write-Host "   ✔ PSGallery metadata (ProjectUri, LicenseUri, Tags) validated." -ForegroundColor Green

# 4. Verify no prohibited development files are present
Write-Host "`n4. Auditing package purity (zero test / dev leak)..." -ForegroundColor Yellow
$prohibitedPatterns = @("*.Tests.ps1", "*.cs", "*.csproj", "*.sln", "scratch*", "*.tmp", ".git*")
$stagedFiles = Get-ChildItem -Path $StagingPath -Recurse -File
$violations = @()
foreach ($file in $stagedFiles) {
    foreach ($pat in $prohibitedPatterns) {
        if ($file.Name -like $pat) {
            $violations += $file.FullName
        }
    }
}
if ($violations.Count -gt 0) {
    throw "Purity audit failed! Prohibited files found in package: $($violations -join ', ')"
}
Write-Host "   ✔ Package contains exactly $($stagedFiles.Count) clean production files (0 dev leaks)." -ForegroundColor Green

# 5. Local repository simulation or actual publish
if ($CreateLocalRepo) {
    Write-Host "`n5. Testing offline publication against local repository..." -ForegroundColor Yellow
    $localRepoPath = Join-Path $projectDir "dist\LocalNuGetRepo"
    if (-not (Test-Path $localRepoPath)) {
        $null = New-Item -ItemType Directory -Path $localRepoPath -Force
    }
    
    $repoName = "TerminalAiLocalTest"
    if (-not (Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Name $repoName -SourceLocation $localRepoPath -PublishLocation $localRepoPath -InstallationPolicy Trusted
    }
    
    try {
        Publish-Module -Path $StagingPath -Repository $repoName -Force
        Write-Host "   ✔ Successfully published to local test repository: $localRepoPath" -ForegroundColor Green
    } finally {
        Unregister-PSRepository -Name $repoName -ErrorAction SilentlyContinue
    }
}

if (-not [string]::IsNullOrWhiteSpace($NuGetApiKey) -and -not $DryRun) {
    if ($galleryProvenance.dirty) { throw "Public Gallery publication requires a clean git tree." }
    Write-Host "`n6. Publishing to PowerShell Gallery ($Repository)..." -ForegroundColor Cyan
    if ($PSCmdlet.ShouldProcess("PowerShell Gallery", "Publish Module TerminalAI v$($manifestInfo.Version)")) {
        Publish-Module -Path $StagingPath -NuGetApiKey $NuGetApiKey -Repository $Repository -Verbose
        Write-Host "`n✔ Successfully published TerminalAI v$($manifestInfo.Version) to $Repository!" -ForegroundColor Green
    }
} else {
    Write-Host "`n✔ Staging and local validation completed. Public publication still requires signing, credentials, approval, and live verification." -ForegroundColor Green
    Write-Host "   • To publish: .\tools\Publish-TerminalAiGallery.ps1 -NuGetApiKey <Your-API-Key>`n" -ForegroundColor DarkCyan
}
} finally {
    if (Test-Path $galleryBuildRoot) { Remove-Item $galleryBuildRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
