# Test-TerminalAi.ps1 - Комплексний тест перевірки TerminalAI

$ErrorActionPreference = "Stop"

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "             Запуск тестів розширення TerminalAI               " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$allPassed = $true
$tests = 0
$passed = 0

function Assert-Test {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    $script:tests++
    Write-Host "Тест $script:tests : $Name ... " -NoNewline -ForegroundColor White
    try {
        $result = & $TestBlock
        if ($result -ne $false) {
            $script:passed++
            Write-Host "ПРОЙДЕНО" -ForegroundColor Green
        } else {
            $script:allPassed = $false
            Write-Host "НЕВДАЛО (Умова не виконана)" -ForegroundColor Red
        }
    } catch {
        $script:allPassed = $false
        Write-Host "ПОМИЛКА: $($_.Exception.Message)" -ForegroundColor Red
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Тест конфігурації
Assert-Test "Збереження та читання конфігурації" {
    . (Join-Path $PSScriptRoot "TerminalAiConfig.ps1")
    $cfg = Get-TerminalAiConfig
    if ($null -eq $cfg.Model -or $null -eq $cfg.OllamaUrl) { return $false }
    return $true
}

# 2. Тест імпорту маніфесту модуля
Assert-Test "Імпорт модуля TerminalAI.psd1 та перевірка експорту" {
    Import-Module (Join-Path $PSScriptRoot "TerminalAI.psd1") -Force
    $mod = Get-Module TerminalAI
    $hasCmd = $mod.ExportedFunctions.ContainsKey("Invoke-AiCommand")
    $hasAlias = $mod.ExportedAliases.ContainsKey("ai")
    return ($hasCmd -and $hasAlias)
}

# 3. Тест зв'язку з Ollama
Assert-Test "З'єднання з локальною Ollama та отримання моделей" {
    $models = Get-TerminalAiModels
    return ($models.Count -gt 0)
}

# 4. Тест генерації команди через Ollama
$testModel = (Get-TerminalAiConfig).Model
Assert-Test "Генерація PowerShell команди через Ollama ($testModel)" {
    $code = Invoke-OllamaApi -Prompt "Write a single PowerShell command to get the current date in yyyy-MM-dd format" -Model $testModel -Temperature 0.1
    $clean = Clean-AiCodeOutput -Text $code
    Write-Host "`n    [Згенеровано]: $clean" -ForegroundColor DarkCyan
    return (-not [string]::IsNullOrWhiteSpace($clean))
}

# 5. Тест очищення markdown розмітки та тегів міркування
Assert-Test "Функція очищення виводу Clean-AiCodeOutput" {
    $raw = '```powershell' + [Environment]::NewLine + 'Get-Process' + [Environment]::NewLine + '```'
    $clean = Clean-AiCodeOutput -Text $raw
    $thinkRaw = '<think>I should use Get-Process</think>' + [Environment]::NewLine + '`Get-Process`'
    $thinkClean = Clean-AiCodeOutput -Text $thinkRaw
    return ($clean -eq "Get-Process" -and $thinkClean -eq "Get-Process")
}

# 6. Тест отримання шрифтів терміналу
Assert-Test "Виявлення активного та моноширинних шрифтів терміналу" {
    $fontInfo = Get-TerminalAiFonts
    if ($null -eq $fontInfo -or $fontInfo.Fonts.Count -eq 0) { return $false }
    Write-Host "`n    [Активний шрифт]: $($fontInfo.ActiveFont)" -ForegroundColor DarkCyan
    return (-not [string]::IsNullOrWhiteSpace($fontInfo.ActiveFont))
}

# 7. Тест перемикання мови та постійної фіксації (-Permanent)
Assert-Test "Перемикання мови інтерфейсу та постійна фіксація (-Permanent)" {
    $origLang = (Get-TerminalAiConfig).Language
    Set-TerminalAiLanguage -Language "en" -Permanent | Out-Null
    $cfgEn = Get-TerminalAiConfig
    $txtEn = Get-TerminalAiText "CardTitle"
    $envEn = $env:TERMINAL_AI_LANG
    
    Set-TerminalAiLanguage -Language "uk" -Permanent | Out-Null
    $cfgUk = Get-TerminalAiConfig
    $txtUk = Get-TerminalAiText "CardTitle"
    $envUk = $env:TERMINAL_AI_LANG

    # Залишаємо українську як активну мову
    Set-TerminalAiLanguage -Language "uk" -Permanent | Out-Null

    return ($cfgEn.Language -eq "en" -and $txtEn -eq "AI Command" -and $envEn -eq "en" -and `
            $cfgUk.Language -eq "uk" -and $txtUk -eq "AI Команда" -and $envUk -eq "uk")
}

# 8. Тест нових аліасів та функцій
Assert-Test "Експорт команд шрифтів та постійної мови (ai-font, ai-lang, ai-lang-permanent)" {
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

# 9. Тест інтерактивного помічника та автодоповнення
Assert-Test "Експорт інтерактивного агента (Invoke-AiAssistant, ai-chat, TerminalAiAssistant.ps1)" {
    $mod = Get-Module TerminalAI
    $hasAssistantFunc = $mod.ExportedFunctions.ContainsKey("Invoke-AiAssistant")
    $hasChatAlias = $mod.ExportedAliases.ContainsKey("ai-chat")
    $hasAssistantAlias = $mod.ExportedAliases.ContainsKey("ai-assistant")
    $assistantPath = Join-Path $PSScriptRoot "TerminalAiAssistant.ps1"
    $hasAssistantScript = Test-Path $assistantPath

    # Перевіримо також синтаксичну коректність TerminalAiAssistant.ps1
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($assistantPath, [ref]$null, [ref]$parseErrors)
    $syntaxValid = ($parseErrors.Count -eq 0)

    return ($hasAssistantFunc -and $hasChatAlias -and $hasAssistantAlias -and $hasAssistantScript -and $syntaxValid)
}

# 10. Тест функцій одноразового зчитування клавіш меню та очищення буфера
Assert-Test "Експорт функцій зчитування меню (Clear-AiInputBuffer, Get-AiMenuKeyPress)" {
    $mod = Get-Module TerminalAI
    $hasClearBuf = $mod.ExportedFunctions.ContainsKey("Clear-AiInputBuffer")
    $hasReadKey = $mod.ExportedFunctions.ContainsKey("Get-AiMenuKeyPress")

    # Виклик Clear-AiInputBuffer не повинен викидати помилок
    Clear-AiInputBuffer

    return ($hasClearBuf -and $hasReadKey)
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "  Всі тести успішно пройдені! ($passed / $tests)" -ForegroundColor Green
} else {
    Write-Host "  Деякі тести завершилися з помилкою ($passed / $tests)" -ForegroundColor Red
}
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

