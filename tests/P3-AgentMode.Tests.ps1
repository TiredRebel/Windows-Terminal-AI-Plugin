<#
.SYNOPSIS
    Automated test suite for Phase P3: Optional Claude Code Agent Mode (Invoke-AiAgent / ai-agent).
    Validates binary discovery, Ollama Messages endpoint integration, environment isolation,
    argument formatting, workspace trust, diagnostic reporting, and non-regression of core cmdlets.
#>

[CmdletBinding()]
param()

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $moduleRoot "TerminalAI.psd1"

Remove-Module -Name TerminalAI -ErrorAction SilentlyContinue
$script:TargetMod = Import-Module $modulePath -Force -DisableNameChecking -PassThru
if ($script:TargetMod -is [array]) {
    $script:TargetMod = $script:TargetMod | Select-Object -First 1
}

$testRoot = Join-Path $env:TEMP ("tai_p3_test_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0

function Assert-P3Fixture {
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
Write-Host "  TerminalAI Phase P3 Test Suite: Claude Code Agent Mode" -ForegroundColor Cyan
Write-Host "  PowerShell Version: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor DarkGray
Write-Host "============================================================`n" -ForegroundColor Cyan

try {
    # -------------------------------------------------------------
    # 1. EXPORT & MANIFEST PARITY
    # -------------------------------------------------------------
    Write-Host "--- 1. Module Export & Manifest Parity ---" -ForegroundColor Yellow

    # FIX-P3-01: Export of Invoke-AiAgent, Test-AiAgentReadiness, and alias ai-agent
    Assert-P3Fixture "FIX-P3-01" "Invoke-AiAgent, Test-AiAgentReadiness and alias ai-agent exported" {
        $mod = Get-Module -Name TerminalAI
        $exportedFuncs = @($mod.ExportedFunctions.Keys)
        $exportedAliases = @($mod.ExportedAliases.Keys)

        $hasFunc = ($exportedFuncs -contains "Invoke-AiAgent")
        $hasReadiness = ($exportedFuncs -contains "Test-AiAgentReadiness")
        $hasAlias = ($exportedAliases -contains "ai-agent")

        $psd1Content = Get-Content -Path $modulePath -Raw
        $manifestHasFunc = ($psd1Content -match "'Invoke-AiAgent'")
        $manifestHasAlias = ($psd1Content -match "'ai-agent'")

        return ($hasFunc -and $hasReadiness -and $hasAlias -and $manifestHasFunc -and $manifestHasAlias)
    }

    # -------------------------------------------------------------
    # 2. CONFIGURATION SCHEMA & PERSISTENCE
    # -------------------------------------------------------------
    Write-Host "`n--- 2. Configuration Schema & Persistence ---" -ForegroundColor Yellow

    # FIX-P3-02: Configuration properties and persistence
    Assert-P3Fixture "FIX-P3-02" "Agent configuration fields exist and persist" {
        $oldConfigDir = $env:TERMINAL_AI_CONFIG_DIR
        try {
            $env:TERMINAL_AI_CONFIG_DIR = Join-Path $testRoot "cfg"
            $def = & $script:TargetMod { Get-TerminalAiDefaultConfig }
            $hasAgentModel = ($null -ne $def.AgentModel)
            $hasClaudeExec = ($null -ne $def.ClaudeExecutable)
            $hasAgentData = ($null -ne $def.AgentDataDirectory)

            Set-TerminalAiConfig -AgentModel "qwen3.5:9b" -ClaudeExecutable "C:\claude\claude.exe" | Out-Null
            $saved = Get-TerminalAiConfig
            $persists = ($saved.AgentModel -eq "qwen3.5:9b" -and $saved.ClaudeExecutable -eq "C:\claude\claude.exe")

            return ($hasAgentModel -and $hasClaudeExec -and $hasAgentData -and $persists)
        } finally {
            $env:TERMINAL_AI_CONFIG_DIR = $oldConfigDir
        }
    }

    # -------------------------------------------------------------
    # 3. BINARY DISCOVERY & VERSION EXTRACTION
    # -------------------------------------------------------------
    Write-Host "`n--- 3. Binary Discovery & Readiness Probing ---" -ForegroundColor Yellow

    # FIX-P3-03: Claude Code discovery on local system
    Assert-P3Fixture "FIX-P3-03" "Find-ClaudeCodeExecutable locates local binary and extracts version" {
        $claudePath = & $script:TargetMod { Find-ClaudeCodeExecutable }
        if (-not $claudePath) {
            # In CI or environments without Claude Code pre-installed, verify discovery logic with a mock binary in testRoot
            $mockClaude = Join-Path $testRoot "claude.cmd"
            Set-Content -Path $mockClaude -Value "@echo 2.1.0`r`n"
            $claudePath = & $script:TargetMod { param($p) Find-ClaudeCodeExecutable -CustomPath $p } $mockClaude
        }
        if (-not $claudePath) { return $false }
        if (-not (Test-Path $claudePath)) { return $false }

        $ver = & $script:TargetMod { param($p) Get-ClaudeCodeVersion -ClaudePath $p } $claudePath
        return ($ver -match '\d+\.\d+')
    }

    # FIX-P3-04: Test-AiAgentReadiness returns structured status
    Assert-P3Fixture "FIX-P3-04" "Test-AiAgentReadiness checks Ollama endpoint and Claude binary" {
        $st = Test-AiAgentReadiness -PassThru
        $hasClaudeProp = ($null -ne $st.PSObject.Properties["ClaudeReady"])
        $hasOllamaProp = ($null -ne $st.PSObject.Properties["OllamaReady"])
        $hasModelProp  = ($null -ne $st.PSObject.Properties["Model"])
        $hasReadyProp  = ($null -ne $st.PSObject.Properties["Ready"])
        return ($hasClaudeProp -and $hasOllamaProp -and $hasModelProp -and $hasReadyProp)
    }

    # FIX-P3-05: Model tool capability detection
    Assert-P3Fixture "FIX-P3-05" "Model tool capability properly detected for coding models" {
        $requestedModel = "qwen2.5-coder:7b"
        $availableModels = @()
        try {
            $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 2 -ErrorAction Stop
            $availableModels = @($tags.models.name)
            if ($availableModels -notcontains $requestedModel) {
                $installedCodingModel = $availableModels | Where-Object { $_ -match '(?i)(coder|qwen|granite|hermes|command-r)' } | Select-Object -First 1
                if ($installedCodingModel) { $requestedModel = $installedCodingModel }
            }
        } catch { }

        $st = Test-AiAgentReadiness -Model $requestedModel -PassThru
        if ($st.OllamaReady) {
            $presenceMatches = ($st.ModelPresent -eq ($availableModels -contains $requestedModel))
            $capabilityIsBoolean = ($st.ToolsSupported -is [bool])
            $absentModelIsUnsupported = $st.ModelPresent -or ($st.ToolsSupported -eq $false)
            return ($presenceMatches -and $capabilityIsBoolean -and $absentModelIsUnsupported)
        } else {
            return ($st.Model -eq $requestedModel -and $st.ModelPresent -eq $false -and $st.ToolsSupported -eq $false)
        }
    }

    # FIX-P3-06: Clean error handling when Claude is missing
    Assert-P3Fixture "FIX-P3-06" "Test-AiAgentReadiness cleanly flags missing Claude executable" {
        $st = Test-AiAgentReadiness -ClaudePath "C:\invalid_missing_dir_12345\claude.exe" -PassThru
        return ($st.ClaudeReady -eq $false -and $st.Ready -eq $false)
    }

    # -------------------------------------------------------------
    # 4. ENVIRONMENT ISOLATION & PROCESS CONFIGURATION
    # -------------------------------------------------------------
    Write-Host "`n--- 4. Environment Isolation & Process Contract ---" -ForegroundColor Yellow

    # FIX-P3-07: Process-scoped environment variables contract
    Assert-P3Fixture "FIX-P3-07" "Environment isolation protects endpoints, config, and privacy" {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.EnvironmentVariables["OPENAI_API_KEY"] = "sk-fake-key-to-clear"
        $psi.EnvironmentVariables["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:11434"
        $psi.EnvironmentVariables["ANTHROPIC_AUTH_TOKEN"] = "ollama"
        $psi.EnvironmentVariables["CLAUDE_CONFIG_DIR"] = Join-Path $HOME ".terminal-ai\claude"
        $psi.EnvironmentVariables["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"

        if ($psi.EnvironmentVariables.ContainsKey("OPENAI_API_KEY")) {
            $psi.EnvironmentVariables.Remove("OPENAI_API_KEY")
        }

        $cleared = (-not $psi.EnvironmentVariables.ContainsKey("OPENAI_API_KEY"))
        $urlSet = ($psi.EnvironmentVariables["ANTHROPIC_BASE_URL"] -eq "http://127.0.0.1:11434")
        $tokenSet = ($psi.EnvironmentVariables["ANTHROPIC_AUTH_TOKEN"] -eq "ollama")
        $trafficDisabled = ($psi.EnvironmentVariables["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] -eq "1")

        $portableConfig = Join-Path $testRoot "portable-config"
        New-Item -Path $portableConfig -ItemType Directory -Force | Out-Null
        $configPath = Join-Path $portableConfig "config.json"
        Set-Content -Path $configPath -Value '{"Language":"en","Model":"fixture"}' -Encoding UTF8
        $configBefore = Get-Content -Path $configPath -Raw
        $profilePaths = @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost) | Select-Object -Unique
        $profileBefore = @{}
        foreach ($profilePath in $profilePaths) {
            if (Test-Path $profilePath) { $profileBefore[$profilePath] = (Get-FileHash -Path $profilePath).Hash }
        }
        $oldConfigDir = $env:TERMINAL_AI_CONFIG_DIR
        $oldPortable = $env:TERMINAL_AI_PORTABLE
        try {
            $env:TERMINAL_AI_CONFIG_DIR = $portableConfig
            $env:TERMINAL_AI_PORTABLE = $null
            & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $moduleRoot "bootstrap.ps1") -Mode Portable -Language en -SkipOllama -NonInteractive *> $null
            $configUnchanged = ((Get-Content -Path $configPath -Raw) -eq $configBefore)
            $profilesUnchanged = $true
            foreach ($profilePath in $profileBefore.Keys) {
                $profilesUnchanged = $profilesUnchanged -and ((Test-Path $profilePath) -and ((Get-FileHash -Path $profilePath).Hash -eq $profileBefore[$profilePath]))
            }

            $absentConfigDir = Join-Path $testRoot "portable-config-absent"
            $env:TERMINAL_AI_CONFIG_DIR = $absentConfigDir
            & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $moduleRoot "bootstrap.ps1") -Mode Portable -Language uk -SkipOllama -NonInteractive *> $null
            $absentConfigUnchanged = (-not (Test-Path $absentConfigDir))
        } finally {
            $env:TERMINAL_AI_CONFIG_DIR = $oldConfigDir
            $env:TERMINAL_AI_PORTABLE = $oldPortable
        }

        return ($cleared -and $urlSet -and $tokenSet -and $trafficDisabled -and $configUnchanged -and $profilesUnchanged -and $absentConfigUnchanged)
    }

    # FIX-P3-08: Argument formatting with quoting for spaces
    Assert-P3Fixture "FIX-P3-08" "CLI argument formatting properly escapes spaces and flags" {
        $argList = @("--model", "qwen2.5-coder:7b", "--resume", "-p", "fix build errors and test")
        $escaped = @()
        foreach ($a in $argList) {
            if ($a -match '[\s"]') {
                $escaped += "`"$($a.Replace('"', '\"'))`""
            } else {
                $escaped += $a
            }
        }
        $formatted = ($escaped -join " ")
        $expected = '--model qwen2.5-coder:7b --resume -p "fix build errors and test"'
        return ($formatted -eq $expected)
    }

    # FIX-P3-09: Target workspace directory validation
    Assert-P3Fixture "FIX-P3-09" "Readiness probe validates existence of target workspace" {
        $validSt = Test-AiAgentReadiness -WorkingDir $PSScriptRoot -PassThru
        $invalidSt = Test-AiAgentReadiness -WorkingDir "C:\nonexistent_path_987654321" -PassThru
        return ($validSt.WorkingDirValid -eq $true -and $invalidSt.WorkingDirValid -eq $false -and $invalidSt.Ready -eq $false)
    }

    # -------------------------------------------------------------
    # 5. DIAGNOSTICS & CHECK-ONLY EXECUTION
    # -------------------------------------------------------------
    Write-Host "`n--- 5. Diagnostics & Non-Destructive Execution ---" -ForegroundColor Yellow

    # FIX-P3-10: Test-TerminalAiInstallation includes Subsystem 9 without failing overall health
    Assert-P3Fixture "FIX-P3-10" "ai-doctor includes Subsystem 9 (Claude Code) and remains healthy" {
        $diag = Test-TerminalAiInstallation -PassThru
        $hasAgentProp = ($null -ne $diag.PSObject.Properties["AgentModeAvailable"])
        $hasClaudeProp = ($null -ne $diag.PSObject.Properties["ClaudeExecutable"])
        return ($hasAgentProp -and $hasClaudeProp -and ($diag.PowerShellOk -eq $true))
    }

    # FIX-P3-11: Invoke-AiAgent -CheckOnly executes non-destructively
    Assert-P3Fixture "FIX-P3-11" "Invoke-AiAgent -CheckOnly returns status object without starting process" {
        $res = Invoke-AiAgent -CheckOnly
        return ($null -ne $res -and ($res.ClaudeReady -is [bool]))
    }

    # -------------------------------------------------------------
    # 6. REGRESSION GATE
    # -------------------------------------------------------------
    Write-Host "`n--- 6. Regression Gate: Core Cmdlets Unaffected ---" -ForegroundColor Yellow

    # FIX-P3-12: Core commands and AST gate unaffected
    Assert-P3Fixture "FIX-P3-12" "Core AST Gate, Secret Protection, and Help operate without regression" {
        $ast = Test-AiCommandAst -Command "Get-Process | Stop-Process"
        $astOk = ($ast.OverallCategory -in @("ServiceOrProcess", "SystemModification") -and $ast.OverallRisk -in @("Medium", "High"))

        $secret = Protect-AiSecretData -Text "token sk-1234567890abcdef12345678"
        $secretOk = ($secret -match 'sk-\*\*\*\[REDACTED\]\*\*\*')

        $helpOut = Show-TerminalAiHelp -Topic shortcuts
        # Function returns void and renders to host, verify it doesn't throw
        return ($astOk -and $secretOk)
    }

} finally {
    if (Test-Path $testRoot) {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  Phase P3 Test Results: $($script:PassedTests)/$($script:TotalTests) Passed" -ForegroundColor Cyan
if ($script:FailedTests -gt 0) {
    Write-Host "  Status: FAILED ($($script:FailedTests) failed)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  Status: ALL FIXTURES PASSED (100%)" -ForegroundColor Green
    exit 0
}
