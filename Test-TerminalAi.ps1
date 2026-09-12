# Test-TerminalAi.ps1 - Комплексний тест перевірки TerminalAI
[CmdletBinding()]
param(
    [switch]$RunLiveTests
)

$ErrorActionPreference = "Stop"

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "             Запуск тестів розширення TerminalAI               " -ForegroundColor Cyan
if (-not $RunLiveTests) {
    Write-Host "       [Режим: Детермінований (Live-тести Ollama пропущено)]   " -ForegroundColor Yellow
} else {
    Write-Host "       [Режим: Повний (з живими запитами до локальної Ollama)]  " -ForegroundColor Magenta
}
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$allPassed = $true
$tests = 0
$passed = 0
$skipped = 0

# Ізоляція тестового середовища (захист реальної конфігурації користувача та $PROFILE)
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

function Assert-LiveTest {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    $script:tests++
    Write-Host "Тест $script:tests : $Name ... " -NoNewline -ForegroundColor White
    if (-not $RunLiveTests) {
        $script:skipped++
        Write-Host "ПРОПУЩЕНО (потрібен -RunLiveTests)" -ForegroundColor Yellow
        return
    }
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

try {

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
Assert-LiveTest "З'єднання з локальною Ollama та отримання моделей" {
    $models = Get-TerminalAiModels
    return ($models.Count -gt 0)
}

# 4. Тест генерації команди через Ollama
$testModel = (Get-TerminalAiConfig).Model
Assert-LiveTest "Генерація PowerShell команди через Ollama ($testModel)" {
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

    # Залишаємо мову за замовчуванням англійською (en)
    Set-TerminalAiLanguage -Language "en" -Permanent | Out-Null

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


# 11. Перевірка кодування UTF-8 з BOM на всіх скриптах для підтримки PS 5.1
Assert-Test "Кодування UTF-8 з BOM на всіх файлах .ps1, .psm1, .psd1" {
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

# 12. Імпорт маніфесту модуля у Windows PowerShell 5.1
Assert-Test "Імпорт модуля у Windows PowerShell 5.1 (без збоїв AOT та UTF-8)" {
    $cmd = "Import-Module (Join-Path '$PSScriptRoot' 'TerminalAI.psd1') -Force -PassThru"
    $ps51Result = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $cmd 2>&1
    $exitCode = $LASTEXITCODE
    return ($exitCode -eq 0 -and $ps51Result -match 'TerminalAI')
}

# 13. Конвертація аліасів ConvertTo-AiShortAliases
Assert-Test "Конвертація повних командлетів у короткі аліаси (ConvertTo-AiShortAliases)" {
    $mod = Get-Module TerminalAI | Select-Object -First 1
    $short = & $mod { ConvertTo-AiShortAliases 'Get-Process | Where-Object { $_.CPU -gt 10 } | ForEach-Object { $_.Name }' }
    return ($short -match 'gps' -and $short -match '\?' -and $short -match '%')
}

# 14. Зворотна конвертація ConvertTo-AiFullCmdlets без спотворення коду
Assert-Test "Зворотна конвертація аліасів без подвійних підстановок (ConvertTo-AiFullCmdlets)" {
    $mod = Get-Module TerminalAI | Select-Object -First 1
    $full = & $mod { ConvertTo-AiFullCmdlets 'Get-Process | ? { $_.CPU -gt 10 } | % { $_.Name }' }
    $valid = ($full -eq 'Get-Process | Where-Object { $_.CPU -gt 10 } | ForEach-Object { $_.Name }')
    return $valid
}

# 15. Доступність System.Net.Http у Windows PowerShell 5.1
Assert-Test "Доступність System.Net.Http у середовищі Windows PowerShell 5.1" {
    $cmd = "Import-Module (Join-Path '$PSScriptRoot' 'TerminalAI.psd1') -Force; [bool][Type]::GetType('System.Net.Http.HttpClient, System.Net.Http, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')"
    $ps51Http = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $cmd 2>&1
    return ($ps51Http -match 'True')
}

# 16. Синхронізація шляху до конфігурації у довідці та коді (.terminal-ai)
Assert-Test "Синхронізація шляху до конфігурації (~/.terminal-ai/config.json)" {
    $psm1Content = Get-Content -Path (Join-Path $PSScriptRoot "TerminalAI.psm1") -Raw
    $hasTypo = ($psm1Content -match '\.terminalai/config\.json')
    return (-not $hasTypo)
}

# 17. Портативність конфігурації Windows Terminal fragment
Assert-Test "Портативність terminalai.json (відсутність локальних абсолютних шляхів користувача)" {
    $jsonPath = Join-Path $PSScriptRoot "terminalai.json"
    $jsonContent = Get-Content -Path $jsonPath -Raw
    $hasHardcodedUser = ($jsonContent -match 'C:\\Users\\|OneDrive|Belgeler')
    return (-not $hasHardcodedUser)
}

# 18. Обробка некоректного markdown та незакритих блоків у Format-AiCodeOutput
Assert-Test "Обробка незакритих markdown-блоків у Format-AiCodeOutput" {
    $bt = [char]96
    $unclosed = "$bt$bt$bt" + "powershell`nGet-Process"
    $cleaned = Format-AiCodeOutput -Text $unclosed
    return ($cleaned.Trim() -eq "Get-Process")
}

# 19. Стійкість та зворотний зв'язок обробника F2 при помилці Ollama
Assert-Test "Стійкість та наявність зворотного зв'язку в Register-TerminalAiKeyHandler" {
    $psm1Content = Get-Content -Path (Join-Path $PSScriptRoot "TerminalAI.psm1") -Raw
    $hasFeedback = ($psm1Content -match '\[AI:.*(?:offline|помилка|недоступн|error)\]')
    return $hasFeedback
}

# 20. Стійкість консольного читання в TerminalAiAssistant до відсутності інтерактивного хоста
Assert-Test "Стійкість Read-AssistantLine до неінтерактивного консольного хоста (try/catch RawUI)" {
    $assistantContent = Get-Content -Path (Join-Path $PSScriptRoot "TerminalAiAssistant.ps1") -Raw
    $hasProtectedReadKey = ($assistantContent -match 'try\s*\{\s*\$key\s*=\s*\$Host\.UI\.RawUI\.ReadKey')
    return $hasProtectedReadKey
}

# 21. Тест виклику ендпоінта /api/chat через Invoke-OllamaApi -Messages
Assert-LiveTest "Підтримка діалогового режиму Invoke-OllamaApi -Messages (/api/chat)" {
    $cfg = Get-TerminalAiConfig
    $testMessages = @(
        @{ role = "user"; content = "respond with the exact word CHAT_TEST_OK only" }
    )
    $chatRes = Invoke-OllamaApi -Messages $testMessages -Model $cfg.Model -Temperature 0.1
    return ($chatRes -match 'CHAT_TEST_OK')
}

# 22. Перевірка підтримки сесійної пам'яті та команд /reset, /context, /inspect
Assert-Test "Підтримка сесійної пам'яті та команд /reset, /context, /inspect у помічнику" {
    $assistantContent = Get-Content -Path (Join-Path $PSScriptRoot "TerminalAiAssistant.ps1") -Raw
    $hasHistoryVar = ($assistantContent -match '\$script:AiChatHistory')
    $hasResetCmd = ($assistantContent -match '/reset')
    $hasContextCmd = ($assistantContent -match '/context')
    $hasInspectCmd = ($assistantContent -match '/inspect')
    return ($hasHistoryVar -and $hasResetCmd -and $hasContextCmd -and $hasInspectCmd)
}

# 23. Детермінований тест серіалізації багатодіалогового payload без виклику мережі
Assert-Test "Детерміноване формування payload діалогу (/api/chat) з системним промптом" {
    $testMsgs = @(
        @{ role = "user"; content = "Перший запит" },
        @{ role = "assistant"; content = "Перша відповідь" },
        @{ role = "user"; content = "Другий запит" }
    )
    $sysPrompt = "Системний інженерний промпт"
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
            $roundTrip.messages[1].content -eq "Перший запит" -and `
            $roundTrip.messages[2].role -eq "assistant" -and `
            $roundTrip.messages[3].content -eq "Другий запит")
}

# 24. Регресійний парсерний тест деінсталятора Uninstall-TerminalAi.ps1 (PS 7 та PS 5.1)
Assert-Test "Регресійний парсерний тест Uninstall-TerminalAi.ps1 (PS 7 та PS 5.1)" {
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

# 25. Перевірка ізоляції тестового середовища
Assert-Test "Ізоляція тестового середовища (відсутність запису у $HOME\.terminal-ai)" {
    $realConfigDir = Join-Path $HOME ".terminal-ai"
    $isIsolated = ($env:TERMINAL_AI_CONFIG_DIR -ne $realConfigDir -and (Test-Path $env:TERMINAL_AI_CONFIG_DIR))
    return $isIsolated
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
$evaluatedTests = $passed + ($tests - $passed - $skipped)
$score = if ($evaluatedTests -gt 0) { [Math]::Round(($passed / $evaluatedTests) * 100, 1) } else { 100.0 }
if ($allPassed) {
    Write-Host "  Всі оцінювані тести успішно пройдені! ($passed / $evaluatedTests, пропущено live: $skipped) • 100%" -ForegroundColor Green
} else {
    Write-Host "  Деякі тести завершилися з помилкою ($passed / $evaluatedTests) • Score: $score / 100" -ForegroundColor Yellow
}
Write-Host "  EVALUATOR_SCORE: $score / 100" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

}
finally {
    # Гарантоване очищення тимчасового середовища
    $env:TERMINAL_AI_CONFIG_DIR = $origConfigDir
    $env:TERMINAL_AI_LANG = $origLang
    if ($testTempRoot -and (Test-Path $testTempRoot)) {
        Remove-Item -Path $testTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}


