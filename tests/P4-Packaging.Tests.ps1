# P4-Packaging.Tests.ps1 - Packaging, Bootstrapper & Distribution Test Suite
[CmdletBinding()]
param(
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path "$PSScriptRoot\..").Path

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  TerminalAI Phase P4 Test Suite: Packaging & Distribution " -ForegroundColor Cyan
Write-Host "  PowerShell Version: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

# --- Test Isolation: Protect real user config, profiles, and directories ---
$origConfigDir = $env:TERMINAL_AI_CONFIG_DIR
$origLang = $env:TERMINAL_AI_LANG
$testTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("TerminalAiTest_P4_" + [System.Guid]::NewGuid().ToString("N"))
$testConfigDir = Join-Path $testTempRoot "config"
New-Item -ItemType Directory -Path $testConfigDir -Force | Out-Null
$env:TERMINAL_AI_CONFIG_DIR = $testConfigDir

$passed = 0
$failed = 0
$fixtures = [System.Collections.Generic.List[string]]::new()

function Assert-Fixture {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$TestBlock
    )
    Write-Host -NoNewline "  [$Id] $Description ... "
    try {
        & $TestBlock
        Write-Host "PASS" -ForegroundColor Green
        $script:passed++
        $script:fixtures.Add("PASS: $Id - $Description")
    }
    catch {
        Write-Host "FAIL" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkRed
        $script:failed++
        $script:fixtures.Add("FAIL: $Id - $Description - $($_.Exception.Message)")
    }
}

try {

# --- 1. PowerShell Gallery Manifest Validation ---

Assert-Fixture "FIX-P4-01" "TerminalAI.psd1 passes Test-ModuleManifest cleanly (0.1.0-preview2)" {
    $manifestPath = Join-Path $projectRoot "TerminalAI.psd1"
    $mod = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    if ($mod.Name -ne "TerminalAI") { throw "Expected module name TerminalAI, got $($mod.Name)" }
    if ($mod.Version -ne [version]"0.1.0") { throw "Expected version 0.1.0, got $($mod.Version)" }
    $prerelease = $mod.PrivateData.PSData.Prerelease
    if ($prerelease -ne "preview2") { throw "Expected Prerelease preview2, got '$prerelease'" }
}

Assert-Fixture "FIX-P4-02" "TerminalAI.psd1 declares all required PSGallery metadata fields" {
    $manifestPath = Join-Path $projectRoot "TerminalAI.psd1"
    $mod = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($mod.Author)) { throw "Author is empty" }
    if ([string]::IsNullOrWhiteSpace($mod.Description)) { throw "Description is empty" }
    
    $psData = $mod.PrivateData.PSData
    if (-not $psData) { throw "PrivateData.PSData is missing" }
    if (-not $psData.ProjectUri) { throw "PSData.ProjectUri is missing" }
    if (-not $psData.LicenseUri) { throw "PSData.LicenseUri is missing" }
    if (-not $psData.ReleaseNotes) { throw "PSData.ReleaseNotes is missing" }
    if (-not $psData.Tags -or $psData.Tags.Count -lt 5) { throw "PSData.Tags has fewer than 5 tags" }
}

# --- 2. PowerShell Gallery Staging Engine ---

Assert-Fixture "FIX-P4-03" "Publish-TerminalAiGallery stages pure package without dev leaks" {
    $galleryScript = Join-Path $projectRoot "tools\Publish-TerminalAiGallery.ps1"
    if (-not (Test-Path $galleryScript)) { throw "Publish-TerminalAiGallery.ps1 missing" }
    
    $testStaging = Join-Path $testTempRoot "TestStaging_P4"
    $rootDllBefore = (Get-FileHash (Join-Path $projectRoot "TerminalAI.Aot.dll") -Algorithm SHA256).Hash
    & $galleryScript -StagingPath $testStaging -DryRun -Force -AllowUnsigned | Out-Null
    $rootDllAfter = (Get-FileHash (Join-Path $projectRoot "TerminalAI.Aot.dll") -Algorithm SHA256).Hash
    if ($rootDllBefore -ne $rootDllAfter) { throw "Gallery staging modified tracked root AOT DLL." }
    $galleryProv = Get-Content (Join-Path $testStaging "GALLERY-PROVENANCE.json") -Raw | ConvertFrom-Json
    if ($galleryProv.commit -ne ((& git -C $projectRoot rev-parse HEAD).Trim())) { throw "Gallery provenance commit mismatch." }
    $stagedDll = Join-Path $testStaging "TerminalAI.Aot.dll"
    if ($galleryProv.artifactHashes.'TerminalAI.Aot.dll' -ne (Get-FileHash $stagedDll -Algorithm SHA256).Hash) { throw "Gallery staged DLL hash mismatch." }
    
    $stagedFiles = Get-ChildItem -Path $testStaging -Recurse -File
    if ($stagedFiles.Count -lt 12) { throw "Expected at least 12 staged files, got $($stagedFiles.Count)" }
    foreach ($required in @("README.uk.md","docs\TECHNICAL.md","AOT\README.md","AOT\README.uk.md","LICENSE")) { if (-not (Test-Path (Join-Path $testStaging $required))) { throw "Missing staged documentation: $required" } }
    foreach ($readme in @("README.md","README.uk.md","AOT\README.md","AOT\README.uk.md")) {
        $base = Split-Path (Join-Path $testStaging $readme)
        foreach ($match in [regex]::Matches((Get-Content (Join-Path $testStaging $readme) -Raw), '\[[^]]+\]\(([^)#]+)(?:#[^)]+)?\)')) {
            $target = $match.Groups[1].Value
            if ($target -notmatch '^(?i:https?://|mailto:)') {
                $resolved = Join-Path $base $target
                if (-not (Test-Path $resolved)) { throw "Broken staged README link: $readme -> $target" }
            }
        }
    }
    
    # Verify zero dev files
    $devFiles = $stagedFiles | Where-Object { $_.Name -like "*.Tests.ps1" -or $_.Name -like "*.cs" -or $_.Name -like "*.csproj" }
    if ($devFiles.Count -gt 0) { throw "Dev file leaked into staging: $($devFiles[0].Name)" }
}

Assert-Fixture "FIX-P4-04" "Staged package manifest passes Test-ModuleManifest" {
    $galleryScript = Join-Path $projectRoot "tools\Publish-TerminalAiGallery.ps1"
    $testStaging = Join-Path $testTempRoot "TestStaging_P4_Val"
    & $galleryScript -StagingPath $testStaging -DryRun -Force -AllowUnsigned | Out-Null
    
    $stagedPsd1 = Join-Path $testStaging "TerminalAI.psd1"
    $stagedInfo = Test-ModuleManifest -Path $stagedPsd1 -ErrorAction Stop
    if ($stagedInfo.ExportedFunctions.Count -lt 30) { throw "Staged manifest exported functions incomplete" }
}

Assert-Fixture "FIX-P4-04A" "Public Gallery publication rejects dirty working trees" {
    $galleryScript = Join-Path $projectRoot "tools\Publish-TerminalAiGallery.ps1"
    $dirtyStaging = Join-Path $testTempRoot "PublicDirtyGallery"
    $rejected = $false
    try { & $galleryScript -StagingPath $dirtyStaging -Force -AllowUnsigned -NuGetApiKey "test-only-key" -ErrorAction Stop } catch { $rejected = $_.Exception.Message -match "clean git tree" }
    if (-not $rejected) { throw "Public Gallery path did not reject dirty working tree." }
}

# --- 3. Release Package & Cryptographic Integrity ---

Assert-Fixture "FIX-P4-05" "Release zip is freshly rebuilt in isolated output and ignores stale archive" {
    $buildOut = Join-Path $testTempRoot "release"
    New-Item -ItemType Directory -Path $buildOut -Force | Out-Null
    $zipPath = Join-Path $buildOut "TerminalAI-v0.1.0-preview2-win-x64.zip"
    [IO.File]::WriteAllText($zipPath, "stale preview2 archive")
    & (Join-Path $projectRoot "tools\Build-ReleasePackage.ps1") -Version "0.1.0-preview2" -OutputDir $buildOut -AllowUnsigned -AllowDirty | Out-Null
    if (-not (Test-Path $zipPath)) { throw "Release zip not found at $zipPath" }
    
    $zipItem = Get-Item $zipPath
    if ($zipItem.Length -lt 50KB) { throw "Release zip is suspiciously small: $($zipItem.Length) bytes" }
}

Assert-Fixture "FIX-P4-06" "Release provenance, docs, source hashes, and WinGet checksum are current" {
    $buildOut = Join-Path $testTempRoot "release"
    $zipPath = Join-Path $buildOut "TerminalAI-v0.1.0-preview2-win-x64.zip"
    if (-not (Test-Path $zipPath)) { throw "Release zip not found at $zipPath" }
    $realHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
    
    $installerYaml = Join-Path $projectRoot "manifests\t\TiredRebel\TerminalAI\0.1.0-preview2\TiredRebel.TerminalAI.installer.yaml"
    if (-not (Test-Path $installerYaml)) { throw "Installer YAML not found at $installerYaml" }
    
    $yamlContent = Get-Content $installerYaml -Raw
    if ($yamlContent -notmatch "InstallerSha256:\s+([A-Fa-f0-9]{64})") {
        throw "Could not parse InstallerSha256 from $installerYaml"
    }
    $manifestHash = $Matches[1]
    if ($realHash.ToUpperInvariant() -ne $manifestHash.ToUpperInvariant()) {
        throw "Hash mismatch! Archive SHA256: $realHash vs Manifest: $manifestHash"
    }
    $extract = Join-Path $testTempRoot "extract"
    Expand-Archive $zipPath $extract -Force
    $prov = Get-Content (Join-Path $extract "RELEASE-PROVENANCE.json") -Raw | ConvertFrom-Json
    if ($prov.version -ne "0.1.0-preview2") { throw "Wrong provenance version: $($prov.version)" }
    $head = (& git -C $projectRoot rev-parse HEAD).Trim()
    if ($prov.commit -ne $head) { throw "Provenance commit mismatch: $($prov.commit) vs $head" }
    if (-not $prov.dirty) { throw "Candidate test build must identify dirty working-tree content." }
    foreach ($entry in $prov.artifactHashes.psobject.Properties) {
        $archived = Join-Path $extract $entry.Name
        if (-not (Test-Path $archived)) { throw "Artifact missing: $($entry.Name)" }
        if ((Get-FileHash $archived -Algorithm SHA256).Hash -ne $entry.Value) { throw "Artifact hash mismatch: $($entry.Name)" }
    }
    foreach ($entry in $prov.sourceHashes.psobject.Properties) {
        $relative = $entry.Name -replace '/', '\\'; $source = Join-Path $projectRoot $relative
        if (-not (Test-Path $source)) { throw "Provenance source missing: $relative" }
        if ((Get-FileHash $source -Algorithm SHA256).Hash -ne $entry.Value) { throw "Source hash mismatch: $relative" }
        $archived = Join-Path $extract $relative
        if (-not (Test-Path $archived)) { throw "Provenance archive file missing: $relative" }
        if ((Get-FileHash $archived -Algorithm SHA256).Hash -ne $entry.Value) { throw "Archive content hash mismatch: $relative" }
    }
    foreach ($required in @("README.uk.md","docs\TECHNICAL.md","AOT\README.md","AOT\README.uk.md","LICENSE")) { if (-not (Test-Path (Join-Path $extract $required))) { throw "Archive missing: $required" } }
}

Assert-Fixture "FIX-P4-06A" "Unsigned release packaging requires explicit acknowledgement" {
    $unsignedOut = Join-Path $testTempRoot "unsigned-no-ack"
    $failedAsExpected = $false
    try { & (Join-Path $projectRoot "tools\Build-ReleasePackage.ps1") -Version "0.1.0-preview2" -OutputDir $unsignedOut -SkipZip -AllowDirty -ErrorAction Stop } catch { $failedAsExpected = $true }
    if (-not $failedAsExpected) { throw "Packaging unexpectedly succeeded without -AllowUnsigned or a certificate." }
}

Assert-Fixture "FIX-P4-06B" "Publishable release packaging rejects dirty working trees" {
    $failedAsExpected = $false
    try { & (Join-Path $projectRoot "tools\Build-ReleasePackage.ps1") -Version "0.1.0-preview2" -OutputDir (Join-Path $testTempRoot "dirty-release") -SkipZip -ErrorAction Stop } catch { $failedAsExpected = $_.Exception.Message -match "clean git tree" }
    if (-not $failedAsExpected) { throw "Dirty-tree release guard did not reject the candidate." }
}

# --- 4. WinGet Manifest Compliance ---

Assert-Fixture "FIX-P4-07" "WinGet manifests pass Test-WinGetManifest suite (Schema 1.9.0)" {
    $testScript = Join-Path $projectRoot "tools\Test-WinGetManifest.ps1"
    if (-not (Test-Path $testScript)) { throw "Test-WinGetManifest.ps1 missing" }
    $out = & $testScript *>&1 | Out-String
    if ($out -match "Manifest validation failed|Error" -or $LASTEXITCODE -ne 0) {
        throw "WinGet validation reported errors: $out"
    }
    if ($out -notmatch "Schema 1\.9\.0") {
        throw "WinGet validation did not verify Schema 1.9.0"
    }
}

# --- 5. One-Command Portable Bootstrapper ---

Assert-Fixture "FIX-P4-08" "bootstrap.ps1 parses cleanly and supports -Mode Portable" {
    $bootScript = Join-Path $projectRoot "bootstrap.ps1"
    if (-not (Test-Path $bootScript)) { throw "bootstrap.ps1 missing" }
    
    # Syntax check
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($bootScript, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Syntax error in bootstrap.ps1: $($errors[0].Message)" }
}

Assert-Fixture "FIX-P4-09" "bootstrap.ps1 -Mode Portable executes without modifying `$PROFILE or user config" {
    $fakeProfile = Join-Path $testTempRoot "fake_profile.ps1"
    $initialProfileContent = "# Test profile initial content"
    [System.IO.File]::WriteAllText($fakeProfile, $initialProfileContent, [System.Text.Encoding]::UTF8)

    $bootScript = Join-Path $projectRoot "bootstrap.ps1"
    if (-not (Test-Path $bootScript)) { throw "bootstrap.ps1 missing" }

    $escapedBoot = $bootScript -replace "'", "''"
    $escapedFakeProfile = $fakeProfile -replace "'", "''"
    $escapedCfgDir = $testConfigDir -replace "'", "''"

    $childCmd = "& { `$env:TERMINAL_AI_CONFIG_DIR = '$escapedCfgDir'; `$PROFILE = '$escapedFakeProfile'; & '$escapedBoot' -Mode Portable -SkipOllama -NonInteractive | Out-Null }"
    $proc = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList "-NoProfile", "-NonInteractive", "-Command", $childCmd -PassThru -Wait -WindowStyle Hidden
    
    if ($proc.ExitCode -ne 0) {
        throw "bootstrap.ps1 returned non-zero exit code: $($proc.ExitCode)"
    }
    
    $profileAfter = [System.IO.File]::ReadAllText($fakeProfile)
    if ($initialProfileContent -ne $profileAfter) {
        throw "Portable mode must not modify `$PROFILE!"
    }
}

# --- 6. Native Desktop Launcher ---

Assert-Fixture "FIX-P4-10" "Native launcher (terminalai.exe) and batch script exist and are valid" {
    $cmdPath = Join-Path $projectRoot "TerminalAI-Portable.cmd"
    if (-not (Test-Path $cmdPath)) { throw "TerminalAI-Portable.cmd missing" }
    
    $stagingExe = Join-Path $testTempRoot "release\staging\terminalai.exe"
    if (-not (Test-Path $stagingExe)) { throw "fresh isolated terminalai.exe missing: $stagingExe" }
    $provenance = Get-Content (Join-Path $testTempRoot "release\staging\RELEASE-PROVENANCE.json") -Raw | ConvertFrom-Json
    if ($provenance.artifactHashes.'terminalai.exe' -ne (Get-FileHash $stagingExe -Algorithm SHA256).Hash) { throw "Fresh launcher hash does not match provenance." }
    
    $cmdContent = Get-Content $cmdPath -Raw
    if ($cmdContent -notmatch "bootstrap\.ps1") { throw "cmd launcher does not reference bootstrap.ps1" }
}

Assert-Fixture "FIX-P4-11" "Documentation quality checker passes offline" {
    $checker = Join-Path $projectRoot "tools\Test-DocumentationQuality.ps1"
    if (-not (Test-Path -LiteralPath $checker)) { throw "Test-DocumentationQuality.ps1 missing" }
    $out = & $checker -Root $projectRoot *>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Documentation quality check failed: $out" }
    if ($out -match '(?m)^UNKNOWN:') { throw "Offline checker must not report unknown live state: $out" }
}

# --- Summary ---
Write-Host "`n------------------------------------------------------------"
Write-Host "Results: $passed / $($passed + $failed) passed ($failed failed)"
Write-Host "------------------------------------------------------------`n"

} finally {
    # Guaranteed cleanup of isolated test environment
    $env:TERMINAL_AI_CONFIG_DIR = $origConfigDir
    $env:TERMINAL_AI_LANG = $origLang
    if ($testTempRoot -and (Test-Path $testTempRoot)) {
        Remove-Item -Path $testTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}
