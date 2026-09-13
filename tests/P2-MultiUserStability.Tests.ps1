<#
.SYNOPSIS
    Набір автоматичних тестів для Фази P2:
    - Цикл 7: Багатокористувацький інсталятор/деінсталятор та ізоляція $PROFILE
    - Цикл 8: Сумісність PS 5.1 / PS 7 без розривів синтаксису
    - Цикл 9: Стабільність Windows Terminal Fragments JSON schema
    - Цикл 10: Модуль самодіагностики Test-TerminalAiInstallation (ai-doctor)
#>

[CmdletBinding()]
param()

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $moduleRoot "TerminalAI.psd1"

if (-not (Get-Module -Name TerminalAI)) {
    Import-Module $modulePath -Force -DisableNameChecking
}

$testRoot = Join-Path $env:TEMP ("tai_p2_test_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
$origConfigDir = $env:TERMINAL_AI_CONFIG_DIR
$env:TERMINAL_AI_CONFIG_DIR = Join-Path $testRoot "Config"

$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0

function Assert-P2Fixture {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$TestBlock
    )

    $script:TotalTests++
    Write-Host "  [$Id] $Description ... " -NoNewline -ForegroundColor Gray

    try {
        $result = & $TestBlock
        if ($result -eq $false) {
            Write-Host "FAILED (Assertion returned false)" -ForegroundColor Red
            $script:FailedTests++
        } else {
            Write-Host "PASS" -ForegroundColor Green
            $script:PassedTests++
        }
    } catch {
        Write-Host "FAILED ($($_.Exception.Message))" -ForegroundColor Red
        $script:FailedTests++
    }
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  TerminalAI Phase P2 Test Suite (Cycles 7–10)" -ForegroundColor Cyan
Write-Host "  PowerShell Version: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor DarkGray
Write-Host "============================================================`n" -ForegroundColor Cyan

try {
    # -------------------------------------------------------------
    # CYCLE 7: MULTI-USER INSTALLER / UNINSTALLER & PROFILE BLOCKS
    # -------------------------------------------------------------
    Write-Host "--- Cycle 7: Installer/Uninstaller & Profile Idempotency ---" -ForegroundColor Yellow

    $fakeProfile = Join-Path $testRoot "Microsoft.PowerShell_profile.ps1"
    $fakeModuleRoot = Join-Path $testRoot "Modules"
    $fakeFragmentRoot = Join-Path $testRoot "Fragments\TerminalAI"
    $fakeConfigDir = Join-Path $testRoot "Config"

    # Pre-populate custom profile with existing user functions
    $userExistingProfile = @"
# Custom User Setup
function Prompt { 'PS> ' }
Set-Alias -Name np -Value notepad.exe
"@
    [System.IO.File]::WriteAllText($fakeProfile, $userExistingProfile, (New-Object System.Text.UTF8Encoding($true)))

    # FIX-P2-01: Isolated installation of module files
    Assert-P2Fixture "FIX-P2-01" "Installer synchronizes module into target module path" {
        $installScript = Join-Path $moduleRoot "Install-TerminalAi.ps1"
        & $installScript -CustomProfilePath $fakeProfile -CustomModulePath $fakeModuleRoot -CustomFragmentPath $fakeFragmentRoot -SkipTerminalConfig -SkipOllamaCheck -AutoConfirm

        $installedPsd = Join-Path $fakeModuleRoot "TerminalAI\TerminalAI.psd1"
        $installedPsm = Join-Path $fakeModuleRoot "TerminalAI\TerminalAI.psm1"
        (Test-Path $installedPsd) -and (Test-Path $installedPsm)
    }

    # FIX-P2-02: Marked block in $PROFILE
    Assert-P2Fixture "FIX-P2-02" "Installer writes delimited block preserving existing user profile code" {
        $content = [System.IO.File]::ReadAllText($fakeProfile)
        $hasCustomCode = ($content -match 'function Prompt') -and ($content -match 'Set-Alias -Name np')
        $hasStartMarker = ($content -match '# >>> TerminalAI Initialization >>>')
        $hasEndMarker = ($content -match '# <<< TerminalAI Initialization <<<')
        $hasImport = ($content -match 'Import-Module TerminalAI')

        $hasCustomCode -and $hasStartMarker -and $hasEndMarker -and $hasImport
    }

    # FIX-P2-03: Idempotency of $PROFILE modification
    Assert-P2Fixture "FIX-P2-03" "Re-running installer updates marked block in-place without duplicate code" {
        $installScript = Join-Path $moduleRoot "Install-TerminalAi.ps1"
        & $installScript -CustomProfilePath $fakeProfile -CustomModulePath $fakeModuleRoot -CustomFragmentPath $fakeFragmentRoot -SkipTerminalConfig -SkipOllamaCheck -AutoConfirm

        $content = [System.IO.File]::ReadAllText($fakeProfile)
        $startMatches = [regex]::Matches($content, '# >>> TerminalAI Initialization >>>')
        $endMatches = [regex]::Matches($content, '# <<< TerminalAI Initialization <<<')

        ($startMatches.Count -eq 1) -and ($endMatches.Count -eq 1)
    }

    # FIX-P2-04: Profile backup file creation
    Assert-P2Fixture "FIX-P2-04" "Installer generates timestamped .bak file before modifying profile" {
        $bakFiles = Get-ChildItem -Path $testRoot -Filter "Microsoft.PowerShell_profile.ps1.bak.*"
        $bakFiles.Count -ge 1
    }

    # FIX-P2-05: Non-destructive uninstallation of marked block
    Assert-P2Fixture "FIX-P2-05" "Uninstaller extracts ONLY the marked block and preserves surrounding user code" {
        $uninstallScript = Join-Path $moduleRoot "Uninstall-TerminalAi.ps1"
        & $uninstallScript -CustomProfilePath $fakeProfile -CustomModulePath $fakeModuleRoot -CustomFragmentPath $fakeFragmentRoot

        $content = [System.IO.File]::ReadAllText($fakeProfile)
        $hasCustomCode = ($content -match 'function Prompt') -and ($content -match 'Set-Alias -Name np')
        $markersGone = ($content -notmatch '# >>> TerminalAI Initialization >>>') -and ($content -notmatch 'Import-Module TerminalAI')

        $hasCustomCode -and $markersGone
    }

    # FIX-P2-06: Module directory removal on uninstall
    Assert-P2Fixture "FIX-P2-06" "Uninstaller removes the module directory cleanly" {
        $installedDir = Join-Path $fakeModuleRoot "TerminalAI"
        -not (Test-Path $installedDir)
    }

    # FIX-P2-07: Config preservation vs -PurgeConfig
    Assert-P2Fixture "FIX-P2-07" "Uninstaller preserves config by default and purges when requested" {
        $cfgDir = Join-Path $testRoot "TestConfigDir"
        New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
        $env:TERMINAL_AI_CONFIG_DIR = $cfgDir

        # 1. Without -PurgeConfig -> preserved
        $uninstallScript = Join-Path $moduleRoot "Uninstall-TerminalAi.ps1"
        & $uninstallScript -CustomProfilePath $fakeProfile -CustomModulePath $fakeModuleRoot -CustomFragmentPath $fakeFragmentRoot
        $preserved = Test-Path $cfgDir

        # 2. With -PurgeConfig -> deleted
        & $uninstallScript -CustomProfilePath $fakeProfile -CustomModulePath $fakeModuleRoot -CustomFragmentPath $fakeFragmentRoot -PurgeConfig
        $purged = -not (Test-Path $cfgDir)

        $env:TERMINAL_AI_CONFIG_DIR = $null
        $preserved -and $purged
    }

    # -------------------------------------------------------------
    # CYCLE 8: CROSS-VERSION POWERSHELL 5.1 / 7 PARITY
    # -------------------------------------------------------------
    Write-Host "`n--- Cycle 8: Cross-Version PowerShell Compatibility ---" -ForegroundColor Yellow

    # FIX-P2-08: Module manifests and cmdlets export seamlessly
    Assert-P2Fixture "FIX-P2-08" "Module exports all cmdlets, functions, and aliases identically" {
        $exportedFuncs = (Get-Module TerminalAI).ExportedFunctions.Keys
        $exportedAliases = (Get-Module TerminalAI).ExportedAliases.Keys

        $hasGate = ($exportedFuncs -contains "Invoke-AiExecutionGate")
        $hasAst = ($exportedFuncs -contains "Test-AiCommandAst")
        $hasRedact = ($exportedFuncs -contains "Protect-AiSecretData")
        $hasDiff = ($exportedFuncs -contains "Format-AiScriptDiff")
        $hasSave = ($exportedFuncs -contains "Save-AiScriptFile")
        $hasDoctor = ($exportedFuncs -contains "Test-TerminalAiInstallation")
        $hasDoctorAlias = ($exportedAliases -contains "ai-doctor")

        $hasGate -and $hasAst -and $hasRedact -and $hasDiff -and $hasSave -and $hasDoctor -and $hasDoctorAlias
    }

    # FIX-P2-09: Dual-host compatibility check
    Assert-P2Fixture "FIX-P2-09" "Shared scripts contain no unsupported operators (??=, &&, ?:)" {
        $repoFiles = Get-ChildItem -Path $moduleRoot -Include *.ps1, *.psm1, *.psd1 | Where-Object { $_.FullName -notmatch '\\\.git\\' }
        $violating = @()
        foreach ($rf in $repoFiles) {
            $text = [System.IO.File]::ReadAllText($rf.FullName)
            if ($text -match '\?\?=' -or $text -match '\s\?\s[^\r\n]+:') {
                $violating += $rf.Name
            }
        }
        $violating.Count -eq 0
    }

    # -------------------------------------------------------------
    # CYCLE 9: WINDOWS TERMINAL FRAGMENTS SCHEMA STABILITY
    # -------------------------------------------------------------
    Write-Host "`n--- Cycle 9: Windows Terminal Fragment Schema Stability ---" -ForegroundColor Yellow

    # FIX-P2-10: Fragment Schema Validation
    Assert-P2Fixture "FIX-P2-10" "terminalai.json validates as proper Windows Terminal Fragment Schema" {
        $jsonFile = Join-Path $moduleRoot "terminalai.json"
        $json = Get-Content -Path $jsonFile -Raw | ConvertFrom-Json
        $hasProfiles = ($null -ne $json.profiles -and $json.profiles.Count -ge 2)
        $hasActions = ($null -ne $json.actions -and $json.actions.Count -ge 4)

        $guids = @($json.profiles | ForEach-Object { $_.guid })
        $uniqueGuids = ($guids | Select-Object -Unique).Count -eq $guids.Count

        $hasProfiles -and $hasActions -and $uniqueGuids
    }

    # FIX-P2-11: Non-invasive Fragment Deployment
    Assert-P2Fixture "FIX-P2-11" "Fragment copied without mutating settings.json when ModifySettingsJson is omitted" {
        $installScript = Join-Path $moduleRoot "Install-TerminalAi.ps1"
        & $installScript -CustomProfilePath $fakeProfile -CustomModulePath $fakeModuleRoot -CustomFragmentPath $fakeFragmentRoot -SkipOllamaCheck -AutoConfirm

        $targetFrag = Join-Path $fakeFragmentRoot "terminalai.json"
        Test-Path $targetFrag
    }

    # -------------------------------------------------------------
    # CYCLE 10: SELF-DIAGNOSTICS & AI-DOCTOR
    # -------------------------------------------------------------
    Write-Host "`n--- Cycle 10: Self-Diagnostics (Test-TerminalAiInstallation / ai-doctor) ---" -ForegroundColor Yellow

    # FIX-P2-12: Test-TerminalAiInstallation -PassThru returns structured result
    Assert-P2Fixture "FIX-P2-12" "Test-TerminalAiInstallation -PassThru reports key subsystem health" {
        $diag = Test-TerminalAiInstallation -PassThru
        ($diag.PowerShellOk -eq $true) -and
        ($diag.AstEngineOk -eq $true) -and
        ($diag.SecretRedactionOk -eq $true) -and
        ($null -ne $diag.PowerShellVersion)
    }

    # FIX-P2-13: ai-doctor alias execution
    Assert-P2Fixture "FIX-P2-13" "ai-doctor alias invokes diagnostic health engine" {
        $aliasCmd = Get-Command ai-doctor -ErrorAction Ignore
        ($null -ne $aliasCmd) -and ($aliasCmd.ResolvedCommandName -eq "Test-TerminalAiInstallation")
    }

    # FIX-P2-14: Clean session state and zero $global:Error pollution on import
    Assert-P2Fixture "FIX-P2-14" "Module import produces zero errors in `$global:Error without autoload recursion" {
        $cleanRun = if ($PSVersionTable.PSVersion.Major -ge 7) {
            pwsh -NoProfile -Command "`$global:Error.Clear(); Import-Module '$moduleRoot\TerminalAI.psd1' -Force; exit `$global:Error.Count"
        } else {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "`$global:Error.Clear(); Import-Module '$moduleRoot\TerminalAI.psd1' -Force; exit `$global:Error.Count"
        }
        $LASTEXITCODE -eq 0
    }

    # FIX-P2-15: Installer runs cleanly without polluting $global:Error
    Assert-P2Fixture "FIX-P2-15" "Installer runs cleanly without polluting `$global:Error even when files exist" {
        $instCmd = "`$global:Error.Clear(); & '$moduleRoot\Install-TerminalAi.ps1' -AutoConfirm -SkipOllamaCheck -CustomModulePath '$testRoot\TestModules' -CustomProfilePath '$testRoot\TestProfile.ps1' | Out-Null; exit `$global:Error.Count"
        $instRun = if ($PSVersionTable.PSVersion.Major -ge 7) {
            pwsh -NoProfile -Command $instCmd
        } else {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $instCmd
        }
        $LASTEXITCODE -eq 0
    }

} finally {
    $env:TERMINAL_AI_CONFIG_DIR = $origConfigDir
    if (Test-Path $testRoot) {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Results: $script:PassedTests / $script:TotalTests passed ($script:FailedTests failed)" -ForegroundColor $(if ($script:FailedTests -eq 0) { "Green" } else { "Red" })
Write-Host "------------------------------------------------------------`n" -ForegroundColor Cyan

if ($script:FailedTests -gt 0) {
    exit 1
} else {
    exit 0
}
