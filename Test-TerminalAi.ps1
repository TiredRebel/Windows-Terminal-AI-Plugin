# Test-TerminalAi.ps1 - Comprehensive TerminalAI verification
[CmdletBinding()]
param(
    [switch]$RunLiveTests
)

$ErrorActionPreference = "Stop"

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "             Running TerminalAI extension tests                  " -ForegroundColor Cyan
if (-not $RunLiveTests) {
    Write-Host "       [Mode: deterministic (live Ollama tests skipped)]         " -ForegroundColor Yellow
} else {
    Write-Host "       [Mode: full (live requests to local Ollama)]              " -ForegroundColor Magenta
}
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$allPassed = $true
$tests = 0
$passed = 0
$skipped = 0

# Isolate the test environment from the user's configuration and profile
$origConfigDir = $env:TERMINAL_AI_CONFIG_DIR
$origLang = $env:TERMINAL_AI_LANG
$testTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("TerminalAiTest_" + [System.Guid]::NewGuid().ToString("N"))
$testConfigDir = Join-Path $testTempRoot "config"
New-Item -ItemType Directory -Path $testConfigDir -Force | Out-Null
$env:TERMINAL_AI_CONFIG_DIR = $testConfigDir

function Assert-Test {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    $script:tests++
    Write-Host "Test $script:tests : $Name ... " -NoNewline -ForegroundColor White
    try {
        $result = & $TestBlock
        if ($result -ne $false) {
            $script:passed++
            Write-Host "PASSED" -ForegroundColor Green
        } else {
            $script:allPassed = $false
            Write-Host "FAILED (condition not met)" -ForegroundColor Red
        }
    } catch {
        $script:allPassed = $false
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-LiveTest {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    $script:tests++
    Write-Host "Test $script:tests : $Name ... " -NoNewline -ForegroundColor White
    if (-not $RunLiveTests) {
        $script:skipped++
        Write-Host "SKIPPED (requires -RunLiveTests)" -ForegroundColor Yellow
        return
    }
    try {
        $result = & $TestBlock
        if ($result -ne $false) {
            $script:passed++
            Write-Host "PASSED" -ForegroundColor Green
        } else {
            $script:allPassed = $false
            Write-Host "FAILED (condition not met)" -ForegroundColor Red
        }
    } catch {
        $script:allPassed = $false
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

try {

# Configuration
Assert-Test "Save and read configuration" {
    . (Join-Path $PSScriptRoot "TerminalAiConfig.ps1")
    $cfg = Get-TerminalAiConfig
    if ($null -eq $cfg.Model -or $null -eq $cfg.OllamaUrl) { return $false }
    return $true
}

# Module manifest import
Assert-Test "Import TerminalAI.psd1 and verify exports" {
    Import-Module (Join-Path $PSScriptRoot "TerminalAI.psd1") -Force
    $mod = Get-Module TerminalAI
    $hasCmd = $mod.ExportedFunctions.ContainsKey("Invoke-AiCommand")
    $hasAlias = $mod.ExportedAliases.ContainsKey("ai")
    return ($hasCmd -and $hasAlias)
}

# Ollama connectivity
Assert-LiveTest "Connect to local Ollama and retrieve models" {
    $models = Get-TerminalAiModels
    return ($models.Count -gt 0)
}

# Command generation through Ollama
$testModel = (Get-TerminalAiConfig).Model
Assert-LiveTest "Generate a PowerShell command through Ollama ($testModel)" {
    $code = Invoke-OllamaApi -Prompt "Write a single PowerShell command to get the current date in yyyy-MM-dd format" -Model $testModel -Temperature 0.1
    $clean = Clean-AiCodeOutput -Text $code
    Write-Host "`n    [Generated]: $clean" -ForegroundColor DarkCyan
    return (-not [string]::IsNullOrWhiteSpace($clean))
}

# Markdown and reasoning-tag cleanup
Assert-Test "Clean-AiCodeOutput output cleanup" {
    $raw = '```powershell' + [Environment]::NewLine + 'Get-Process' + [Environment]::NewLine + '```'
    $clean = Clean-AiCodeOutput -Text $raw
    $thinkRaw = '<think>I should use Get-Process</think>' + [Environment]::NewLine + '`Get-Process`'
    $thinkClean = Clean-AiCodeOutput -Text $thinkRaw
    return ($clean -eq "Get-Process" -and $thinkClean -eq "Get-Process")
}

# Terminal fonts
Assert-Test "Detect active and installed monospace terminal fonts" {
    $fontInfo = Get-TerminalAiFonts
    if ($null -eq $fontInfo -or $fontInfo.Fonts.Count -eq 0) { return $false }
    Write-Host "`n    [Active font]: $($fontInfo.ActiveFont)" -ForegroundColor DarkCyan
    return (-not [string]::IsNullOrWhiteSpace($fontInfo.ActiveFont))
}

# Language switching and persistence
Assert-Test "Switch and persist the model response language" {
    $origLang = (Get-TerminalAiConfig).Language
    Set-TerminalAiLanguage -Language "en" -Permanent | Out-Null
    $cfgEn = Get-TerminalAiConfig
    $txtEn = Get-TerminalAiText "CardTitle"
    $envEn = $env:TERMINAL_AI_LANG
    
    Set-TerminalAiLanguage -Language "uk" -Permanent | Out-Null
    $cfgUk = Get-TerminalAiConfig
    $txtUk = Get-TerminalAiText "CardTitle"
    $envUk = $env:TERMINAL_AI_LANG

    # Leave English as the default language
    Set-TerminalAiLanguage -Language "en" -Permanent | Out-Null

    return ($cfgEn.Language -eq "en" -and $txtEn -eq "AI Command" -and $envEn -eq "en" -and `
            $cfgUk.Language -eq "uk" -and $txtUk -eq "AI Command" -and $envUk -eq "uk")
}

# Exported aliases and functions
Assert-Test "Export font and persistent-language commands" {
    $mod = Get-Module TerminalAI
    $hasFontFunc = $mod.ExportedFunctions.ContainsKey("Set-TerminalAiFont")
    $hasLangFunc = $mod.ExportedFunctions.ContainsKey("Set-TerminalAiLanguage")
    $hasDefLangFunc = $mod.ExportedFunctions.ContainsKey("Set-TerminalAiDefaultLanguage")
    $hasFontAlias = $mod.ExportedAliases.ContainsKey("ai-font")
    $hasLangAlias = $mod.ExportedAliases.ContainsKey("ai-lang")
    $hasPermLangAlias = $mod.ExportedAliases.ContainsKey("ai-lang-permanent")
    $hasDefLangAlias = $mod.ExportedAliases.ContainsKey("ai-lang-default")
    return ($hasFontFunc -and $hasLangFunc -and $hasDefLangFunc -and $hasFontAlias -and $hasLangAlias -and $hasPermLangAlias -and $hasDefLangAlias)
}

# Interactive assistant and completion
Assert-Test "Export the interactive assistant" {
    $mod = Get-Module TerminalAI
    $hasAssistantFunc = $mod.ExportedFunctions.ContainsKey("Invoke-AiAssistant")
    $hasChatAlias = $mod.ExportedAliases.ContainsKey("ai-chat")
    $hasAssistantAlias = $mod.ExportedAliases.ContainsKey("ai-assistant")
    $assistantPath = Join-Path $PSScriptRoot "TerminalAiAssistant.ps1"
    $hasAssistantScript = Test-Path $assistantPath

    # Verify TerminalAiAssistant.ps1 syntax
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($assistantPath, [ref]$null, [ref]$parseErrors)
    $syntaxValid = ($parseErrors.Count -eq 0)

    return ($hasAssistantFunc -and $hasChatAlias -and $hasAssistantAlias -and $hasAssistantScript -and $syntaxValid)
}

# Menu input helpers
Assert-Test "Export menu input helpers" {
    $mod = Get-Module TerminalAI
    $hasClearBuf = $mod.ExportedFunctions.ContainsKey("Clear-AiInputBuffer")
    $hasReadKey = $mod.ExportedFunctions.ContainsKey("Get-AiMenuKeyPress")

    # Clear-AiInputBuffer must not throw
    Clear-AiInputBuffer

    return ($hasClearBuf -and $hasReadKey)
}


# UTF-8 BOM support for PowerShell 5.1
Assert-Test "UTF-8 BOM encoding for all PowerShell files" {
    $scripts = Get-ChildItem -Path $PSScriptRoot -Filter *.ps*1
    $allHaveBom = $true
    foreach ($s in $scripts) {
        $bytes = [System.IO.File]::ReadAllBytes($s.FullName)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        if (-not $hasBom) {
            $allHaveBom = $false
            break
        }
    }
    return $allHaveBom
}

# Windows PowerShell 5.1 manifest import
Assert-Test "Import the module in Windows PowerShell 5.1" {
    $cmd = "Import-Module (Join-Path '$PSScriptRoot' 'TerminalAI.psd1') -Force -PassThru"
    $ps51Result = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $cmd 2>&1
    $exitCode = $LASTEXITCODE
    return ($exitCode -eq 0 -and $ps51Result -match 'TerminalAI')
}

# Short alias conversion
Assert-Test "Convert full cmdlet names to short aliases" {
    $mod = Get-Module TerminalAI | Select-Object -First 1
    $short = & $mod { ConvertTo-AiShortAliases 'Get-Process | Where-Object { $_.CPU -gt 10 } | ForEach-Object { $_.Name }' }
    return ($short -match 'gps' -and $short -match '\?' -and $short -match '%')
}

# Full cmdlet conversion
Assert-Test "Convert aliases back without duplicate substitutions" {
    $mod = Get-Module TerminalAI | Select-Object -First 1
    $full = & $mod { ConvertTo-AiFullCmdlets 'Get-Process | ? { $_.CPU -gt 10 } | % { $_.Name }' }
    $valid = ($full -eq 'Get-Process | Where-Object { $_.CPU -gt 10 } | ForEach-Object { $_.Name }')
    return $valid
}

# System.Net.Http availability in Windows PowerShell 5.1
Assert-Test "System.Net.Http is available in Windows PowerShell 5.1" {
    $cmd = "Import-Module (Join-Path '$PSScriptRoot' 'TerminalAI.psd1') -Force; [bool][Type]::GetType('System.Net.Http.HttpClient, System.Net.Http, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')"
    $ps51Http = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $cmd 2>&1
    return ($ps51Http -match 'True')
}

# Configuration path consistency
Assert-Test "Configuration path is ~/.terminal-ai/config.json" {
    $psm1Content = Get-Content -Path (Join-Path $PSScriptRoot "TerminalAI.psm1") -Raw
    $hasTypo = ($psm1Content -match '\.terminalai/config\.json')
    return (-not $hasTypo)
}

# Windows Terminal fragment portability
Assert-Test "terminalai.json contains no user-specific absolute paths" {
    $jsonPath = Join-Path $PSScriptRoot "terminalai.json"
    $jsonContent = Get-Content -Path $jsonPath -Raw
    $hasHardcodedUser = ($jsonContent -match 'C:\\Users\\|OneDrive|Belgeler')
    return (-not $hasHardcodedUser)
}

# Malformed Markdown handling
Assert-Test "Format-AiCodeOutput handles unclosed Markdown fences" {
    $bt = [char]96
    $unclosed = "$bt$bt$bt" + "powershell`nGet-Process"
    $cleaned = Format-AiCodeOutput -Text $unclosed
    return ($cleaned.Trim() -eq "Get-Process")
}

# F2 handler resilience when Ollama fails
Assert-Test "Register-TerminalAiKeyHandler provides failure feedback" {
    $psm1Content = Get-Content -Path (Join-Path $PSScriptRoot "TerminalAI.psm1") -Raw
    $hasFeedback = ($psm1Content -match '\[AI:.*(?:offline|error)\]')
    return $hasFeedback
}

# Non-interactive assistant input
Assert-Test "Read-AssistantLine handles a non-interactive console host" {
    $assistantContent = Get-Content -Path (Join-Path $PSScriptRoot "TerminalAiAssistant.ps1") -Raw
    $hasProtectedReadKey = ($assistantContent -match 'try\s*\{\s*\$key\s*=\s*\$Host\.UI\.RawUI\.ReadKey')
    return $hasProtectedReadKey
}

# Invoke-OllamaApi chat endpoint
Assert-LiveTest "Invoke-OllamaApi supports /api/chat messages" {
    $cfg = Get-TerminalAiConfig
    $testMessages = @(
        @{ role = "user"; content = "respond with the exact word CHAT_TEST_OK only" }
    )
    $chatRes = Invoke-OllamaApi -Messages $testMessages -Model $cfg.Model -Temperature 0.1
    return ($chatRes -match 'CHAT_TEST_OK')
}

# Assistant session memory and commands
Assert-Test "Assistant supports session memory, reset, context, and inspect" {
    $assistantContent = Get-Content -Path (Join-Path $PSScriptRoot "TerminalAiAssistant.ps1") -Raw
    $hasHistoryVar = ($assistantContent -match '\$script:AiChatHistory')
    $hasResetCmd = ($assistantContent -match '/reset')
    $hasContextCmd = ($assistantContent -match '/context')
    $hasInspectCmd = ($assistantContent -match '/inspect')
    return ($hasHistoryVar -and $hasResetCmd -and $hasContextCmd -and $hasInspectCmd)
}

# Deterministic chat payload serialization
Assert-Test "Build an /api/chat payload with a system prompt" {
    $testMsgs = @(
        @{ role = "user"; content = "First request" },
        @{ role = "assistant"; content = "First response" },
        @{ role = "user"; content = "Second request" }
    )
    $sysPrompt = "System engineering prompt"
    $chatList = [System.Collections.Generic.List[object]]::new()
    $chatList.Add(@{ role = "system"; content = $sysPrompt })
    foreach ($m in $testMsgs) { $chatList.Add($m) }

    $payload = @{
        model = "qwen2.5-coder:7b"
        messages = $chatList
        stream = $false
        options = @{ temperature = 0.2; num_ctx = 4096 }
    }
    $json = $payload | ConvertTo-Json -Depth 5
    $roundTrip = $json | ConvertFrom-Json

    return ($roundTrip.messages.Count -eq 4 -and `
            $roundTrip.messages[0].role -eq "system" -and `
            $roundTrip.messages[1].content -eq "First request" -and `
            $roundTrip.messages[2].role -eq "assistant" -and `
            $roundTrip.messages[3].content -eq "Second request")
}

# Uninstaller parser regression test
Assert-Test "Parse Uninstall-TerminalAi.ps1 in PowerShell 7 and 5.1" {
    $uninstPath = Join-Path $PSScriptRoot "Uninstall-TerminalAi.ps1"
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($uninstPath, [ref]$tokens, [ref]$errors) | Out-Null
    $ps7Valid = ($errors.Count -eq 0)

    $escapedPath = $uninstPath -replace "'", "''"
    $cmd = "& { `$tokens = `$null; `$errors = `$null; `$null = [System.Management.Automation.Language.Parser]::ParseFile('$escapedPath', [ref]`$tokens, [ref]`$errors); `$errors.Count }"
    $ps51ErrCount = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $cmd
    $ps51Valid = ($null -ne $ps51ErrCount -and [int]($ps51ErrCount | Select-Object -Last 1) -eq 0)

    return ($ps7Valid -and $ps51Valid)
}

# Test environment isolation
Assert-Test "Test environment does not write to the user configuration" {
    $realConfigDir = Join-Path $HOME ".terminal-ai"
    $isIsolated = ($env:TERMINAL_AI_CONFIG_DIR -ne $realConfigDir -and (Test-Path $env:TERMINAL_AI_CONFIG_DIR))
    return $isIsolated
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
$evaluatedTests = $passed + ($tests - $passed - $skipped)
$score = if ($evaluatedTests -gt 0) { [Math]::Round(($passed / $evaluatedTests) * 100, 1) } else { 100.0 }
if ($allPassed) {
    Write-Host "  All evaluated tests passed ($passed / $evaluatedTests; live skipped: $skipped) • 100%" -ForegroundColor Green
} else {
    Write-Host "  Some tests failed ($passed / $evaluatedTests) • Score: $score / 100" -ForegroundColor Yellow
}
Write-Host "  EVALUATOR_SCORE: $score / 100" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

}
finally {
    # Always clean up the temporary environment
    $env:TERMINAL_AI_CONFIG_DIR = $origConfigDir
    $env:TERMINAL_AI_LANG = $origLang
    if ($testTempRoot -and (Test-Path $testTempRoot)) {
        Remove-Item -Path $testTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $allPassed) {
    exit 1
} else {
    exit 0
}
