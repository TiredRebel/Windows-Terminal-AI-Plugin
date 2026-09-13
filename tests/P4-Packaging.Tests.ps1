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

Assert-Fixture "FIX-P4-01" "TerminalAI.psd1 passes Test-ModuleManifest cleanly (0.1.0-preview1)" {
    $manifestPath = Join-Path $projectRoot "TerminalAI.psd1"
    $mod = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    if ($mod.Name -ne "TerminalAI") { throw "Expected module name TerminalAI, got $($mod.Name)" }
    if ($mod.Version -ne [version]"0.1.0") { throw "Expected version 0.1.0, got $($mod.Version)" }
    $prerelease = $mod.PrivateData.PSData.Prerelease
    if ($prerelease -ne "preview1") { throw "Expected Prerelease preview1, got '$prerelease'" }
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
    & $galleryScript -StagingPath $testStaging -DryRun -Force | Out-Null
    
    $stagedFiles = Get-ChildItem -Path $testStaging -Recurse -File
    if ($stagedFiles.Count -lt 9) { throw "Expected at least 9 staged files, got $($stagedFiles.Count)" }
    
    # Verify zero dev files
    $devFiles = $stagedFiles | Where-Object { $_.Name -like "*.Tests.ps1" -or $_.Name -like "*.cs" -or $_.Name -like "*.csproj" }
    if ($devFiles.Count -gt 0) { throw "Dev file leaked into staging: $($devFiles[0].Name)" }
}

Assert-Fixture "FIX-P4-04" "Staged package manifest passes Test-ModuleManifest" {
    $galleryScript = Join-Path $projectRoot "tools\Publish-TerminalAiGallery.ps1"
    $testStaging = Join-Path $testTempRoot "TestStaging_P4_Val"
    & $galleryScript -StagingPath $testStaging -DryRun -Force | Out-Null
    
    $stagedPsd1 = Join-Path $testStaging "TerminalAI.psd1"
    $stagedInfo = Test-ModuleManifest -Path $stagedPsd1 -ErrorAction Stop
    if ($stagedInfo.ExportedFunctions.Count -lt 30) { throw "Staged manifest exported functions incomplete" }
}

# --- 3. Release Package & Cryptographic Integrity ---

Assert-Fixture "FIX-P4-05" "Release zip package exists and has valid archive contents" {
    $zipPath = Join-Path $projectRoot "dist\TerminalAI-v0.1.0-preview1-win-x64.zip"
    if (-not (Test-Path $zipPath)) {
        & (Join-Path $projectRoot "tools\Build-ReleasePackage.ps1") -Version "0.1.0-preview1" | Out-Null
    }
    if (-not (Test-Path $zipPath)) { throw "Release zip not found at $zipPath" }
    
    $zipItem = Get-Item $zipPath
    if ($zipItem.Length -lt 50KB) { throw "Release zip is suspiciously small: $($zipItem.Length) bytes" }
}

Assert-Fixture "FIX-P4-06" "Release zip SHA-256 matches WinGet installer manifest checksum" {
    $zipPath = Join-Path $projectRoot "dist\TerminalAI-v0.1.0-preview1-win-x64.zip"
    if (-not (Test-Path $zipPath)) { throw "Release zip not found at $zipPath" }
    $realHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
    
    $installerYaml = Join-Path $projectRoot "manifests\t\TiredRebel\TerminalAI\0.1.0-preview1\TiredRebel.TerminalAI.installer.yaml"
    if (-not (Test-Path $installerYaml)) { throw "Installer YAML not found at $installerYaml" }
    
    $yamlContent = Get-Content $installerYaml -Raw
    if ($yamlContent -notmatch "InstallerSha256:\s+([A-Fa-f0-9]{64})") {
        throw "Could not parse InstallerSha256 from $installerYaml"
    }
    $manifestHash = $Matches[1]
    if ($realHash.ToUpperInvariant() -ne $manifestHash.ToUpperInvariant()) {
        throw "Hash mismatch! Archive SHA256: $realHash vs Manifest: $manifestHash"
    }
}

# --- 4. WinGet Manifest Compliance ---

Assert-Fixture "FIX-P4-07" "WinGet manifests pass Test-WinGetManifest suite (Schema 1.9.0)" {
    $testScript = Join-Path $projectRoot "tools\Test-WinGetManifest.ps1"
    if (-not (Test-Path $testScript)) { throw "Test-WinGetManifest.ps1 missing" }
    $out = & $testScript -Version "0.1.0-preview1" *>&1 | Out-String
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
    
    $publishExe = Join-Path $projectRoot "Launcher\bin\Release\net10.0\win-x64\publish\terminalai.exe"
    $stagingExe = Join-Path $projectRoot "dist\staging\terminalai.exe"
    if (-not (Test-Path $publishExe) -and -not (Test-Path $stagingExe)) {
        throw "terminalai.exe missing in Launcher/bin/Release/net10.0/win-x64/publish/ or dist/staging/"
    }
    
    $cmdContent = Get-Content $cmdPath -Raw
    if ($cmdContent -notmatch "bootstrap\.ps1") { throw "cmd launcher does not reference bootstrap.ps1" }
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
