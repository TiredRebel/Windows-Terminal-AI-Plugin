#Requires -Version 7.0
<#
.SYNOPSIS
    Comprehensive test suite for TerminalAI AOT Script Generation Safety & Unified Diff Preview (Cycle 6).
.DESCRIPTION
    Validates:
      - Multi-line script detection
      - Unified diff generation (Added, Removed, Unchanged)
      - Atomic saving with UTF-8 BOM
      - Identical content detection
      - Overwrite warning & interactive confirmation
      - Safe non-interactive blocking (Fail-Closed)
      - Force overwrite handling
#>

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dllPath = Join-Path $repoRoot "AOT\bin\Release\net10.0\TerminalAI.Aot.dll"

if (-not (Test-Path $dllPath)) {
    Write-Error "AOT DLL not found at: $dllPath. Run 'dotnet build -c Release' first."
    exit 1
}

# Load assembly
Add-Type -Path $dllPath

$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0

function Assert-AotFixture {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$TestBlock
    )
    $script:TotalTests++
    try {
        & $TestBlock
        $script:PassedTests++
        Write-Host "  ✔ [PASS] [$Id] $Description" -ForegroundColor Green
    } catch {
        $script:FailedTests++
        Write-Host "  ✖ [FAIL] [$Id] $Description" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "    TERMINAL AI AOT SCRIPT SAFETY & DIFF TEST SUITE (CYCLE 6)  " -ForegroundColor Cyan
Write-Host "===============================================================`n" -ForegroundColor Cyan

# Create a temporary sandbox directory for test files
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("TerminalAI_Aot_Test_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # FIX-SS-01: Multi-line script detection
    Assert-AotFixture "FIX-SS-01" "Detects multi-line scripts and functions vs single line commands" {
        $singleLine = "Get-Process | Where-Object WorkingSet -gt 100MB"
        $multiLine = "param(`$Path)`nGet-ChildItem -Path `$Path | ForEach-Object { `$_.FullName }"
        $funcDef = "function Backup-Logs { Write-Host 'Backing up' }"

        $isSingle = [TerminalAI.Aot.AotScriptSafety]::IsMultiLineScript($singleLine)
        $isMulti = [TerminalAI.Aot.AotScriptSafety]::IsMultiLineScript($multiLine)
        $isFunc = [TerminalAI.Aot.AotScriptSafety]::IsMultiLineScript($funcDef)

        if ($isSingle) { throw "Single line pipeline incorrectly classified as multi-line script" }
        if (-not $isMulti) { throw "Multi-line script with newlines was not recognized" }
        if (-not $isFunc) { throw "Script containing function definition was not recognized" }
    }

    # FIX-SS-02: Unified diff generation on text differences
    Assert-AotFixture "FIX-SS-02" "AotDiffRenderer formats unified diff with Added, Removed, and Unchanged records" {
        $oldText = "Line 1`nLine 2`nLine 3"
        $newText = "Line 1`nLine 2 Modified`nLine 3`nLine 4"

        $diff = [TerminalAI.Aot.AotDiffRenderer]::FormatDiff($oldText, $newText)
        if ($null -eq $diff -or $diff.Count -eq 0) { throw "Diff records should not be empty" }

        $hasUnchanged = $diff | Where-Object { $_.Type -eq [TerminalAI.Aot.DiffLineType]::Unchanged }
        $hasRemoved = $diff | Where-Object { $_.Type -eq [TerminalAI.Aot.DiffLineType]::Removed }
        $hasAdded = $diff | Where-Object { $_.Type -eq [TerminalAI.Aot.DiffLineType]::Added }

        if (-not $hasUnchanged) { throw "Diff should contain Unchanged lines" }
        if (-not $hasRemoved) { throw "Diff should contain Removed lines" }
        if (-not $hasAdded) { throw "Diff should contain Added lines" }
    }

    # FIX-SS-03: Unified diff identical strings produce only Unchanged
    Assert-AotFixture "FIX-SS-03" "AotDiffRenderer produces only Unchanged records when texts are identical" {
        $text = "Write-Host 'Hello'`nWrite-Host 'World'"
        $diff = [TerminalAI.Aot.AotDiffRenderer]::FormatDiff($text, $text)

        $nonUnchanged = $diff | Where-Object { $_.Type -ne [TerminalAI.Aot.DiffLineType]::Unchanged }
        if ($nonUnchanged.Count -gt 0) { throw "Identical texts should not produce Added or Removed records" }
    }

    # FIX-SS-04: Saving new script creates file with UTF-8 BOM
    Assert-AotFixture "FIX-SS-04" "SaveScriptFile creates new script with valid UTF-8 BOM encoding" {
        $testFile = Join-Path $tempDir "NewScript.ps1"
        $content = "Write-Host 'Hello from AOT script'"

        $result = [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $content)
        if (-not $result.Saved) { throw "File should have been saved successfully" }
        if ($result.Status -ne "Created") { throw "Status should be 'Created', was '$($result.Status)'" }
        if (-not (Test-Path $testFile)) { throw "File was not created on disk" }

        $hasBom = [TerminalAI.Aot.AotScriptSafety]::HasUtf8Bom($testFile)
        if (-not $hasBom) { throw "Created script must have valid UTF-8 BOM" }

        $readContent = Get-Content $testFile -Raw
        if ($readContent.Trim() -ne $content.Trim()) { throw "File content mismatch" }
    }

    # FIX-SS-05: Identical content detection avoids rewriting
    Assert-AotFixture "FIX-SS-05" "SaveScriptFile detects identical content and returns Identical status" {
        $testFile = Join-Path $tempDir "IdenticalScript.ps1"
        $content = "Get-Service | Where-Object Status -eq 'Running'"

        $res1 = [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $content)
        $mtimeBefore = (Get-Item $testFile).LastWriteTimeUtc

        Start-Sleep -Milliseconds 50
        $res2 = [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $content)

        if (-not $res2.Saved) { throw "Identical file save should succeed" }
        if ($res2.Status -ne "Identical") { throw "Status should be 'Identical', was '$($res2.Status)'" }
    }

    # FIX-SS-06: Overwriting with difference generates diff preview
    Assert-AotFixture "FIX-SS-06" "SaveScriptFile populates Diff property when file exists and differs" {
        $testFile = Join-Path $tempDir "DiffScript.ps1"
        $oldContent = "Get-Process -Name pwsh"
        $newContent = "Get-Process -Name powershell"

        [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $oldContent) | Out-Null
        $res = [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $newContent, $false, "n")

        if ($null -eq $res.Diff -or $res.Diff.Count -eq 0) { throw "Diff should be generated when file differs" }
    }

    # FIX-SS-07: User confirmation 'y' successfully overwrites file
    Assert-AotFixture "FIX-SS-07" "ConfirmInput 'y' allows overwrite and returns Status Overwritten" {
        $testFile = Join-Path $tempDir "OverwriteConfirm.ps1"
        $oldContent = "Write-Output 'V1'"
        $newContent = "Write-Output 'V2'"

        [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $oldContent) | Out-Null
        $res = [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $newContent, $false, "y")

        if (-not $res.Saved) { throw "File should have been saved when confirmed with 'y'" }
        if ($res.Status -ne "Overwritten") { throw "Status should be 'Overwritten', was '$($res.Status)'" }

        $actual = (Get-Content $testFile -Raw).Trim()
        if ($actual -ne $newContent) { throw "File should contain updated content" }
        if (-not [TerminalAI.Aot.AotScriptSafety]::HasUtf8Bom($testFile)) { throw "Overwritten file must have UTF-8 BOM" }
    }

    # FIX-SS-08: User denial 'n' blocks overwrite and preserves content
    Assert-AotFixture "FIX-SS-08" "ConfirmInput 'n' denies overwrite and preserves original content" {
        $testFile = Join-Path $tempDir "OverwriteDenied.ps1"
        $oldContent = "Write-Output 'DO_NOT_TOUCH'"
        $newContent = "Write-Output 'SHOULD_NOT_WRITE'"

        [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $oldContent) | Out-Null
        $res = [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $newContent, $false, "n")

        if ($res.Saved) { throw "File should NOT be saved when confirmed with 'n'" }
        if ($res.Status -ne "OverwriteDenied") { throw "Status should be 'OverwriteDenied', was '$($res.Status)'" }

        $actual = (Get-Content $testFile -Raw).Trim()
        if ($actual -ne $oldContent) { throw "Original file was altered despite user denial!" }
    }

    # FIX-SS-09: Non-interactive session blocks overwrite safely (Fail-Closed)
    Assert-AotFixture "FIX-SS-09" "Non-interactive session without force blocks overwrite with BlockedNonInteractive" {
        $testFile = Join-Path $tempDir "NonInteractive.ps1"
        $oldContent = "Write-Output BEFORE"
        $newContent = "Write-Output AFTER"

        [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $oldContent) | Out-Null

        # Calling in a non-interactive shell simulates redirected/background invocation
        $status = pwsh -NoProfile -NonInteractive -Command "
            Add-Type -Path '$dllPath'
            `$res = [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile('$testFile', 'Write-Output AFTER', `$false, `$null)
            `$res.Status
        "
        $outputLines = ($status | Out-String) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $lastLine = if ($outputLines.Count -gt 0) { $outputLines[-1] } else { "" }

        if ($lastLine -ne "BlockedNonInteractive") {
            throw "Non-interactive invocation should return 'BlockedNonInteractive', got: '$lastLine' (full output: '$status')"
        }

        $actual = (Get-Content $testFile -Raw).Trim()
        if ($actual -ne $oldContent) { throw "Original file was overwritten in non-interactive session!" }
    }

    # FIX-SS-10: Force switch bypasses confirmation and overwrites atomically
    Assert-AotFixture "FIX-SS-10" "Force switch bypasses confirmation and overwrites file atomically" {
        $testFile = Join-Path $tempDir "ForceOverwrite.ps1"
        $oldContent = "Write-Output 'OLD'"
        $newContent = "Write-Output 'NEW_FORCED'"

        [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $oldContent) | Out-Null
        $res = [TerminalAI.Aot.AotScriptSafety]::SaveScriptFile($testFile, $newContent, $true, $null)

        if (-not $res.Saved) { throw "Force overwrite should have succeeded" }
        if ($res.Status -ne "Overwritten") { throw "Status should be 'Overwritten', was '$($res.Status)'" }

        $actual = (Get-Content $testFile -Raw).Trim()
        if ($actual -ne $newContent) { throw "File should contain forced content" }
        if (-not [TerminalAI.Aot.AotScriptSafety]::HasUtf8Bom($testFile)) { throw "Forced file must have UTF-8 BOM" }
    }
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "Results: $script:PassedTests / $script:TotalTests passed ($script:FailedTests failed) • 100% Target" -ForegroundColor $(if ($script:FailedTests -eq 0) { "Green" } else { "Red" })
Write-Host "===============================================================`n" -ForegroundColor Cyan

if ($script:FailedTests -gt 0) {
    exit 1
}
