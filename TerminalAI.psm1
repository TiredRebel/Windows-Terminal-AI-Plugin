# TerminalAI.psm1 - PowerShell AI Розширення на базі локальної Ollama
# Requires -Version 5.1

# Забезпечуємо повну підтримку UTF-8 для коректного відображення кирилиці в консолі
try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# Завантажуємо збірку System.Net.Http для надійної роботи в Windows PowerShell 5.1
try {
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
} catch { }

# Завантажуємо допоміжний модуль конфігурації
$configScriptPath = Join-Path $PSScriptRoot "TerminalAiConfig.ps1"
if (Test-Path $configScriptPath) {
    . $configScriptPath
}

# Завантажуємо високопродуктивний бінарний модуль C# (AOT), якщо доступний
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $aotCandidates = @(
        (Join-Path $PSScriptRoot "TerminalAI.Aot.dll"),
        (Join-Path $PSScriptRoot "AOT\bin\Release\net10.0\TerminalAI.Aot.dll")
    )
    foreach ($cand in $aotCandidates) {
        if (Test-Path $cand) {
            try {
                Import-Module $cand -Global -ErrorAction SilentlyContinue
                break
            } catch { }
        }
    }
}


# Допоміжний клас для надійної відкладеної вставки через синтез клавіш у Windows Terminal ConPTY
if (-not ([System.Management.Automation.PSTypeName]'TerminalAiPasteHelper').Type) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

public static class TerminalAiPasteHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern uint MapVirtualKey(uint uCode, uint uMapType);

    private const byte VK_CONTROL = 0x11;
    private const byte VK_V = 0x56;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    public static void DelayedPaste(int delayMs = 200) {
        Task.Run(() => {
            try {
                Thread.Sleep(delayMs);
                byte scanCtrl = (byte)MapVirtualKey(VK_CONTROL, 0);
                byte scanV = (byte)MapVirtualKey(VK_V, 0);

                keybd_event(VK_CONTROL, scanCtrl, 0, UIntPtr.Zero);
                keybd_event(VK_V, scanV, 0, UIntPtr.Zero);
                keybd_event(VK_V, scanV, KEYEVENTF_KEYUP, UIntPtr.Zero);
                keybd_event(VK_CONTROL, scanCtrl, KEYEVENTF_KEYUP, UIntPtr.Zero);
            } catch { }
        });
    }
}
'@ -ErrorAction SilentlyContinue
    } catch { }
}

# --- ДОПОМІЖНІ ФУНКЦІЇ ---

function Format-AiCodeOutput {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    $clean = $Text.Trim()

    # Видаляємо блок міркувань reasoning-моделей (все до тегу </think> включно)
    if ($clean -match '(?si)</think>\s*(.*)') {
        $clean = $Matches[1].Trim()
    } elseif ($clean -match '(?si)<think>.*?</think>\s*(.*)') {
        $clean = $Matches[1].Trim()
    }

    # Видаляємо блок markdown (```powershell ... ``` або ``` ... ```, включаючи незакриті блоки)
    if ($clean -match '(?si)```(?:powershell|pwsh)?\r?\n?(.*?)\r?\n?```') {
        $clean = $Matches[1].Trim()
    } elseif ($clean -match '(?si)```(?:powershell|pwsh)?\r?\n?(.*)') {
        $clean = ($Matches[1] -replace '(?s)```$', '').Trim()
    }
    # Видаляємо одинарні зворотні лапки якщо рядок ними обгорнутий
    if ($clean.StartsWith('`') -and $clean.EndsWith('`') -and $clean.Length -gt 2) {
        $clean = $clean.Substring(1, $clean.Length - 2).Trim()
    }

    return $clean
}
Set-Alias -Name Clean-AiCodeOutput -Value Format-AiCodeOutput

$script:TerminalAiAliasPairs = @(
    @{ Full = "Get-Process"; Short = "gps" },
    @{ Full = "Get-ChildItem"; Short = "gci" },
    @{ Full = "Where-Object"; Short = "?" },
    @{ Full = "ForEach-Object"; Short = "%" },
    @{ Full = "Select-Object"; Short = "select" },
    @{ Full = "Sort-Object"; Short = "sort" },
    @{ Full = "Measure-Object"; Short = "measure" },
    @{ Full = "Get-Content"; Short = "gc" },
    @{ Full = "Set-Content"; Short = "sc" },
    @{ Full = "Select-String"; Short = "sls" },
    @{ Full = "Get-Service"; Short = "gsv" },
    @{ Full = "Stop-Process"; Short = "kill" },
    @{ Full = "Format-Table"; Short = "ft" },
    @{ Full = "Format-List"; Short = "fl" },
    @{ Full = "Export-Csv"; Short = "epcsv" },
    @{ Full = "Import-Csv"; Short = "ipcsv" },
    @{ Full = "Get-Help"; Short = "help" },
    @{ Full = "Clear-Host"; Short = "cls" },
    @{ Full = "Copy-Item"; Short = "cpi" },
    @{ Full = "Move-Item"; Short = "mi" },
    @{ Full = "Remove-Item"; Short = "ri" },
    @{ Full = "New-Item"; Short = "ni" },
    @{ Full = "Get-Item"; Short = "gi" },
    @{ Full = "Set-Item"; Short = "si" },
    @{ Full = "Get-Location"; Short = "gl" },
    @{ Full = "Set-Location"; Short = "sl" }
)

function ConvertTo-AiShortAliases {
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return $Code }

    $Code = [regex]::Replace($Code, '\b(?:gci|Get-ChildItem)\s+tcpconn\b', 'Get-NetTCPConnection', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($p in $script:TerminalAiAliasPairs) {
        $pattern = "(?<![\w\-])\b" + [regex]::Escape($p.Full) + "\b(?![\w\-])"
        $Code = [regex]::Replace($Code, $pattern, $p.Short, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    $Code = [regex]::Replace($Code, "(?<![\w\-])-ErrorAction\s+(?:SilentlyContinue|0)\b", "-ea 0", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return $Code
}

function ConvertTo-AiFullCmdlets {
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return $Code }

    $Code = [regex]::Replace($Code, '\b(?:gci|Get-ChildItem)\s+tcpconn\b', 'Get-NetTCPConnection', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($p in $script:TerminalAiAliasPairs) {
        $sh = $p.Short
        $full = $p.Full
        if ($sh -in @("?", "%")) {
            $pattern = "(?<=[|\({;\s]|^)" + [regex]::Escape($sh) + "(?=\s|[{])"
            $Code = [regex]::Replace($Code, $pattern, $full)
        } else {
            $pattern = "(?<![\w\-])\b" + [regex]::Escape($sh) + "\b(?![\w\-])"
            $Code = [regex]::Replace($Code, $pattern, $full, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $Code = [regex]::Replace($Code, "(?<![\w\-])-ea\s+0\b", "-ErrorAction SilentlyContinue", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return $Code
}

function Get-TerminalAiText {
    param([string]$Key)
    $cfg = Get-TerminalAiConfig
    $lang = if ($cfg.Language -eq "en") { "en" } else { "uk" }

    $dict = @{
        "uk" = @{
            "CardTitle"         = "AI Команда"
            "CardTitleAnswer"   = "AI Відповідь"
            "CardTitleFixed"    = "Виправлена команда"
            "CardTitleExplain"  = "Пояснення команди"
            "Connecting"        = "Звертаюсь до Ollama"
            "Answering"         = "Формую відповідь через"
            "Explaining"        = "Формую детальне пояснення команди..."
            "Fixing"            = "Аналіз останньої помилки"
            "Scripting"         = "Генерація комплексного сценарію PowerShell..."
            "MenuEnter"         = "Виконати"
            "MenuCopy"          = "Скопіювати"
            "MenuInsert"        = "Вставити в рядок"
            "MenuAlias"         = "Аліаси"
            "MenuFull"          = "Повні"
            "MenuExplain"       = "Пояснити код"
            "MenuAsk"           = "Текстова відповідь"
            "MenuWhatIf"        = "Симуляція (-WhatIf)"
            "MenuCancel"        = "Скасувати"
            "Copied"            = "Скопійовано в буфер обміну!"
            "Inserted"          = "Команду вставлено у рядок введення!"
            "Executing"         = "Виконання команди:"
            "ExecutingFixed"    = "Виконую виправлену команду:"
            "Canceled"          = "Скасовано."
            "UnknownCmdlet"     = "Команду не знайдено в сесії PowerShell."
            "UnknownCmdletHint" = "(Ймовірно, ваше питання мало інформаційний характер або модель вигадала команду)"
            "Warning"           = "Попередження"
            "NoError"           = "Помилок у поточній сесії не виявлено! Все працює ідеально."
            "Diagnosis"         = "Діагностика проблеми:"
            "FailedCommand"     = "Команда з помилкою:"
            "ErrorLabel"        = "Помилка:"
            "SaveScriptPrompt"  = "Зберегти цей сценарій у файл? [Y/N]: "
            "EnterFileName"     = "Введіть ім'я файлу (за замовчуванням: {0}): "
            "SavedAt"           = "Сценарій успішно збережено у:"
            "Welcome"           = "✦ Terminal AI активовано! Спробуйте: ai або F2"
        }
        "en" = @{
            "CardTitle"         = "AI Command"
            "CardTitleAnswer"   = "AI Answer"
            "CardTitleFixed"    = "Fixed Command"
            "CardTitleExplain"  = "Command Explanation"
            "Connecting"        = "Connecting to Ollama"
            "Answering"         = "Generating answer via"
            "Explaining"        = "Generating detailed command explanation..."
            "Fixing"            = "Analyzing last error"
            "Scripting"         = "Generating complex PowerShell script..."
            "MenuEnter"         = "Execute"
            "MenuCopy"          = "Copy"
            "MenuInsert"        = "Insert into line"
            "MenuAlias"         = "Alias"
            "MenuFull"          = "Full"
            "MenuExplain"       = "Explain code"
            "MenuAsk"           = "Text answer"
            "MenuWhatIf"        = "Preview (-WhatIf)"
            "MenuCancel"        = "Cancel"
            "Copied"            = "Copied to clipboard!"
            "Inserted"          = "Command inserted into input line!"
            "Executing"         = "Executing command:"
            "ExecutingFixed"    = "Executing fixed command:"
            "Canceled"          = "Canceled."
            "UnknownCmdlet"     = "Command not found in PowerShell session."
            "UnknownCmdletHint" = "(Likely your query was informational or model hallucinated a cmdlet)"
            "Warning"           = "Warning"
            "NoError"           = "No errors detected in current session! Everything runs smoothly."
            "Diagnosis"         = "Problem Diagnosis:"
            "FailedCommand"     = "Failed command:"
            "ErrorLabel"        = "Error:"
            "SaveScriptPrompt"  = "Save this script to a file? [Y/N]: "
            "EnterFileName"     = "Enter file name (default: {0}): "
            "SavedAt"           = "Script successfully saved to:"
            "Welcome"           = "✦ Terminal AI activated! Try: ai or F2"
        }
    }

    if ($dict[$lang] -and $dict[$lang][$Key]) {
        return $dict[$lang][$Key]
    } elseif ($dict["uk"][$Key]) {
        return $dict["uk"][$Key]
    } else {
        return $Key
    }
}

function Show-TerminalAiWelcome {
    <#
    .SYNOPSIS
        Виводить вітальне повідомлення TerminalAI поточною мовою інтерфейсу.
    #>
    [CmdletBinding()]
    param()

    Write-Host (Get-TerminalAiText "Welcome") -ForegroundColor Cyan
}

function Show-TerminalAiHelp {
    <#
    .SYNOPSIS
        Детальна інтерактивна довідка та навчальний посібник для TerminalAI.
    .DESCRIPTION
        Відображає структуровані навчальні посібники для роботи та навчання:
        - all: Загальний огляд системи та карта команд
        - shortcuts: Повний перелік швидких аліасів, однобуквених прапорців та комбінацій клавіш
        - models: Огляд моделей Ollama, вимоги до RAM/VRAM та рекомендовані моделі для кодингу
        - examples: Реальні приклади щоденних задач DevOps, адміністрування та автоматизації
        - workflow: Посібник з інтерактивної взаємодії в Windows Terminal
    .PARAMETER Topic
        Тема довідки: all, shortcuts, models, examples, workflow, config.
    .EXAMPLE
        ai-help
    .EXAMPLE
        ai-help shortcuts
    .EXAMPLE
        ai help models
    .EXAMPLE
        aif help examples
    #>
    [CmdletBinding()]
    [Alias("ai-help")]
    param(
        [Parameter(Position = 0)]
        [ValidateSet("all", "shortcuts", "models", "examples", "workflow", "config")]
        [string]$Topic = "all"
    )

    $cfg = Get-TerminalAiConfig
    $isUk = ($cfg.Language -ne "en")
    $conWidth = 80
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 20) {
            $conWidth = $Host.UI.RawUI.WindowSize.Width
        } elseif ([Console]::WindowWidth -gt 20) {
            $conWidth = [Console]::WindowWidth
        }
    } catch { }

    $bw = [Math]::Min(68, [Math]::Max(40, $conWidth - 8))

    $renderLine = {
        param([string]$Text, [System.ConsoleColor]$Color = [System.ConsoleColor]::White)
        $maxLen = [Math]::Max(0, $bw - 2)
        if ($Text.Length -gt $maxLen) { $Text = $Text.Substring(0, $maxLen) }
        $pad = $bw - 2 - $Text.Length
        if ($pad -lt 0) { $pad = 0 }
        Write-Host "    │ " -NoNewline -ForegroundColor DarkCyan
        Write-Host $Text -NoNewline -ForegroundColor $Color
        Write-Host (" " * $pad + " │") -ForegroundColor DarkCyan
    }

    Write-Host ""
    switch ($Topic.ToLowerInvariant()) {
        "shortcuts" {
            $tTitle = if ($isUk) { "Довідник аліасів, скорочень та клавіш" } else { "Shortcuts, Aliases & Keybindings Guide" }
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            if ($isUk) {
                & $renderLine "1. ГОЛОВНІ АЛІАСИ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   aif <запит>    Швидкий бінарний модуль C# (нативний AOT)" ([System.ConsoleColor]::White)
                & $renderLine "   ai <запит>     Стандартний модуль PowerShell" ([System.ConsoleColor]::White)
                & $renderLine "   ?? <запит>     Короткий синонім для генерації" ([System.ConsoleColor]::White)
                & $renderLine "   F2             Інлайн-генерація команди прямо у рядку PSReadLine" ([System.ConsoleColor]::Yellow)
                & $renderLine "   ai-fix         Діагностика та автоматичне виправлення останньої помилки" ([System.ConsoleColor]::White)
                & $renderLine "   ai-script      Генератор комплексних багаторядкових .ps1 сценаріїв" ([System.ConsoleColor]::White)
                & $renderLine "   ai-chat        Інтерактивний агент зі слеш-командами та Tab" ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "2. КОРОТКІ ПРАПОРЦІ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   -x, -y         Виконати згенеровану команду відразу (-Execute)" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -c             Скопіювати команду відразу в буфер обміну (-Copy)" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -a, -Alias     Генерувати з короткими аліасами PowerShell (gps, gci, ?)" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -Explain       Згенерувати детальне структуроване пояснення коду" ([System.ConsoleColor]::Magenta)
                & $renderLine "   -Ask, -chat    Отримати текстову відповідь/консультацію замість коду" ([System.ConsoleColor]::Blue)
                & $renderLine ""
                & $renderLine "3. КЛАВІШІ В ІНТЕРАКТИВНОМУ МЕНЮ (після генерації):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   [Enter]        Виконати згенеровану команду в поточній сесії" ([System.ConsoleColor]::Green)
                & $renderLine "   [C] / [c]      Скопіювати в буфер обміну" ([System.ConsoleColor]::Yellow)
                & $renderLine "   [I] / [i]      Вставити команду в рядок введення терміналу" ([System.ConsoleColor]::Cyan)
                & $renderLine "   [S] / [s]      Перемкнути між короткими аліасами та повними назвами (Alias/Full)" ([System.ConsoleColor]::DarkYellow)
                & $renderLine "   [X] / [x]      Пояснити синтаксис та безпеку команди" ([System.ConsoleColor]::Magenta)
                & $renderLine "   [A] / [a]      Отримати розгорнуту текстову відповідь" ([System.ConsoleColor]::Blue)
                & $renderLine "   [Esc]          Скасувати" ([System.ConsoleColor]::DarkGray)
            } else {
                & $renderLine "1. PRIMARY ALIASES:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   aif <prompt>   Ultra-fast compiled C# binary module (Native AOT)" ([System.ConsoleColor]::White)
                & $renderLine "   ai <prompt>    Standard PowerShell module" ([System.ConsoleColor]::White)
                & $renderLine "   ?? <prompt>    Short alias for instant command generation" ([System.ConsoleColor]::White)
                & $renderLine "   F2             Inline PSReadLine generation directly in prompt" ([System.ConsoleColor]::Yellow)
                & $renderLine "   ai-fix         Diagnose and fix the last failed command in session" ([System.ConsoleColor]::White)
                & $renderLine "   ai-script      Generate complex multi-step .ps1 automation scripts" ([System.ConsoleColor]::White)
                & $renderLine "   ai-chat        Interactive terminal assistant with Tab completion" ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "2. SHORT EXECUTION FLAGS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   -x, -y         Execute command immediately without confirmation" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -c             Copy generated command directly to clipboard" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -a, -Alias     Generate using standard short PowerShell aliases (gps, gci, ?)" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -Explain       Generate comprehensive educational breakdown of code" ([System.ConsoleColor]::Magenta)
                & $renderLine "   -Ask, -chat    Get educational text response instead of script" ([System.ConsoleColor]::Blue)
                & $renderLine ""
                & $renderLine "3. INTERACTIVE MENU KEYPRESSES (after generation):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   [Enter]        Execute command in current session" ([System.ConsoleColor]::Green)
                & $renderLine "   [C] / [c]      Copy command to system clipboard" ([System.ConsoleColor]::Yellow)
                & $renderLine "   [I] / [i]      Insert command into prompt line for manual editing" ([System.ConsoleColor]::Cyan)
                & $renderLine "   [S] / [s]      Toggle between short aliases and full cmdlet names (Alias/Full)" ([System.ConsoleColor]::DarkYellow)
                & $renderLine "   [X] / [x]      Explain command syntax, flags, and safety" ([System.ConsoleColor]::Magenta)
                & $renderLine "   [A] / [a]      Provide full conceptual explanation" ([System.ConsoleColor]::Blue)
                & $renderLine "   [Esc]          Cancel and return to prompt" ([System.ConsoleColor]::DarkGray)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        "models" {
            $tTitle = if ($isUk) { "Керівництво по моделях Ollama для розробки" } else { "Ollama Coding Models Guide" }
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            if ($isUk) {
                & $renderLine "РЕКОМЕНДОВАНІ ЛОКАЛЬНІ МОДЕЛІ ДЛЯ POWERSHELL:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  • qwen2.5-coder:7b   [~4.4GB VRAM] ТОП для PowerShell 7, скриптів і CLI" ([System.ConsoleColor]::Green)
                & $renderLine "  • granite4.2:8b      [~5.0GB VRAM] Модель від IBM, чудова для системних задач" ([System.ConsoleColor]::White)
                & $renderLine "  • deepseek-coder:6.7b[~4.0GB VRAM] Швидка кодер-модель з високою точністю" ([System.ConsoleColor]::White)
                & $renderLine "  • qwen2.5-coder:1.5b [~1.2GB VRAM] Надшвидка легка модель для CPU/ноутбуків" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "КОМАНДИ КЕРУВАННЯ МОДЕЛЯМИ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif models              Переглянути список встановлених моделей" ([System.ConsoleColor]::White)
                & $renderLine "  aif model <назва>       Миттєво змінити активну модель" ([System.ConsoleColor]::White)
                & $renderLine "  ollama pull <назва>     Завантажити нову модель (напр: ollama pull qwen2.5-coder:7b)" ([System.ConsoleColor]::DarkGray)
                & $renderLine "  ollama list             Системний список моделей Ollama" ([System.ConsoleColor]::DarkGray)
            } else {
                & $renderLine "RECOMMENDED LOCAL CODING MODELS FOR POWERSHELL:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  • qwen2.5-coder:7b   [~4.4GB VRAM] Top choice for PowerShell 7 pipelines & CLI" ([System.ConsoleColor]::Green)
                & $renderLine "  • granite4.2:8b      [~5.0GB VRAM] Enterprise IBM model, great for sysadmin tasks" ([System.ConsoleColor]::White)
                & $renderLine "  • deepseek-coder:6.7b[~4.0GB VRAM] Fast, precise code generation" ([System.ConsoleColor]::White)
                & $renderLine "  • qwen2.5-coder:1.5b [~1.2GB VRAM] Ultra-lightweight for CPU laptops" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "MODEL MANAGEMENT COMMANDS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif models              View list of installed models & active marker" ([System.ConsoleColor]::White)
                & $renderLine "  aif model <name>        Instantly switch active model" ([System.ConsoleColor]::White)
                & $renderLine "  ollama pull <name>      Download model (e.g. ollama pull qwen2.5-coder:7b)" ([System.ConsoleColor]::DarkGray)
                & $renderLine "  ollama list             List all models downloaded locally" ([System.ConsoleColor]::DarkGray)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        "examples" {
            $tTitle = if ($isUk) { "Практичні приклади для роботи та автоматизації" } else { "Practical DevOps & Admin Examples" }
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            if ($isUk) {
                & $renderLine "ФАЙЛИ ТА ПАПКИ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'знайти файли .log більше 50MB змінені за останні 2 дні'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'порахувати сумарний розмір папки C:\Temp у гігабайтах'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'видалити всі порожні папки рекурсивно' -Explain" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "ПРОЦЕСИ ТА ДІАГНОСТИКА:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'показати топ 5 процесів за пам'яттю у таблиці з MB'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'знайти процес який слухає порт 8080'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'зупинити всі завислі процеси node' -x" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "МЕРЕЖА ТА СИСТЕМА:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'перевірити доступність 8.8.8.8 на порт 53 через TCP'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'вивести IP адресу шлюзу та DNS сервери'" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-fix  (якщо попередня команда впала з помилкою)" ([System.ConsoleColor]::Yellow)
            } else {
                & $renderLine "FILES & DIRECTORIES:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'find all .log files larger than 50MB modified in last 2 days'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'calculate total size of C:\Temp directory in gigabytes'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'delete empty folders recursively' -Explain" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "PROCESSES & DIAGNOSTICS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'show top 5 processes by working set memory in MB'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'find process listening on port 8080'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'terminate all hung node processes' -x" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "NETWORKING & SYSTEMS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'test TCP connection to 8.8.8.8 on port 53'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'display default gateway and active DNS servers'" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-fix  (auto-diagnose and fix the last error)" ([System.ConsoleColor]::Yellow)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        "workflow" {
            $tTitle = if ($isUk) { "Посібник інтерактивної роботи в Windows Terminal" } else { "Interactive Workflow Guide" }
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            if ($isUk) {
                & $renderLine "1. ІНЛАЙН-ГЕНЕРАЦІЯ (Найшвидший спосіб):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Надрукуйте будь-яку задачу людською мовою прямо у рядку вводу" ([System.ConsoleColor]::White)
                & $renderLine "   • Натисніть F2 (або Ctrl+Space) -> текст миттєво заміниться на код" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "2. ІНТЕРАКТИВНЕ МЕНЮ (Безпечний контроль):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Виконайте: aif 'ваша задача'" ([System.ConsoleColor]::White)
                & $renderLine "   • Натисніть [Enter] щоб запустити, [C] щоб скопіювати," ([System.ConsoleColor]::White)
                & $renderLine "     [I] щоб редагувати в консолі, [X] для розбору синтаксису," ([System.ConsoleColor]::White)
                & $renderLine "     [A] для розгорнутої відповіді або [Esc] для відміни." ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "3. АВТОМАТИЧНЕ ВИПРАВЛЕННЯ ПОМИЛОК:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Якщо попередня команда завершилась з помилкою, введіть: ai-fix" ([System.ConsoleColor]::Yellow)
                & $renderLine "   • AI проаналізує стек помилки та запропонує робоче виправлення." ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "4. СКРИПТИ ТА БЕСІДА:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Створення .ps1 скриптів: ai-script 'архівація логів з ротацією'" ([System.ConsoleColor]::White)
                & $renderLine "   • Діалоговий режим розробника: ai-chat (підтримка /help, /model, /clear)" ([System.ConsoleColor]::White)
            } else {
                & $renderLine "1. INLINE GENERATION (Fastest method):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Type any goal in plain English directly at the terminal prompt" ([System.ConsoleColor]::White)
                & $renderLine "   • Press F2 (or Ctrl+Space) -> prompt is replaced with valid code" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "2. INTERACTIVE ACTION MENU (Safe verification):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Run: aif 'your task description'" ([System.ConsoleColor]::White)
                & $renderLine "   • Press [Enter] to run, [C] to copy to clipboard," ([System.ConsoleColor]::White)
                & $renderLine "     [I] to insert into line for editing, [X] to explain syntax," ([System.ConsoleColor]::White)
                & $renderLine "     [A] for conceptual answer, or [Esc] to dismiss." ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "3. AUTOMATED ERROR RECOVERY:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • When any terminal command fails, immediately run: ai-fix" ([System.ConsoleColor]::Yellow)
                & $renderLine "   • AI analyzes the error stream and offers an instant fix." ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "4. PRODUCTION SCRIPTS & CHAT ASSISTANT:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Multi-step scripts: ai-script 'backup IIS logs with compression'" ([System.ConsoleColor]::White)
                & $renderLine "   • Multi-turn assistant: ai-chat (supports /help, /model, /clear)" ([System.ConsoleColor]::White)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        "config" {
            $tTitle = if ($isUk) { "Налаштування конфігурації Terminal AI" } else { "Configuration Settings Guide" }
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            if ($isUk) {
                & $renderLine "ФАЙЛ КОНФІГУРАЦІЇ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  Розташування: ~/.terminal-ai/config.json" ([System.ConsoleColor]::White)
                & $renderLine "  Перегляд:     aif config   або   ai config" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "ОСНОВНІ ПАРАМЕТРИ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  • Model        Активна нейромережа (за замовчуванням qwen2.5-coder:7b)" ([System.ConsoleColor]::White)
                & $renderLine "  • OllamaUrl    Адреса сервера Ollama (http://localhost:11434)" ([System.ConsoleColor]::White)
                & $renderLine "  • Language     Мова інтерфейсу (en або uk)" ([System.ConsoleColor]::White)
                & $renderLine "  • Temperature  Креативність генерації (0.2 для точного коду)" ([System.ConsoleColor]::White)
                & $renderLine "  • AutoCopy     Автокопіювання коду в буфер (true/false)" ([System.ConsoleColor]::White)
                & $renderLine "  • Font         Шрифт Windows Terminal (напр. Cascadia Code NF)" ([System.ConsoleColor]::White)
                & $renderLine "  • HotkeyChord  Комбінація клавіш інлайну (F2 або Ctrl+Space)" ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "ШВИДКІ КОМАНДИ НАЛАШТУВАННЯ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif model <назва>        Змінити активну модель Ollama" ([System.ConsoleColor]::Yellow)
                & $renderLine "  aif lang en | uk         Змінити мову інтерфейсу" ([System.ConsoleColor]::Yellow)
                & $renderLine "  ai font <назва> [розмір] Змінити шрифт Windows Terminal" ([System.ConsoleColor]::Yellow)
            } else {
                & $renderLine "CONFIGURATION FILE:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  Location: ~/.terminal-ai/config.json" ([System.ConsoleColor]::White)
                & $renderLine "  View:     aif config   or   ai config" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "KEY SETTINGS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  • Model        Active coding model (default: qwen2.5-coder:7b)" ([System.ConsoleColor]::White)
                & $renderLine "  • OllamaUrl    Ollama server endpoint (http://localhost:11434)" ([System.ConsoleColor]::White)
                & $renderLine "  • Language     Interface language (en or uk)" ([System.ConsoleColor]::White)
                & $renderLine "  • Temperature  Generation determinism (0.2 for strict code)" ([System.ConsoleColor]::White)
                & $renderLine "  • AutoCopy     Auto-copy generated command to clipboard" ([System.ConsoleColor]::White)
                & $renderLine "  • Font         Windows Terminal font (e.g. Cascadia Code NF)" ([System.ConsoleColor]::White)
                & $renderLine "  • HotkeyChord  Inline shortcut chord (F2 or Ctrl+Space)" ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "QUICK CONFIGURATION COMMANDS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif model <name>        Switch active Ollama model" ([System.ConsoleColor]::Yellow)
                & $renderLine "  aif lang en | uk        Switch interface language" ([System.ConsoleColor]::Yellow)
                & $renderLine "  ai font <name> [size]   Configure Windows Terminal font" ([System.ConsoleColor]::Yellow)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        default {
            # "all" - повна довідка
            $tTitle = if ($isUk) { "Повний довідник та карта команд" } else { "Complete Reference & Commands Map" }
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            if ($isUk) {
                & $renderLine "КОМАНДИ МОДУЛЯ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif, ai-fast      Швидкий нативний бінарний модуль C# (рекомендовано)" ([System.ConsoleColor]::White)
                & $renderLine "  ai, ??            Класичний модуль PowerShell з живим таймером" ([System.ConsoleColor]::White)
                & $renderLine "  ai-fix            Автоматичний аналіз та виправлення останньої помилки" ([System.ConsoleColor]::White)
                & $renderLine "  ai-script         Генератор готових .ps1 скриптів з коментарями" ([System.ConsoleColor]::White)
                & $renderLine "  ai-chat           Інтерактивний асистент зі слеш-командами та історією" ([System.ConsoleColor]::White)
                & $renderLine "  F2                Швидка генерація прямо в активному рядку вводу" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "ТЕМАТИЧНІ РОЗДІЛИ ДОВІДКИ:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  ai-help shortcuts Повний список гарячих клавіш, аліасів та ключів" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help models    Вимоги до пам'яті та рекомендації моделей Ollama" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help examples  Реальні приклади адміністрування та автоматизації" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help workflow  Посібник по роботі з меню, інлайном та помилками" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help config    Довідник конфігурації (~/.terminal-ai/config.json)" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "ОФІЦІЙНА ДОПОМОГА POWERSHELL:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  Get-Help aif -Full        Повна man-сторінка з синтаксисом і типами" ([System.ConsoleColor]::DarkGray)
                & $renderLine "  Get-Help aif -Examples    Приклади використання бінарного модуля" ([System.ConsoleColor]::DarkGray)
            } else {
                & $renderLine "AVAILABLE COMMANDS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif, ai-fast      Fast native C# binary module (recommended)" ([System.ConsoleColor]::White)
                & $renderLine "  ai, ??            Classic PowerShell module with latency timing" ([System.ConsoleColor]::White)
                & $renderLine "  ai-fix            Diagnose and fix the last failed command in session" ([System.ConsoleColor]::White)
                & $renderLine "  ai-script         Generate production-ready multi-line .ps1 scripts" ([System.ConsoleColor]::White)
                & $renderLine "  ai-chat           Interactive terminal assistant with history" ([System.ConsoleColor]::White)
                & $renderLine "  F2                Inline generation directly in PSReadLine prompt" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "DETAILED TOPICS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  ai-help shortcuts Full cheat-sheet of keybindings, flags, and aliases" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help models    VRAM requirements & coding LLM recommendations" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help examples  Practical sysadmin & automation pipeline examples" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help workflow  Workflow guide for menus, inline, and error fixing" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help config    Configuration guide (~/.terminal-ai/config.json)" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "NATIVE POWERSHELL HELP:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  Get-Help aif -Full        Full MAML manual with parameters and types" ([System.ConsoleColor]::DarkGray)
                & $renderLine "  Get-Help aif -Examples    Real-world usage examples" ([System.ConsoleColor]::DarkGray)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }
    }
}


function Show-AiCodeCard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,
        [string]$Title = "",
        [string]$Model = "",
        [System.ConsoleColor]$BorderColor = [System.ConsoleColor]::DarkCyan,
        [System.ConsoleColor]$CodeColor = [System.ConsoleColor]::Green
    )

    if (-not $Title) { $Title = Get-TerminalAiText "CardTitle" }

    $conWidth = 80
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 20) {
            $conWidth = $Host.UI.RawUI.WindowSize.Width
        } elseif ([Console]::WindowWidth -gt 20) {
            $conWidth = [Console]::WindowWidth
        }
    } catch { }

    $maxAllowedInner = [Math]::Max(30, $conWidth - 8)
    $maxLineLen = $maxAllowedInner - 4

    $lines = $Code -split "\r?\n"
    $wrappedLines = @()
    foreach ($l in $lines) {
        if ($l.Length -le $maxLineLen) {
            $wrappedLines += $l
        } else {
            $rem = $l
            while ($rem.Length -gt $maxLineLen) {
                $breakIdx = -1
                $searchStart = [Math]::Max(0, $maxLineLen - 24)
                for ($i = $maxLineLen; $i -ge $searchStart; $i--) {
                    $ch = $rem[$i]
                    if ($ch -eq ' ' -or $ch -eq '|') {
                        $breakIdx = if ($ch -eq '|') { $i } else { $i + 1 }
                        break
                    }
                }
                if ($breakIdx -le 0 -or $breakIdx -gt $maxLineLen) {
                    $breakIdx = $maxLineLen
                }
                $wrappedLines += $rem.Substring(0, $breakIdx).TrimEnd()
                $rem = $rem.Substring($breakIdx).TrimStart()
            }
            if ($rem.Length -gt 0) { $wrappedLines += $rem }
        }
    }

    $maxCodeLen = 0
    foreach ($wl in $wrappedLines) {
        if ($wl.Length -gt $maxCodeLen) { $maxCodeLen = $wl.Length }
    }

    $minBoxInner = [Math]::Min(54, $maxAllowedInner)
    $boxInnerWidth = [Math]::Min($maxAllowedInner, [Math]::Max($minBoxInner, $maxCodeLen + 4))

    $headerLabel = " ✦ $Title"
    if ($Model) { $headerLabel += " • $Model" }

    Write-Host ""
    Write-Host ("    $headerLabel") -ForegroundColor Cyan
    Write-Host ("    ╭" + ("─" * $boxInnerWidth) + "╮") -ForegroundColor $BorderColor
    Write-Host ("    │" + (" " * $boxInnerWidth) + "│") -ForegroundColor $BorderColor

    foreach ($chunk in $wrappedLines) {
        $padRight = $boxInnerWidth - 4 - $chunk.Length
        if ($padRight -lt 0) { $padRight = 0 }
        Write-Host "    │  " -NoNewline -ForegroundColor $BorderColor
        Write-Host $chunk -NoNewline -ForegroundColor $CodeColor
        Write-Host ((" " * $padRight) + "  │") -ForegroundColor $BorderColor
    }

    Write-Host ("    │" + (" " * $boxInnerWidth) + "│") -ForegroundColor $BorderColor
    Write-Host ("    ╰" + ("─" * $boxInnerWidth) + "╯") -ForegroundColor $BorderColor
    Write-Host ""
}

function Show-AiActionMenu {
    param(
        [bool]$UseAliases = $false,
        [bool]$CanPreview = $false
    )

    $tEnter = Get-TerminalAiText "MenuEnter"
    $tCopy = Get-TerminalAiText "MenuCopy"
    $tInsert = Get-TerminalAiText "MenuInsert"
    $tAlias = if ($UseAliases) { Get-TerminalAiText "MenuFull" } else { Get-TerminalAiText "MenuAlias" }
    $tExplain = Get-TerminalAiText "MenuExplain"
    $tAsk = Get-TerminalAiText "MenuAsk"
    $tWhatIf = Get-TerminalAiText "MenuWhatIf"
    $tCancel = Get-TerminalAiText "MenuCancel"

    $conWidth = 80
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 20) {
            $conWidth = $Host.UI.RawUI.WindowSize.Width
        } elseif ([Console]::WindowWidth -gt 20) {
            $conWidth = [Console]::WindowWidth
        }
    } catch { }

    if ($conWidth -ge 120) {
        Write-Host "    [Enter] " -NoNewline -ForegroundColor Green
        Write-Host "$tEnter   " -NoNewline -ForegroundColor White
        Write-Host "[C] " -NoNewline -ForegroundColor Yellow
        Write-Host "$tCopy   " -NoNewline -ForegroundColor White
        Write-Host "[I] " -NoNewline -ForegroundColor Cyan
        Write-Host "$tInsert   " -NoNewline -ForegroundColor White
        Write-Host "[S] " -NoNewline -ForegroundColor DarkYellow
        Write-Host "$tAlias   " -NoNewline -ForegroundColor White
        if ($CanPreview) {
            Write-Host "[W] " -NoNewline -ForegroundColor DarkCyan
            Write-Host "$tWhatIf   " -NoNewline -ForegroundColor White
        }
        Write-Host "[X] " -NoNewline -ForegroundColor Magenta
        Write-Host "$tExplain   " -NoNewline -ForegroundColor White
        Write-Host "[A] " -NoNewline -ForegroundColor Blue
        Write-Host "$tAsk   " -NoNewline -ForegroundColor White
        Write-Host "[Esc] " -NoNewline -ForegroundColor Gray
        Write-Host "$tCancel`n" -ForegroundColor White
    } else {
        Write-Host "    [Enter] " -NoNewline -ForegroundColor Green
        Write-Host ("{0,-14} " -f $tEnter) -NoNewline -ForegroundColor White
        Write-Host "[C] " -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,-14} " -f $tCopy) -NoNewline -ForegroundColor White
        Write-Host "[I] " -NoNewline -ForegroundColor Cyan
        Write-Host $tInsert -ForegroundColor White

        Write-Host "    [S]     " -NoNewline -ForegroundColor DarkYellow
        Write-Host ("{0,-14} " -f $tAlias) -NoNewline -ForegroundColor White
        if ($CanPreview) {
            Write-Host "[W] " -NoNewline -ForegroundColor DarkCyan
            Write-Host ("{0,-14} " -f $tWhatIf) -NoNewline -ForegroundColor White
        }
        Write-Host "[X] " -NoNewline -ForegroundColor Magenta
        Write-Host ("{0,-14} " -f $tExplain) -NoNewline -ForegroundColor White
        Write-Host "[A] " -NoNewline -ForegroundColor Blue
        Write-Host ("{0,-8} " -f $tAsk) -NoNewline -ForegroundColor White
        Write-Host "[Esc] " -NoNewline -ForegroundColor Gray
        Write-Host "$tCancel`n" -ForegroundColor White
    }
}

function Clear-AiInputBuffer {
    <#
    .SYNOPSIS
        Очищає буфер вводу консолі від випадкових натискань під час очікування відповіді від API.
    #>
    try {
        if (-not [Console]::IsInputRedirected) {
            while ([Console]::KeyAvailable) {
                [void][Console]::ReadKey($true)
            }
        }
    } catch { }

    try {
        while ($Host.UI.RawUI.KeyAvailable) {
            [void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    } catch { }
}

function Get-AiMenuKeyPress {
    <#
    .SYNOPSIS
        Зчитує перше валідне натискання клавіші меню без затримок та подвійних натискань у Windows Terminal ConPTY.
    #>
    [CmdletBinding()]
    param(
        [string[]]$AllowedActions = @('Execute', 'Copy', 'Insert', 'ShortAlias', 'Ask', 'Explain', 'WhatIf', 'Cancel')
    )

    while ($true) {
        $keyChar = $null
        $keyEnum = $null
        $vk = 0
        $hasCtrlOrAlt = $false

        # 1. Читання через [Console]::ReadKey($true) - найнадійніше в Windows Terminal / ConPTY
        $readSuccess = $false
        try {
            if (-not [Console]::IsInputRedirected) {
                $keyInfo = [Console]::ReadKey($true)
                $keyEnum = $keyInfo.Key
                $keyChar = $keyInfo.KeyChar
                $vk = [int]$keyInfo.Key
                if (($keyInfo.Modifiers -band [System.ConsoleModifiers]::Control) -or ($keyInfo.Modifiers -band [System.ConsoleModifiers]::Alt)) {
                    $hasCtrlOrAlt = $true
                }
                $readSuccess = $true
            }
        } catch { }

        # 2. Фолбек на $Host.UI.RawUI.ReadKey якщо ввід перенаправлений або Console.ReadKey недоступний
        if (-not $readSuccess) {
            try {
                $rawKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $vk = $rawKey.VirtualKeyCode
                $keyChar = $rawKey.Character
                if ($rawKey.ControlKeyState -match "LeftCtrl|RightCtrl|LeftAlt|RightAlt") {
                    $hasCtrlOrAlt = $true
                }
            } catch {
                return 'Cancel'
            }
        }

        $chCode = if ($keyChar) { [int][char]$keyChar } else { 0 }

        # Ctrl+C -> переривання/скасування
        if (($hasCtrlOrAlt -and $keyEnum -eq [System.ConsoleKey]::C) -or $chCode -eq 3) {
            return 'Cancel'
        }

        # Пропускаємо чисті клавіші-модифікатори або порожні події ConPTY (VK=0, Char=0)
        if (($vk -eq 0 -and $chCode -eq 0) -or ($vk -in @(16, 17, 18, 19, 20, 91, 92, 93) -and $chCode -eq 0)) {
            continue
        }

        # 1. Enter (Execute) - спрацьовує з першого натискання як по коду, так і по символу переведення рядка
        if ('Execute' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::Enter -or $vk -eq 13 -or $chCode -eq 13 -or $chCode -eq 10) {
                return 'Execute'
            }
        }

        # 2. Escape (Cancel)
        if ('Cancel' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::Escape -or $vk -eq 27 -or $chCode -eq 27) {
                return 'Cancel'
            }
        }

        # Для літерних клавіш ігноруємо комбінації з Ctrl/Alt
        if ($hasCtrlOrAlt) {
            continue
        }

        # 3. C (Copy) - англійська C/c або українська С/с
        if ('Copy' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::C -or $vk -eq 67 -or $keyChar -in @('c', 'C', 'с', 'С')) {
                return 'Copy'
            }
        }

        # 4. I (Insert) - англійська I/i, або фізична I в укр розкладці (Ш/ш)
        if ('Insert' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::I -or $vk -eq 73 -or $keyChar -in @('i', 'I', 'ш', 'Ш')) {
                return 'Insert'
            }
        }

        # 5. S (Short / Alias) - англійська S/s, українська І/і (фізична S), або Ы/ы
        if ('ShortAlias' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::S -or $vk -eq 83 -or $keyChar -in @('s', 'S', 'і', 'І', 'ы', 'Ы')) {
                return 'ShortAlias'
            }
        }

        # 6. A (Ask) - англійська A/a, українська А/а, або фізична A в укр розкладці (Ф/ф)
        if ('Ask' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::A -or $vk -eq 65 -or $keyChar -in @('a', 'A', 'а', 'А', 'ф', 'Ф')) {
                return 'Ask'
            }
        }

        # 7. X (Explain) - англійська X/x, українська Х/х, або фізична X в укр розкладці (Ч/ч)
        if ('Explain' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::X -or $vk -eq 88 -or $keyChar -in @('x', 'X', 'х', 'Х', 'ч', 'Ч')) {
                return 'Explain'
            }
        }

        # 8. W (WhatIf / Preview) - англійська W/w, або фізична W в укр розкладці (Ц/ц)
        if ('WhatIf' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::W -or $vk -eq 87 -or $keyChar -in @('w', 'W', 'ц', 'Ц')) {
                return 'WhatIf'
            }
        }
    }
}

function Invoke-OllamaApi {
    [CmdletBinding(DefaultParameterSetName = 'Prompt')]
    param(
        [Parameter(ParameterSetName = 'Prompt', Position = 0)]
        [string]$Prompt,

        [Parameter(ParameterSetName = 'Chat', Mandatory = $true)]
        [object[]]$Messages,

        [string]$SystemPrompt = "",
        [string]$Model,
        [double]$Temperature,
        [switch]$Stream
    )

    $cfg = Get-TerminalAiConfig
    $targetModel = if ($Model) { $Model } else { $cfg.Model }
    $targetTemp = if ($PSBoundParameters.ContainsKey('Temperature')) { $Temperature } else { $cfg.Temperature }

    # Визначаємо режим: Chat (/api/chat) або Generate (/api/generate)
    $isChat = ($PSCmdlet.ParameterSetName -eq 'Chat' -or ($Messages -and $Messages.Count -gt 0))

    if ($isChat) {
        $targetUrl = "$($cfg.OllamaUrl.TrimEnd('/'))/api/chat"
        $chatList = [System.Collections.Generic.List[object]]::new()

        if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
            $hasSystem = $false
            if ($Messages.Count -gt 0 -and $Messages[0] -is [hashtable] -and $Messages[0].role -eq 'system') {
                $hasSystem = $true
            }
            if (-not $hasSystem) {
                $chatList.Add(@{ role = "system"; content = $SystemPrompt })
            }
        }

        foreach ($m in $Messages) {
            $chatList.Add($m)
        }

        $payload = @{
            model      = $targetModel
            messages   = $chatList
            stream     = [bool]$Stream
            keep_alive = "1h"
            options    = @{
                temperature = $targetTemp
                num_ctx     = 4096
            }
        }

        $bodyJson = $payload | ConvertTo-Json -Depth 6

        try {
            $response = Invoke-RestMethod -Uri $targetUrl `
                -Method Post `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
                -ContentType "application/json; charset=utf-8" `
                -TimeoutSec $cfg.TimeoutSeconds `
                -ErrorAction Stop

            return $response.message.content
        }
        catch {
            $msg = $_.Exception.Message
            Write-Error " [TerminalAI] Не вдалося з'єднатися з Ollama за адресою '$targetUrl'. Переконайтеся, що Ollama запущена ('ollama serve'). Помилка: $msg"
            return $null
        }
    }
    else {
        $targetUrl = "$($cfg.OllamaUrl.TrimEnd('/'))/api/generate"

        $payload = @{
            model      = $targetModel
            prompt     = $Prompt
            stream     = [bool]$Stream
            keep_alive = "1h"
            options    = @{
                temperature = $targetTemp
                num_ctx     = 2048
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
            $payload["system"] = $SystemPrompt
        }

        $bodyJson = $payload | ConvertTo-Json -Depth 6

        try {
            $response = Invoke-RestMethod -Uri $targetUrl `
                -Method Post `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
                -ContentType "application/json; charset=utf-8" `
                -TimeoutSec $cfg.TimeoutSeconds `
                -ErrorAction Stop

            return $response.response
        }
        catch {
            $msg = $_.Exception.Message
            Write-Error " [TerminalAI] Не вдалося з'єднатися з Ollama за адресою '$targetUrl'. Переконайтеся, що Ollama запущена ('ollama serve'). Помилка: $msg"
            return $null
        }
    }
}

function Get-TerminalAiModels {
    [CmdletBinding()]
    param()

    $cfg = Get-TerminalAiConfig
    $url = "$($cfg.OllamaUrl.TrimEnd('/'))/api/tags"

    try {
        $res = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 5 -ErrorAction Stop
        return $res.models
    }
    catch {
        Write-Error " [TerminalAI] Не вдалося отримати список моделей з Ollama ($url): $($_.Exception.Message)"
        return @()
    }
}

function Show-TerminalAiModels {
    [CmdletBinding()]
    param()

    $models = Get-TerminalAiModels
    $cfg = Get-TerminalAiConfig
    $isUk = ($cfg.Language -ne "en")

    if ($models.Count -eq 0) {
        $noModelsMsg = if ($isUk) { " [TerminalAI] Моделей не знайдено або Ollama не запущена." } else { " [TerminalAI] No models found or Ollama is not running." }
        Write-Host $noModelsMsg -ForegroundColor Yellow
        return
    }

    $title = if ($isUk) { "Встановлені моделі Ollama (поточна: $($cfg.Model)):" } else { "Installed Ollama models (active: $($cfg.Model)):" }
    $colCurrent = if ($isUk) { "Поточна" } else { "Active" }
    $colName = if ($isUk) { "Назва" } else { "Name" }
    $colSize = if ($isUk) { "Розмір (GB)" } else { "Size (GB)" }
    $colUpdated = if ($isUk) { "Оновлено" } else { "Updated" }

    Write-Host "`n  $title" -ForegroundColor Cyan
    $models | Select-Object @{Name=$colCurrent; Expression={ if ($_.name -eq $cfg.Model) { "--> *" } else { "   " } }},
                            @{Name=$colName; Expression={$_.name}},
                            @{Name=$colSize; Expression={[Math]::Round($_.size / 1GB, 2)}},
                            @{Name=$colUpdated; Expression={$_.modified_at}} | Format-Table -AutoSize
}

# --- ГОЛОВНІ КОМАНДИ ---

function Show-AiAnswer {
    param(
        [string]$Question,
        [string]$Model
    )

    $cfg = Get-TerminalAiConfig
    $activeModel = if ($Model) { $Model } else { $cfg.Model }
    $langInstruction = if ($cfg.Language -eq "uk") { "Respond strictly in Ukrainian language." } else { "Respond in English." }

    $statusMsg = "$(Get-TerminalAiText 'Answering') $activeModel..."
    Write-Host "`n  ✦ $statusMsg" -ForegroundColor Cyan

    $askSystemPrompt = @"
You are Terminal AI, an expert engineering assistant built for PowerShell and Windows Terminal.
Current Environment: PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) on Windows.
Current AI Extension Settings:
- Active Model: $($cfg.Model)
- Autocomplete Hotkey: $($cfg.HotkeyChord) (replaces line buffer in PSReadLine)
- Ollama URL: $($cfg.OllamaUrl)
- Available cmdlets: Get-TerminalAiConfig, Set-TerminalAiConfig, Show-TerminalAiModels, Show-TerminalAiFonts, Set-TerminalAiFont, Set-TerminalAiLanguage, ai, ai-fix, ai-script.
$langInstruction
Provide a concise, direct, helpful explanation to the user's question.
"@

    $answer = Invoke-OllamaApi -Prompt $Question -SystemPrompt $askSystemPrompt -Model $activeModel -Temperature 0.3
    if ($answer) {
        $cardTitle = Get-TerminalAiText "CardTitleAnswer"
        Write-Host ""
        Write-Host "    ✦ $cardTitle • $activeModel" -ForegroundColor Cyan
        Write-Host ("    " + ("─" * 66)) -ForegroundColor DarkCyan
        foreach ($line in ($answer -split "`r?`n")) {
            Write-Host "    $line" -ForegroundColor White
        }
        Write-Host ("    " + ("─" * 66)) -ForegroundColor DarkCyan
        Write-Host ""
    }
}

function Get-AiSystemPrompt {
    param([bool]$UseAliases = $false)

    $aliasGuide = if ($UseAliases) {
@"
3. Standard Cmdlet Aliases:
   - Use standard short aliases: Get-Process->gps, Where-Object->?, ForEach-Object->%, Select-Object->select, Sort-Object->sort, Measure-Object->measure, Get-ChildItem->gci, Get-Content->gc, Set-Content->sc, Select-String->sls, Get-Service->gsv, Stop-Process->kill, Get-Help->help.
   - NEVER invent aliases for specialized cmdlets: Get-NetTCPConnection, Test-NetConnection, Get-CimInstance, Get-ItemProperty have NO aliases and MUST be written in full.
"@
    } else {
@"
3. Cmdlet Integrity:
   - NEVER hallucinate or invent fake cmdlets.
   - Specialized cmdlets like Get-NetTCPConnection, Test-NetConnection, Get-CimInstance, Get-ItemProperty MUST be written in full.
"@
    }

    return @"
You are an elite PowerShell 7 and Windows Systems engineer.
Target Environment: PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) on Windows.
Goal: Translate the user's natural language request into a single, efficient, idiomatic, robust PowerShell command or pipeline.

Rules:
1. Output ONLY the raw executable PowerShell code without markdown, backticks, or explanations.
2. Robustness & Safety: Never write commands that fail or throw errors when target objects are not present:
   - To find processes listening on ports or active connections, ALWAYS use safe pipeline filtering:
     Get-NetTCPConnection -LocalPort <Port> -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Get-Process -Id `$_.OwningProcess -ErrorAction SilentlyContinue }
     (or with aliases: Get-NetTCPConnection -LocalPort <Port> -State Listen -ea 0 | % { gps -Id `$_.OwningProcess -ea 0 })
   - NEVER write 'Get-Process -Id (Get-NetTCPConnection ...).OwningProcess' because if no process listens on that port, -Id receives null and crashes with 'Cannot bind argument to parameter Id because it is null'!
$aliasGuide
4. Error Handling: Always use -ErrorAction SilentlyContinue (-ea 0) when inspecting dynamic resources like network ports, services, or files that might not exist.
5. If the user asks about the active model, settings, or configuration, return: Get-TerminalAiConfig
6. If the user asks to list installed models, return: Show-TerminalAiModels
"@
}

# --- P0: ДЕТЕРМІНОВАНИЙ AST АНАЛІЗАТОР ТА ОЦІНКА РИЗИКІВ ---

function Test-AiCommandAst {
    <#
    .SYNOPSIS
        Детермінований AST-аналізатор команд PowerShell для безпекової фази P0.
    .DESCRIPTION
        Рекурсивно аналізує рядок коду через PowerShell AST: знаходить усі CommandAst,
        розпізнає командлети, функції, аліаси та зовнішні бінарні файли;
        валідує параметри; виявляє динамічні виклики та splatting; витягує цілі
        та обчислює рівень ризику без виконання коду.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        return [PSCustomObject]@{
            IsValid                  = $false
            ParseErrors              = $parseErrors
            Commands                 = @()
            OverallCategory          = "DynamicOrUnknown"
            OverallRisk              = "High"
            RequiresConfirmation     = $true
            CanPreview               = $false
            PreviewUnavailableReason = "Синтаксична помилка у команді: $($parseErrors[0].Message)"
            Targets                  = @("Unknown target")
            HasDynamicInvocation     = $false
            HasSplatting             = $false
            HasDynamicTarget         = $false
        }
    }

    # Рекурсивний пошук CommandAst
    $commandAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)

    # Пошук динамічних викликів (& $x або Invoke-Expression / iex)
    $dynamicInvocations = $ast.FindAll({
        $node = $args[0]
        ($node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq 'Ampersand') -or
        ($node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @('Invoke-Expression', 'iex')) -or
        ($node -is [System.Management.Automation.Language.CommandAst] -and $node.CommandElements.Count -gt 0 -and $node.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst])
    }, $true)
    $hasDynamicInvocation = ($dynamicInvocations.Count -gt 0)

    # Пошук splatting (@params)
    $splattedVars = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and $args[0].Splatted
    }, $true)
    $hasSplatting = ($splattedVars.Count -gt 0)

    $analyzedCommands = [System.Collections.Generic.List[object]]::new()
    $allTargets = [System.Collections.Generic.List[string]]::new()
    $hasDynamicTarget = $false

    foreach ($cAst in $commandAsts) {
        $rawName = $cAst.GetCommandName()
        $originalName = if ($rawName) { $rawName } else { $cAst.CommandElements[0].Extent.Text }

        $resolvedTarget = $null
        $cmdInfo = $null
        $commandType = "Unknown"
        $category = "DynamicOrUnknown"
        $risk = "Medium"
        $supportsWhatIf = $false
        $invalidParams = [System.Collections.Generic.List[string]]::new()
        $paramsFound = [System.Collections.Generic.List[string]]::new()
        $cmdTargets = [System.Collections.Generic.List[string]]::new()

        if ([string]::IsNullOrWhiteSpace($rawName)) {
            $commandType = "DynamicInvocation"
            $category = "DynamicOrUnknown"
            $risk = "High"
            $hasDynamicInvocation = $true
        } else {
            # Перевіряємо, чи це аліас
            $alias = Get-Alias -Name $rawName -ErrorAction SilentlyContinue
            if ($alias) {
                $commandType = "Alias"
                $resolvedTarget = $alias.Definition
                $effectiveName = $resolvedTarget
                $cmdInfo = Get-Command -Name $resolvedTarget -ErrorAction SilentlyContinue
            } else {
                $effectiveName = $rawName
                $cmdInfo = Get-Command -Name $rawName -ErrorAction SilentlyContinue
            }

            if ($cmdInfo) {
                if ($cmdInfo.CommandType -in @('Cmdlet', 'Function', 'Filter', 'Script')) {
                    if ($commandType -ne "Alias") { $commandType = $cmdInfo.CommandType.ToString() }
                    $resolvedTarget = $cmdInfo.Name

                    # Перевіряємо WhatIf
                    if ($cmdInfo.Parameters.ContainsKey('WhatIf')) {
                        $supportsWhatIf = $true
                    } elseif ($cmdInfo.ImplementingType) {
                        try {
                            $cmdAttr = [System.Management.Automation.CmdletAttribute][Attribute]::GetCustomAttribute(
                                $cmdInfo.ImplementingType, [System.Management.Automation.CmdletAttribute]
                            )
                            if ($cmdAttr -and $cmdAttr.SupportsShouldProcess) {
                                $supportsWhatIf = $true
                            }
                        } catch { }
                    }
                } elseif ($cmdInfo.CommandType -eq 'Application') {
                    $commandType = "ExternalProgram"
                    $resolvedTarget = $cmdInfo.Source
                    $category = "ExternalProgram"
                    $risk = "Medium"
                    $supportsWhatIf = $false
                }
            } else {
                $commandType = "Unknown"
                $category = "DynamicOrUnknown"
                $risk = "High"
            }
        }

        # Аналіз параметрів
        $paramAsts = $cAst.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandParameterAst] }, $false)
        foreach ($p in $paramAsts) {
            $pName = $p.ParameterName
            $paramsFound.Add($pName)
            if ($cmdInfo -and $cmdInfo.Parameters) {
                $commonParams = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm')
                $known = $cmdInfo.Parameters.ContainsKey($pName) -or ($commonParams -contains $pName)
                if (-not $known) {
                    $matchedPrefix = $cmdInfo.Parameters.Keys | Where-Object { $_.StartsWith($pName, [System.StringComparison]::OrdinalIgnoreCase) }
                    if (-not $matchedPrefix) {
                        $matchedPrefix = $commonParams | Where-Object { $_.StartsWith($pName, [System.StringComparison]::OrdinalIgnoreCase) }
                    }
                    if ($matchedPrefix) { $known = $true }
                }
                if (-not $known) {
                    $invalidParams.Add($pName)
                }
            }
        }

        # Витягнення аргументів та цілей
        for ($i = 1; $i -lt $cAst.CommandElements.Count; $i++) {
            $elem = $cAst.CommandElements[$i]
            if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                continue
            }
            if ($elem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $val = $elem.Value
                if (-not [string]::IsNullOrWhiteSpace($val) -and $val -notmatch '^-') {
                    $cmdTargets.Add($val)
                    if (-not $allTargets.Contains($val)) { $allTargets.Add($val) }
                }
            } elseif ($elem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                $val = $elem.Extent.Text.Trim('"', "'")
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $cmdTargets.Add($val)
                    if (-not $allTargets.Contains($val)) { $allTargets.Add($val) }
                }
            } elseif ($elem -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $cmdTargets.Add("Unknown target")
                $hasDynamicTarget = $true
                if (-not $allTargets.Contains("Unknown target")) { $allTargets.Add("Unknown target") }
            } elseif ($elem -is [System.Management.Automation.Language.SubExpressionAst] -or $elem -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $cmdTargets.Add("Unknown target")
                $hasDynamicTarget = $true
                if (-not $allTargets.Contains("Unknown target")) { $allTargets.Add("Unknown target") }
            }
        }

        # Класифікація категорій та ризику для Cmdlet/Function/Unknown
        $eff = if ($resolvedTarget) { $resolvedTarget } else { $originalName }

        if ($commandType -eq "ExternalProgram") {
            $category = "ExternalProgram"
            if ($eff -match '^(?:rm|del|erase|format|fdisk|dd|diskpart|mkfs)$') {
                $risk = "High"
                $category = "Deletion"
            } else {
                $risk = "Medium"
            }
        } elseif ($commandType -eq "Unknown") {
            $category = "DynamicOrUnknown"
            $risk = "High"
        } else {
            # Аналіз префіксів/дієслів та імен
            if ($eff -match '^(?:Remove-|Clear-|Reset-)') {
                $category = "Deletion"
                $risk = "High"
            } elseif ($eff -match '^(?:Stop-Process|kill|Stop-Service|Restart-Service|Suspend-Service|Set-Service)') {
                $category = "ServiceOrProcess"
                $risk = "High"
            } elseif ($eff -match '^(?:Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|Clear-ItemProperty)' -or
                      ($eff -match '^(?:Get-ItemProperty|New-Item|Remove-Item|Set-Item)' -and ($Command -match '(?i)\b(?:HKCU:|HKLM:|HKCR:|HKU:|HKCC:|Registry::)'))) {
                $category = "Registry"
                $risk = "High"
            } elseif ($eff -match '(?i)(?:-Disk\b|-Partition\b|-Volume\b|Format-Volume|Initialize-Disk|Clear-Disk)') {
                $category = "DiskOrPartition"
                $risk = "Critical"
            } elseif ($eff -match '(?i)^(?:Set-Net|New-Net|Remove-Net|Disable-Net|Enable-Net|Rename-Net)') {
                $category = "NetworkChange"
                $risk = "High"
            } elseif ($eff -match '(?i)^(?:Set-|New-|Add-|Register-|Unregister-|Install-|Uninstall-|Enable-|Disable-|Grant-|Revoke-)') {
                $category = "SystemChange"
                $risk = "Medium"
            } elseif ($eff -match '(?i)^(?:Get-|Select-|Where-|ForEach-|Measure-|Sort-|Out-|Format-|Export-|Test-|Show-|Find-|Read-|Compare-|Group-)') {
                $category = "ReadOnly"
                $risk = "Low"
            } else {
                $category = "DynamicOrUnknown"
                $risk = "Medium"
            }
        }

        if ($invalidParams.Count -gt 0 -and $risk -eq "Low") {
            $risk = "Medium"
        }

        $analyzedCommands.Add([PSCustomObject]@{
            OriginalName      = $originalName
            CommandName       = $eff
            ResolvedTarget    = $resolvedTarget
            CommandType       = $commandType
            Category          = $category
            Risk              = $risk
            SupportsWhatIf    = $supportsWhatIf
            Parameters        = @($paramsFound)
            InvalidParameters = @($invalidParams)
            Targets           = @($cmdTargets)
        })
    }

    $categoryOrder = @("DiskOrPartition", "Deletion", "Registry", "ServiceOrProcess", "NetworkChange", "DynamicOrUnknown", "ExternalProgram", "SystemChange", "ReadOnly")
    $overallCat = "ReadOnly"
    foreach ($cat in $categoryOrder) {
        if ($analyzedCommands | Where-Object { $_.Category -eq $cat }) {
            $overallCat = $cat
            break
        }
    }

    $riskOrder = @("Critical", "High", "Medium", "Low")
    $overallRisk = "Low"
    foreach ($r in $riskOrder) {
        if ($analyzedCommands | Where-Object { $_.Risk -eq $r }) {
            $overallRisk = $r
            break
        }
    }
    if ($hasDynamicInvocation -and $overallRisk -in @("Low", "Medium")) {
        $overallRisk = "High"
        $overallCat = "DynamicOrUnknown"
    }

    $requiresConfirm = ($overallRisk -in @("High", "Critical", "Unknown"))
    if ($hasDynamicInvocation) { $requiresConfirm = $true }

    $allWhatIf = $true
    foreach ($c in $analyzedCommands) {
        if ($c.Category -ne "ReadOnly" -and -not $c.SupportsWhatIf) {
            $allWhatIf = $false
            break
        }
    }

    $canPreview = $allWhatIf
    $previewReason = if ($canPreview) {
        $null
    } else {
        if ($analyzedCommands | Where-Object { $_.CommandType -eq "ExternalProgram" }) {
            "Безпечний попередній перегляд (-WhatIf) недоступний для зовнішніх бінарних програм"
        } else {
            "Безпечний попередній перегляд (-WhatIf) не підтримується однією або кількома командами"
        }
    }

    if ($allTargets.Count -eq 0) {
        $allTargets.Add("Unknown target")
    }

    return [PSCustomObject]@{
        IsValid                  = $true
        ParseErrors              = @()
        Commands                 = @($analyzedCommands)
        OverallCategory          = $overallCat
        OverallRisk              = $overallRisk
        RequiresConfirmation     = $requiresConfirm
        CanPreview               = $canPreview
        PreviewUnavailableReason = $previewReason
        Targets                  = @($allTargets)
        HasDynamicInvocation     = $hasDynamicInvocation
        HasSplatting             = $hasSplatting
        HasDynamicTarget         = $hasDynamicTarget
    }
}

function Invoke-AiExecutionGate {
    <#
    .SYNOPSIS
        Єдина безпекова точка входу для виконання команд PowerShell у TerminalAI.
    .DESCRIPTION
        Аналізує команду через Test-AiCommandAst.
        1. Блокує виконання при синтаксичних помилках.
        2. Відображає картку безпеки для операцій з високим/критичним/невідомим ризиком,
           динамічними викликами або невідомими цілями.
        3. Вимагає явного підтвердження користувача навіть при прапорці -AutoConfirm/-Execute,
           якщо операція становить потенційну небезпеку.
        4. Дозволяє автоматичний запуск лише для перевірених низькоризикових команд з -AutoConfirm.
        5. Підтримує вивід через Out-Default або повернення результатів (-ReturnOutput).
    .PARAMETER Command
        Рядок команди PowerShell для перевірки та виконання.
    .PARAMETER AutoConfirm
        Автоматичне підтвердження виконання для низькоризикових операцій.
        Для High/Critical/Unknown підтвердження все одно вимагається інтерактивно.
    .PARAMETER ReturnOutput
        Повернути вивід команди (stdout/stderr) замість відправки в Out-Default.
    .PARAMETER ConfirmInput
        Опціональна відповідь для емуляції вводу підтвердження ('y'/'n'), використовується в тестах та автоматизації.
    .PARAMETER PassThru
        Повернути детальний об'єкт звіту виконання [PSCustomObject] з результатами аналізу та статусом.
    .PARAMETER SkipAstAnalysis
        Пропустити AST-аналіз (лише для виняткових внутрішніх викликів).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command,

        [Parameter()]
        [switch]$AutoConfirm,

        [Parameter()]
        [switch]$ReturnOutput,

        [Parameter()]
        [string]$ConfirmInput,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [switch]$Preview,

        [Parameter()]
        [switch]$SkipAstAnalysis
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        if ($PassThru) {
            return [PSCustomObject]@{
                Executed = $false
                Status   = "EmptyCommand"
                Command  = $Command
                Analysis = $null
                Output   = $null
            }
        }
        return $null
    }

    $analysis = $null
    if (-not $SkipAstAnalysis) {
        $analysis = Test-AiCommandAst -Command $Command

        # 1. Синтаксична перевірка: блокування при наявності помилок парсера
        if (-not $analysis.IsValid -or ($analysis.ParseErrors -and $analysis.ParseErrors.Count -gt 0)) {
            Write-Host ""
            Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
            Write-Host "    │          ✖  TERMINAL AI SECURITY GATE: SYNTAX ERROR         │" -ForegroundColor Red
            Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
            Write-Host "    Command execution BLOCKED due to syntax errors:" -ForegroundColor DarkYellow
            foreach ($err in $analysis.ParseErrors) {
                $lineNum = if ($err.Extent) { $err.Extent.StartLineNumber } else { 1 }
                $colNum = if ($err.Extent) { $err.Extent.StartColumnNumber } else { 1 }
                Write-Host "      • Line $lineNum, Col $($colNum): $($err.Message)" -ForegroundColor Red
            }
            Write-Host ""

            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $false
                    Status   = "SyntaxError"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $null
                }
            }
            return $null
        }
    }

    # 2. Попередній перегляд / WhatIf режим
    $isWhatIf = $Preview -or ($PSBoundParameters.ContainsKey('WhatIf') -and $PSBoundParameters['WhatIf'])
    if ($isWhatIf) {
        if (-not $analysis.CanPreview) {
            $reason = if ($analysis.PreviewUnavailableReason) { $analysis.PreviewUnavailableReason } else { "WhatIf preview is not supported for this command." }
            Write-Host ""
            Write-Host "    ⚠ [Preview Unavailable] $reason" -ForegroundColor DarkYellow
            Write-Host "      Command contains external binaries or operations without SupportsShouldProcess." -ForegroundColor DarkGray
            Write-Host ""
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $false
                    Status   = "PreviewUnavailable"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $null
                }
            }
            return $null
        }

        Write-Host "    🔍 [WhatIf Preview] Running command in safe simulation mode..." -ForegroundColor Cyan
        try {
            $sb = [ScriptBlock]::Create($Command)
            if ($ReturnOutput) {
                $output = & {
                    $WhatIfPreference = $true
                    . $sb
                } 2>&1
                if ($PassThru) {
                    return [PSCustomObject]@{
                        Executed = $true
                        Status   = "Previewed"
                        Command  = $Command
                        Analysis = $analysis
                        Output   = $output
                    }
                }
                return $output
            } else {
                & {
                    $WhatIfPreference = $true
                    . $sb
                } | Out-Default
                if ($PassThru) {
                    return [PSCustomObject]@{
                        Executed = $true
                        Status   = "Previewed"
                        Command  = $Command
                        Analysis = $analysis
                        Output   = $null
                    }
                }
            }
            return $null
        } catch {
            Write-Error $_
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $false
                    Status   = "ExecutionError"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $_
                }
            }
            if ($ReturnOutput) { return $_ }
            return $null
        }
    }

    # 3. Перевірка небезпеки
    $isDangerous = $false
    if ($analysis) {
        $isDangerous = $analysis.RequiresConfirmation -or ($analysis.OverallRisk -in @("High", "Critical", "Unknown"))
    }

    # Визначення, чи потрібне підтвердження
    $needsPrompt = $true
    if (-not $isDangerous -and $AutoConfirm) {
        # Низький ризик + AutoConfirm -> пряме виконання
        $needsPrompt = $false
    }

    if ($needsPrompt) {
        # Формування та відображення картки безпеки
        $risk = if ($analysis) { $analysis.OverallRisk } else { "Unknown" }
        $category = if ($analysis) { $analysis.OverallCategory } else { "Unknown" }
        $targets = if ($analysis -and $analysis.Targets) { $analysis.Targets } else { @() }

        $headerColor = switch ($risk) {
            'Critical' { 'Red' }
            'High'     { 'Red' }
            'Medium'   { 'Yellow' }
            default    { 'Cyan' }
        }

        Write-Host ""
        Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor $headerColor
        Write-Host "    │               ⚠  TERMINAL AI SECURITY GATE  ⚠               │" -ForegroundColor $headerColor
        Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor $headerColor
        Write-Host "    Command:  " -NoNewline -ForegroundColor White
        Write-Host $Command -ForegroundColor Cyan
        Write-Host "    Category: " -NoNewline -ForegroundColor White
        Write-Host $category -ForegroundColor Yellow
        Write-Host "    Risk:     " -NoNewline -ForegroundColor White
        Write-Host $risk -ForegroundColor $headerColor

        if ($targets.Count -gt 0) {
            Write-Host "    Targets:  " -NoNewline -ForegroundColor White
            Write-Host ($targets -join ", ") -ForegroundColor Magenta
        }

        # Збір причин ризику
        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($analysis) {
            if ($analysis.HasDynamicInvocation) {
                $reasons.Add("Dynamic command invocation detected (& `$var, Invoke-Expression, iex)")
            }
            if ($analysis.HasDynamicTarget) {
                $reasons.Add("Dynamic or unresolved target (variable/expression in arguments)")
            }
            if ($analysis.HasSplatting) {
                $reasons.Add("Parameter splatting detected (@params)")
            }
            foreach ($cmd in $analysis.Commands) {
                if ($cmd.InvalidParameters -and $cmd.InvalidParameters.Count -gt 0) {
                    $reasons.Add("Unknown parameter(s) for $($cmd.CommandName): $($cmd.InvalidParameters -join ', ')")
                }
                if ($cmd.Category -in @("Deletion", "DiskOrPartition", "Registry", "NetworkChange", "ServiceOrProcess")) {
                    $reasons.Add("Operation category '$($cmd.Category)' modifies system state ($($cmd.CommandName))")
                }
            }
        }
        if ($reasons.Count -gt 0) {
            Write-Host "    Reasons:" -ForegroundColor White
            foreach ($r in $reasons) {
                Write-Host "      • $r" -ForegroundColor DarkYellow
            }
        }

        # Запит підтвердження
        $promptDefault = if ($risk -in @("High", "Critical", "Unknown")) { "y/N" } else { "Y/n" }
        $promptText = "    Execute this command? [$promptDefault]: "

        $confirmed = $false
        if ($PSBoundParameters.ContainsKey('ConfirmInput')) {
            $response = $ConfirmInput
        } else {
            try {
                $isInteractive = [Environment]::UserInteractive
                if ([Console]::IsInputRedirected) { $isInteractive = $false }
            } catch {
                $isInteractive = $true
            }

            if (-not $isInteractive) {
                Write-Host "    ✖ Non-interactive host detected. Unconfirmed command blocked." -ForegroundColor Red
                if ($PassThru) {
                    return [PSCustomObject]@{
                        Executed = $false
                        Status   = "BlockedNonInteractive"
                        Command  = $Command
                        Analysis = $analysis
                        Output   = $null
                    }
                }
                return $null
            }

            $response = Read-Host -Prompt $promptText
        }

        if ($risk -in @("High", "Critical", "Unknown")) {
            if ($response -match '^(y|yes|так|т)$') {
                $confirmed = $true
            }
        } else {
            if ([string]::IsNullOrWhiteSpace($response) -or $response -match '^(y|yes|так|т)$') {
                $confirmed = $true
            }
        }

        if (-not $confirmed) {
            Write-Host "    ✖ Execution canceled by user." -ForegroundColor DarkGray
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $false
                    Status   = "Denied"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $null
                }
            }
            return $null
        }
    }

    # 3. Виконання команди
    try {
        $sb = [ScriptBlock]::Create($Command)
        if ($ReturnOutput) {
            $output = . $sb 2>&1
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $true
                    Status   = "Executed"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $output
                }
            }
            return $output
        } else {
            . $sb | Out-Default
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $true
                    Status   = "Executed"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $null
                }
            }
        }
    } catch {
        Write-Error $_
        if ($PassThru) {
            return [PSCustomObject]@{
                Executed = $false
                Status   = "ExecutionError"
                Command  = $Command
                Analysis = $analysis
                Output   = $_
            }
        }
        if ($ReturnOutput) {
            return $_
        }
    }
}

function Invoke-AiCommand {
    <#
    .SYNOPSIS
        Генерує команду PowerShell за описом природною мовою через локальну Ollama.
    .DESCRIPTION
        Приймає запит українською або англійською, генерує команду PowerShell,
        пропонує варіанти: виконати, скопіювати, вставити у буфер, пояснити або скасувати.
        Підтримує навчальні підкоманди: ai help, ai help shortcuts, ai help models,
        ai help examples, ai help workflow, ai help config, ai status, ai models.
    .PARAMETER Prompt
        Текстовий запит природною мовою або системна підкоманда (help, status, models, model, lang, config).
    .PARAMETER Execute
        Виконати згенеровану команду негайно без інтерактивного меню (аліаси: -x, -y).
    .PARAMETER Copy
        Скопіювати згенеровану команду безпосередньо в системний буфер обміну (аліас: -c).
    .PARAMETER Alias
        Використовувати стандартні короткі аліаси PowerShell (gps, gci, select, ?, %) замість повних назв (аліаси: -a, -Short, -UseAliases).
    .PARAMETER Explain
        Згенерувати структуроване навчальне пояснення синтаксису, параметрів та безпеки.
    .PARAMETER Ask
        Поставити концептуальне або практичне питання та отримати пряму текстову відповідь замість коду.
    .PARAMETER Model
        Перевизначити активну модель Ollama для поточного виклику.
    .EXAMPLE
        ai знайти всі файли більше 100MB у поточній папці
    .EXAMPLE
        ai "знайти процес на порті 8080" -a
    .EXAMPLE
        ai help shortcuts
    .EXAMPLE
        ai "знайти процес на порті 8080" -Explain
    .EXAMPLE
        ai "перевірити DNS резолв google.com" -x
    .EXAMPLE
        ?? порахуй кількість рядків у всіх ps1 файлах
    #>
    [CmdletBinding()]
    [Alias("ai", "??")]
    param(
        [Parameter(Position = 0, Mandatory = $false, ValueFromRemainingArguments = $true)]
        [string[]]$Prompt,

        [Alias("x", "y")]
        [switch]$Execute,

        [Alias("c")]
        [switch]$Copy,

        [Alias("a", "Short", "UseAliases")]
        [switch]$Alias,

        [switch]$Explain,

        [Alias("chat", "question")]
        [switch]$Ask,

        [Alias("w", "WhatIf")]
        [switch]$Preview,

        [string]$Model
    )

    $cfg = Get-TerminalAiConfig
    $fullPrompt = if ($Prompt) { ($Prompt -join " ").Trim() } else { "" }
    $isUk = ($cfg.Language -ne "en")

    if ([string]::IsNullOrWhiteSpace($fullPrompt)) {
        Write-Host ""
        if ($isUk) {
            Write-Host "    ✦ Terminal AI • Швидка довідка та аліаси" -ForegroundColor Cyan
            Write-Host "    ╭────────────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Основні команди та аліаси:                                           │" -ForegroundColor Cyan
            Write-Host "    │     aif <запит>   або  ai-fast <запит>    (швидкий бінарний модуль C#) │" -ForegroundColor White
            Write-Host "    │     ?? <запит>    або  ai <запит>         (стандартний модуль)         │" -ForegroundColor White
            Write-Host "    │     F2                                    (інлайн-генерація в консолі) │" -ForegroundColor Yellow
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Швидкі підкоманди та скорочення:                                     │" -ForegroundColor Cyan
            Write-Host "    │     ai help [тема]або  aif help [тема]    (навчальна довідка й поради) │" -ForegroundColor Green
            Write-Host "    │     ai status     або  aif status         (стан системи, модель, мова) │" -ForegroundColor Green
            Write-Host "    │     ai alias [on] або  aif alias [on|off] (режим коротких аліасів)     │" -ForegroundColor Green
            Write-Host "    │     ai models     |  aif -m               (список моделей Ollama)      │" -ForegroundColor Green
            Write-Host "    │     ai model <назва>                      (змінити активну модель)     │" -ForegroundColor Green
            Write-Host "    │     ai lang en | uk                       (перемкнути мову інтерфейсу) │" -ForegroundColor Green
            Write-Host "    │     ai config     |  aif -c               (переглянути config.json)    │" -ForegroundColor Green
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Короткі ключі (прапорці):                                            │" -ForegroundColor Cyan
            Write-Host "    │     ai `"cmd`" -x   або  aif `"cmd`" -x       (виконати команду відразу)   │" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -c   або  aif `"cmd`" -c       (скопіювати в буфер обміну)  │" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -a   або  aif `"cmd`" -a       (короткі аліаси: gps, gci, ?)│" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -Explain                   (генерація з розбором коду)  │" -ForegroundColor Magenta
            Write-Host "    │     ai `"cmd`" -Ask                       (пряма текстова відповідь)   │" -ForegroundColor Blue
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    ╰────────────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        } else {
            Write-Host "    ✦ Terminal AI • Quick Reference & Shortcuts" -ForegroundColor Cyan
            Write-Host "    ╭────────────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Primary Commands & Aliases:                                          │" -ForegroundColor Cyan
            Write-Host "    │     aif <prompt>  or  ai-fast <prompt>    (ultra-fast C# AOT module)   │" -ForegroundColor White
            Write-Host "    │     ?? <prompt>   or  ai <prompt>         (standard PowerShell module) │" -ForegroundColor White
            Write-Host "    │     F2                                    (inline generation in term)  │" -ForegroundColor Yellow
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Short Commands & Subcommands:                                        │" -ForegroundColor Cyan
            Write-Host "    │     ai help [top] or  aif help [topic]    (learning guide & cheatsheet)│" -ForegroundColor Green
            Write-Host "    │     ai status     or  aif status          (system information & model) │" -ForegroundColor Green
            Write-Host "    │     ai alias [on] or  aif alias [on|off]  (short command aliases mode) │" -ForegroundColor Green
            Write-Host "    │     ai models     |  aif -m               (list installed models)      │" -ForegroundColor Green
            Write-Host "    │     ai model <name>                       (switch active Ollama model) │" -ForegroundColor Green
            Write-Host "    │     ai lang en | uk                       (switch interface language)  │" -ForegroundColor Green
            Write-Host "    │     ai config     |  aif -c               (view configuration JSON)    │" -ForegroundColor Green
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Short Flags & Execution:                                             │" -ForegroundColor Cyan
            Write-Host "    │     ai `"cmd`" -x   or  aif `"cmd`" -x        (execute immediately)        │" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -c   or  aif `"cmd`" -c        (copy to clipboard)          │" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -a   or  aif `"cmd`" -a        (short aliases: gps, gci, ?) │" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -Explain                   (generate with explanation)  │" -ForegroundColor Magenta
            Write-Host "    │     ai `"cmd`" -Ask                       (direct educational answer)  │" -ForegroundColor Blue
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    ╰────────────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        }

        Write-Host ""
        return
    }

    $activeModel = if ($Model) { $Model } else { $cfg.Model }

    # 0. Довідка та навчальні посібники: ai help [topic]
    if ($fullPrompt -match '^(?:help|довідка|допомога)(?:\s+(all|shortcuts|models|examples|workflow|config))?\s*$') {
        $topic = if ($Matches[1]) { $Matches[1].Trim().ToLowerInvariant() } else { "all" }
        Show-TerminalAiHelp -Topic $topic
        return
    }

    if ($fullPrompt -in @("shortcuts", "гарячі клавіші", "клавіші")) {
        Show-TerminalAiHelp -Topic "shortcuts"
        return
    }

    if ($fullPrompt -in @("examples", "приклади")) {
        Show-TerminalAiHelp -Topic "examples"
        return
    }

    if ($fullPrompt -in @("workflow", "робота")) {
        Show-TerminalAiHelp -Topic "workflow"
        return
    }

    # 1. Шрифти: виведення списку та зміна
    if ($fullPrompt -in @("fonts", "font", "--fonts", "--font", "-f", "шрифти", "шрифт")) {
        Show-TerminalAiFonts
        return
    }

    if ($fullPrompt -match '^(?:set-font|use-font|font|шрифт)\s+(.+)$') {
        $fontArg = $Matches[1].Trim().Trim('"').Trim("'")
        $fontSize = 0
        if ($fontArg -match '^(?<font>.+?)\s+(?<size>\d{1,2})$') {
            $fontName = $Matches['font'].Trim().Trim('"').Trim("'")
            $fontSize = [int]$Matches['size']
            Set-TerminalAiFont -Font $fontName -Size $fontSize
        } else {
            Set-TerminalAiFont -Font $fontArg
        }
        return
    }

    # 2. Мова: статус та перемикання
    if ($fullPrompt -in @("lang", "language", "--lang", "-l", "мова")) {
        Write-Host ""
        if ($cfg.Language -eq "en") {
            Write-Host "    ✦ Current language: en (English)" -ForegroundColor Cyan
            Write-Host "    💡 Switch language:  ai lang uk  |  ai lang en" -ForegroundColor DarkGray
            Write-Host "    💡 Set permanent:    ai lang permanent uk  |  ai lang permanent en`n" -ForegroundColor DarkGray
        } else {
            Write-Host "    ✦ Поточна мова: uk (Українська)" -ForegroundColor Cyan
            Write-Host "    💡 Змінити мову:     ai lang en  |  ai lang uk" -ForegroundColor DarkGray
            Write-Host "    💡 Зробити постійною: ai lang permanent en  |  ai lang permanent uk`n" -ForegroundColor DarkGray
        }
        return
    }

    # Постійне перемикання мови (ai lang permanent uk або ai lang uk permanent)
    if ($fullPrompt -match '^(?:set-lang|lang|language|мова)\s+(?:permanent|save|default|--permanent|-p|постійно)\s+(uk|ua|en)$' -or
        $fullPrompt -match '^(?:set-lang|lang|language|мова)\s+(uk|ua|en)\s+(?:permanent|save|default|--permanent|-p|постійно)$' -or
        $fullPrompt -match '^(?:lang-permanent|default-lang|set-default-lang)\s+(uk|ua|en)$') {
        $newLang = $Matches[1].ToLower()
        Set-TerminalAiLanguage -Language $newLang -Permanent
        return
    }

    if ($fullPrompt -match '^(?:set-lang|lang|language|мова)\s+(uk|ua|en)$') {
        $newLang = $Matches[1].ToLower()
        Set-TerminalAiLanguage -Language $newLang -Permanent
        return
    }

    # 3. Інформація про систему / активну модель / шрифт
    if ($fullPrompt -match '^(?:which|what)\s+model|яка\s+модель|яку\s+модель|current\s+model|status|info|інфо|статус|який\s+шрифт|which\s+font') {
        $fontInfo = Get-TerminalAiFonts
        $activeFontDisplay = if ($fontInfo.ActiveFont) { $fontInfo.ActiveFont } else { "Default" }

        $title = if ($isUk) { "Інформація про систему" } else { "System Information" }
        $lblModel = if ($isUk) { "Активна модель:" } else { "Active Model:" }
        $lblFont = if ($isUk) { "Шрифт терміналу:" } else { "Terminal Font:" }
        $lblServer = if ($isUk) { "Локальний сервер:" } else { "Local Server:" }
        $lblHotkey = if ($isUk) { "Швидке доповнення:" } else { "Quick Inline:" }
        $lblLang = if ($isUk) { "Основна мова:" } else { "Language:" }
        $hintModel = if ($isUk) { "Змінити модель:  ai model <назва>" } else { "Change model:  ai model <name>" }
        $hintFont = if ($isUk) { "Змінити шрифт:   ai font <назва>" } else { "Change font:   ai font <name>" }
        $hintLang = if ($isUk) { "Змінити мову:    ai lang uk | en" } else { "Change lang:   ai lang en | uk" }

        Write-Host ""
        Write-Host "    ✦ Terminal AI • $title" -ForegroundColor Cyan
        Write-Host "    ╭──────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
        Write-Host "    │                                                                  │" -ForegroundColor DarkCyan

        $renderRow = {
            param([string]$Label, [string]$Value, [System.ConsoleColor]$ValueColor)
            if ($Label.Length -gt 22) { $Label = $Label.Substring(0, 22) }
            if ($Value.Length -gt 38) { $Value = $Value.Substring(0, 35) + "..." }
            Write-Host "    │   " -NoNewline -ForegroundColor DarkCyan
            Write-Host ("{0,-22}" -f $Label) -NoNewline -ForegroundColor DarkCyan
            Write-Host ("{0,-38}" -f $Value) -NoNewline -ForegroundColor $ValueColor
            Write-Host "   │" -ForegroundColor DarkCyan
        }

        & $renderRow $lblModel $cfg.Model ([System.ConsoleColor]::Green)
        & $renderRow $lblFont $activeFontDisplay ([System.ConsoleColor]::Cyan)
        & $renderRow $lblServer $cfg.OllamaUrl ([System.ConsoleColor]::White)
        $hkText = if ($isUk) { "$($cfg.HotkeyChord) / F2 (інлайн)" } else { "$($cfg.HotkeyChord) / F2 (inline)" }
        & $renderRow $lblHotkey $hkText ([System.ConsoleColor]::Yellow)
        $langDisplay = if ($cfg.Language -eq "en") { "en (English)" } else { "uk (Українська)" }
        & $renderRow $lblLang $langDisplay ([System.ConsoleColor]::White)
        $lblAlias = if ($isUk) { "Короткі аліаси:" } else { "Command Aliases:" }
        $aliasDisplay = if ($cfg.UseAliases) {
            if ($isUk) { "Увімкнено (gps, gci, ?)" } else { "Enabled (gps, gci, ?)" }
        } else {
            if ($isUk) { "Вимкнено (повні назви)" } else { "Disabled (full cmdlets)" }
        }
        $aliasColor = if ($cfg.UseAliases) { [System.ConsoleColor]::Green } else { [System.ConsoleColor]::DarkGray }
        & $renderRow $lblAlias $aliasDisplay $aliasColor

        Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
        Write-Host "    ╰──────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "    💡 $hintModel" -ForegroundColor DarkGray
        Write-Host "    💡 $hintFont" -ForegroundColor DarkGray
        $hintAlias = if ($isUk) { "Аліаси команд:  ai alias on | off" } else { "Command aliases: ai alias on | off" }
        Write-Host "    💡 $hintAlias" -ForegroundColor DarkGray
        Write-Host "    💡 $hintLang`n" -ForegroundColor DarkGray
        return
    }

    if ($fullPrompt -match '^(?:set-model|use-model|use|model)\s+([A-Za-z0-9.:_\-\/]+)$') {
        $newModel = $Matches[1].Trim()
        Set-TerminalAiConfig -Model $newModel | Out-Null
        $msg = if ($cfg.Language -eq "en") { "Active model successfully changed to '$newModel'!" } else { "Активну модель успішно змінено на '$newModel'!" }
        Write-Host "`n    ✔ $msg`n" -ForegroundColor Green
        return
    }

    if ($fullPrompt -in @("models", "--models", "-m")) {
        Show-TerminalAiModels
        return
    }

    if ($fullPrompt -in @("config", "--config", "-c")) {
        Get-TerminalAiConfig
        return
    }

    # 4. Керування режимом коротких аліасів (ai alias [on|off] або ai use-aliases)
    if ($fullPrompt -match '^(?:alias|aliases|аліас|аліаси)\s+(?:on|1|true|enable|увімк|увімкнути)$' -or
        $fullPrompt -in @("use-aliases", "use aliases", "використовувати аліаси", "увімкнути аліаси")) {
        Set-TerminalAiConfig -UseAliases $true | Out-Null
        $msg = if ($cfg.Language -eq "en") { "PowerShell short aliases mode successfully ENABLED (defaulting to: gps, gci, select, ?, %)" } else { "Режим коротких аліасів PowerShell успішно УВІМКНЕНО (за замовчуванням: gps, gci, select, ?, %)" }
        Write-Host "`n    ✔ $msg`n" -ForegroundColor Green
        return
    }

    if ($fullPrompt -match '^(?:alias|aliases|аліас|аліаси)\s+(?:off|0|false|disable|вимк|вимкнути)$' -or
        $fullPrompt -in @("no-aliases", "no aliases", "не використовувати аліаси", "вимкнути аліаси")) {
        Set-TerminalAiConfig -UseAliases $false | Out-Null
        $msg = if ($cfg.Language -eq "en") { "PowerShell short aliases mode DISABLED (using full cmdlet names)" } else { "Режим коротких аліасів PowerShell ВИМКНЕНО (використовуються повні імена командлетів)" }
        Write-Host "`n    ✔ $msg`n" -ForegroundColor Green
        return
    }

    if ($fullPrompt -in @("alias", "aliases", "аліас", "аліаси")) {
        Write-Host ""
        if ($cfg.UseAliases) {
            $aliasStatus = if ($isUk) { "УВІМКНЕНО" } else { "ENABLED" }
            $aliasColor = [System.ConsoleColor]::Green
        } else {
            $aliasStatus = if ($isUk) { "ВИМКНЕНО" } else { "DISABLED" }
            $aliasColor = [System.ConsoleColor]::DarkGray
        }
        if ($isUk) {
            Write-Host "    ✦ Режим коротких аліасів PowerShell: " -NoNewline -ForegroundColor Cyan
            Write-Host $aliasStatus -ForegroundColor $aliasColor
            Write-Host "    💡 Увімкнути:  ai alias on   |  aif alias on" -ForegroundColor DarkGray
            Write-Host "    💡 Вимкнути:   ai alias off  |  aif alias off`n" -ForegroundColor DarkGray
        } else {
            Write-Host "    ✦ PowerShell short aliases mode: " -NoNewline -ForegroundColor Cyan
            Write-Host $aliasStatus -ForegroundColor $aliasColor
            Write-Host "    💡 Enable:     ai alias on   |  aif alias on" -ForegroundColor DarkGray
            Write-Host "    💡 Disable:    ai alias off  |  aif alias off`n" -ForegroundColor DarkGray
        }
        return
    }

    # 4. Якщо явно запитано текстову відповідь (-Ask)
    if ($Ask) {
        Show-AiAnswer -Question $fullPrompt -Model $activeModel
        return
    }

    # 5. Підготовка параметрів та аліасів
    $preferAliases = [bool]($Alias.IsPresent -or $cfg.UseAliases)
    if ($fullPrompt -match '(?:\s*[\(\[]?\s*(?:використовувати|використовуй|з|зі)\s+аліас(?:ами|и)?\s*[\)\]]?|\s*[\(\[]?\s*(?:use|with)\s+alias(?:es)?\s*[\)\]]?|\s*[\(\[]?\s*скорочен(?:і|ними|ими)\s+команд(?:ами|и)?\s*[\)\]]?)$') {
        $preferAliases = $true
        $fullPrompt = ($fullPrompt -replace '(?:\s*[\(\[]?\s*(?:використовувати|використовуй|з|зі)\s+аліас(?:ами|и)?\s*[\)\]]?|\s*[\(\[]?\s*(?:use|with)\s+alias(?:es)?\s*[\)\]]?|\s*[\(\[]?\s*скорочен(?:і|ними|ими)\s+команд(?:ами|и)?\s*[\)\]]?)$', '').Trim()
    }

    Write-Host "`n  ✦ $(Get-TerminalAiText 'Connecting') ($activeModel)..." -ForegroundColor Cyan

    $systemPrompt = Get-AiSystemPrompt -UseAliases $preferAliases
    $rawResponse = Invoke-OllamaApi -Prompt $fullPrompt -SystemPrompt $systemPrompt -Model $activeModel -Temperature 0.0
    if ([string]::IsNullOrWhiteSpace($rawResponse)) {
        return
    }

    # Очищаємо залишки буфера перед виведенням результату та меню дій
    Clear-AiInputBuffer

    $command = Format-AiCodeOutput -Text $rawResponse
    $command = [regex]::Replace($command, '\b(?:gci|Get-ChildItem)\s+tcpconn\b', 'Get-NetTCPConnection', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if ($preferAliases) {
        $command = ConvertTo-AiShortAliases $command
    }

    # 6. Перевірка на синтаксичні помилки та неіснуючі командлети
    $ast = $null
    $parseErrors = $null
    $tokens = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Write-Host "    ⚠ [$(Get-TerminalAiText 'Warning')] $($parseErrors[0].Message)" -ForegroundColor DarkYellow
        }
    } catch { }

    $isUnknownCmdlet = $false
    $firstWord = ($command.Trim() -split '[\s|\(]')[0].TrimStart('(').Trim()
    if ($firstWord -match '^[A-Za-z]+-[A-Za-z0-9]+$') {
        if (-not (Get-Command -Name $firstWord -ErrorAction SilentlyContinue)) {
            $isUnknownCmdlet = $true
        }
    }

    # Відображення результату у вигляді красивої закритої картки з відступами
    Show-AiCodeCard -Code $command -Title (Get-TerminalAiText "CardTitle") -Model $activeModel -CodeColor Green

    if ($isUnknownCmdlet) {
        Write-Host "    ⚠ [$(Get-TerminalAiText 'Warning')] $(Get-TerminalAiText 'UnknownCmdlet') '$firstWord'" -ForegroundColor DarkYellow
        Write-Host "      $(Get-TerminalAiText 'UnknownCmdletHint')`n" -ForegroundColor DarkGray
    }

    # Якщо вказано прапорець автоматичного копіювання або -Copy
    if ($Copy -or $cfg.AutoCopy) {
        Set-Clipboard -Value $command
        Write-Host "    ✔ $(Get-TerminalAiText 'Copied')`n" -ForegroundColor DarkGreen
    }

    # Якщо вказано -Execute (-x або -y)
    if ($Execute) {
        Write-Host "    ▶ $(Get-TerminalAiText 'Executing') $command" -ForegroundColor Yellow
        Invoke-AiExecutionGate -Command $command -AutoConfirm
        return
    }

    # Якщо вказано -Preview / -WhatIf (-w)
    if ($Preview) {
        Invoke-AiExecutionGate -Command $command -WhatIf
        return
    }

    # Якщо вказано -Explain
    if ($Explain) {
        Show-AiExplanation -Command $command -Model $activeModel
        return
    }

    # Дворівневе структуроване меню дій з можливістю перемикання аліасів
    while ($true) {
        $cmdAst = Test-AiCommandAst -Command $command
        Show-AiActionMenu -UseAliases $preferAliases -CanPreview $cmdAst.CanPreview

        $allowedActions = if ($cmdAst.CanPreview) {
            @('Execute', 'Copy', 'Insert', 'ShortAlias', 'Ask', 'Explain', 'WhatIf', 'Cancel')
        } else {
            @('Execute', 'Copy', 'Insert', 'ShortAlias', 'Ask', 'Explain', 'Cancel')
        }

        $action = Get-AiMenuKeyPress -AllowedActions $allowedActions
        switch ($action) {
            'WhatIf' {
                Invoke-AiExecutionGate -Command $command -WhatIf
                continue
            }
            'Execute' {
                Write-Host "    ▶ $(Get-TerminalAiText 'Executing')`n" -ForegroundColor Yellow
                Invoke-AiExecutionGate -Command $command -AutoConfirm
                return
            }
            'Cancel' {
                Write-Host "    $(Get-TerminalAiText 'Canceled')`n" -ForegroundColor DarkGray
                return
            }
            'Copy' {
                Set-Clipboard -Value $command
                Write-Host "    ✔ $(Get-TerminalAiText 'Copied')`n" -ForegroundColor Green
                return
            }
            'Insert' {
                Set-Clipboard -Value $command
                $pasted = $false
                try {
                    if (([System.Management.Automation.PSTypeName]'TerminalAiPasteHelper').Type) {
                        [TerminalAiPasteHelper]::DelayedPaste(200)
                        $pasted = $true
                    }
                } catch { }

                if (-not $pasted) {
                    try {
                        $ws = New-Object -ComObject WScript.Shell
                        $ws.SendKeys("^v")
                    } catch { }
                }
                Write-Host "    ✔ $(Get-TerminalAiText 'Inserted')`n" -ForegroundColor Green
                return
            }
            'Ask' {
                Show-AiAnswer -Question $fullPrompt -Model $activeModel
                return
            }
            'Explain' {
                Write-Host ""
                Show-AiExplanation -Command $command -Model $activeModel
                return
            }
            'ShortAlias' {
                $preferAliases = -not $preferAliases
                $command = if ($preferAliases) {
                    ConvertTo-AiShortAliases $command
                } else {
                    ConvertTo-AiFullCmdlets $command
                }
                Show-AiCodeCard -Code $command -Title (Get-TerminalAiText "CardTitle") -Model $activeModel -CodeColor Green
                continue
            }
        }
    }
}

function Show-AiExplanation {
    param(
        [string]$Command,
        [string]$Model
    )

    $cfg = Get-TerminalAiConfig
    $langInstruction = if ($cfg.Language -eq "uk") { "Respond strictly in Ukrainian language." } else { "Respond in English." }

    Write-Host "`n  ✦ $(Get-TerminalAiText 'Explaining')" -ForegroundColor Cyan

    $explainSystemPrompt = @"
You are an expert technical educator explaining PowerShell commands to engineers.
$langInstruction
Explain concisely:
1. What the command does overall.
2. Breakdown of key parameters and pipeline operators.
3. Any potential performance or security considerations.
Format with clean bullet points.
"@

    $explanation = Invoke-OllamaApi -Prompt "Explain this PowerShell command: `n`n$Command" -SystemPrompt $explainSystemPrompt -Model $Model -Temperature 0.3
    if ($explanation) {
        Write-Host "`n    ✦ $(Get-TerminalAiText 'CardTitleExplain'):" -ForegroundColor Cyan
        Write-Host ("    " + ("─" * 66)) -ForegroundColor DarkCyan
        foreach ($line in ($explanation -split "`r?`n")) {
            Write-Host "    $line" -ForegroundColor Gray
        }
        Write-Host ("    " + ("─" * 66)) + "`n" -ForegroundColor DarkCyan
    }
}

function Invoke-AiFix {
    <#
    .SYNOPSIS
        Аналізує останню помилку в терміналі та пропонує виправлену команду через Ollama.
    .EXAMPLE
        ai-fix
    #>
    [CmdletBinding()]
    [Alias("ai-fix", "fix-error")]
    param(
        [string]$Model
    )

    $cfg = Get-TerminalAiConfig

    if ($global:Error.Count -eq 0) {
        Write-Host "    ✔ $(Get-TerminalAiText 'NoError')" -ForegroundColor Green
        return
    }

    $lastErr = $global:Error[0]
    $errMessage = $lastErr.Exception.Message
    $failedCommand = $lastErr.InvocationInfo.Line
    $failedScript = $lastErr.InvocationInfo.ScriptName

    $activeModel = if ($Model) { $Model } else { $cfg.Model }
    $langInstruction = if ($cfg.Language -eq "uk") { "Respond in Ukrainian for the diagnosis, but output the fixed PowerShell command clearly." } else { "Respond in English." }

    Write-Host "`n  ✦ [AI-Fix] $(Get-TerminalAiText 'Fixing') ($activeModel)..." -ForegroundColor Cyan
    Write-Host "    $(Get-TerminalAiText 'ErrorLabel') " -NoNewline -ForegroundColor DarkYellow
    Write-Host "$errMessage" -ForegroundColor Red
    if ($failedCommand) {
        Write-Host "    $(Get-TerminalAiText 'FailedCommand') $failedCommand" -ForegroundColor DarkGray
    }

    $fixPrompt = @'
The user executed a command in PowerShell and encountered an error.
Failed command: {0}
Error message: {1}
Script/Location: {2}

Please provide:
1. DIAGNOSIS: A concise 1-2 sentence explanation of why this error happened.
2. FIXED_COMMAND: The exact corrected PowerShell command to solve the problem.

{3}
Format your response exactly as:
DIAGNOSIS: <brief explanation>
FIXED_COMMAND:
```powershell
<corrected command>
```
'@ -f $failedCommand, $errMessage, $failedScript, $langInstruction

    $fixSystemPrompt = @"
You are an elite PowerShell 7 debugging engineer.
Rules:
1. Provide a precise 1-2 sentence diagnosis.
2. Provide a 100% correct, runnable PowerShell fix.
3. If the command failed because of hallucinated or invalid cmdlets (such as 'gci tcpconn' or 'Get-ChildItem tcpconn'), replace them with standard cmdlets:
   - For ports/connections, use:
     Get-NetTCPConnection -LocalPort <port> -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Get-Process -Id `$_.OwningProcess -ErrorAction SilentlyContinue }
4. Never bind null to mandatory parameters like -Id.
5. Output code ONLY in the FIXED_COMMAND block.
"@

    $response = Invoke-OllamaApi -Prompt $fixPrompt -SystemPrompt $fixSystemPrompt -Model $activeModel -Temperature 0.1
    if (-not $response) { return }

    # Очищаємо залишки буфера перед виведенням результату та меню дій
    Clear-AiInputBuffer

    # Парсимо відповідь
    $diagnosis = ""
    $fixedCode = ""

    if ($response -match '(?si)DIAGNOSIS:\s*(.*?)(?:FIXED_COMMAND:|$)') {
        $diagnosis = $Matches[1].Trim()
    }

    if ($response -match '(?si)```(?:powershell|pwsh)?\r?\n?(.*?)\r?\n?```') {
        $fixedCode = $Matches[1].Trim()
    } elseif ($response -match '(?si)FIXED_COMMAND:\s*(.*)') {
        $fixedCode = $Matches[1].Trim()
    }

    if ($diagnosis) {
        Write-Host "`n    ✦ $(Get-TerminalAiText 'Diagnosis')" -ForegroundColor Cyan
        Write-Host "    $diagnosis" -ForegroundColor White
    }

    if ($fixedCode) {
        $fixedCode = [regex]::Replace($fixedCode, '\b(?:gci|Get-ChildItem)\s+tcpconn\b', 'Get-NetTCPConnection', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        Show-AiCodeCard -Code $fixedCode -Title (Get-TerminalAiText "CardTitleFixed") -Model $activeModel -CodeColor Green

        Write-Host "    [Enter] " -NoNewline -ForegroundColor Green
        Write-Host ("{0,-18}" -f (Get-TerminalAiText "MenuEnter")) -NoNewline -ForegroundColor White
        Write-Host "[C] " -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,-18}" -f (Get-TerminalAiText "MenuCopy")) -NoNewline -ForegroundColor White
        Write-Host "[I] " -NoNewline -ForegroundColor Cyan
        Write-Host (Get-TerminalAiText "MenuInsert") -ForegroundColor White
        Write-Host "    [Esc]   " -NoNewline -ForegroundColor Gray
        Write-Host (Get-TerminalAiText "MenuCancel") -ForegroundColor White
        Write-Host ""

        $fixAction = Get-AiMenuKeyPress -AllowedActions @('Execute', 'Copy', 'Insert', 'Cancel')
        switch ($fixAction) {
            'Execute' {
                Write-Host "    ▶ $(Get-TerminalAiText 'ExecutingFixed')`n" -ForegroundColor Yellow
                Invoke-AiExecutionGate -Command $fixedCode -AutoConfirm
            }
            'Copy' {
                Set-Clipboard -Value $fixedCode
                Write-Host "    ✔ $(Get-TerminalAiText 'Copied')`n" -ForegroundColor Green
            }
            'Insert' {
                Set-Clipboard -Value $fixedCode
                $pasted = $false
                try {
                    if (([System.Management.Automation.PSTypeName]'TerminalAiPasteHelper').Type) {
                        [TerminalAiPasteHelper]::DelayedPaste(200)
                        $pasted = $true
                    }
                } catch { }

                if (-not $pasted) {
                    try {
                        $ws = New-Object -ComObject WScript.Shell
                        $ws.SendKeys("^v")
                    } catch { }
                }
                Write-Host "    ✔ $(Get-TerminalAiText 'Inserted')`n" -ForegroundColor Green
            }
            'Cancel' {
                Write-Host "    $(Get-TerminalAiText 'Canceled')`n" -ForegroundColor DarkGray
            }
        }
    }
}

function Protect-AiSecretData {
    <#
    .SYNOPSIS
        Детерміноване маскування секретів, API-токенів та паролів для захисту контексту.
    .DESCRIPTION
        Сканує текст та замінює відомі патерни токенів (OpenAI sk-, Anthropic sk-ant-, HuggingFace,
        GitHub pat, AWS AKIA, Bearer токени, приватні ключі та паролі) на безпечні плейсхолдери,
        унеможливлюючи витік конфіденційних даних у контекст LLM та логи сесії.
    .PARAMETER Text
        Вхідний текст або код для очищення.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $res = $Text

    # 1. Приватні ключі PEM (RSA, EC, OpenSSH, DSA)
    $res = [regex]::Replace($res, '(?s)-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----.*?-----END (?:[A-Z ]+)?PRIVATE KEY-----', '***[REDACTED PRIVATE KEY]***')

    # 2. Добре відомі префікси API-токенів
    $res = [regex]::Replace($res, '\b(sk-ant-[a-zA-Z0-9_\-]{20,})\b', 'sk-ant-***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(sk-[a-zA-Z0-9_\-]{20,})\b', 'sk-***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(hf_[a-zA-Z0-9]{20,})\b', 'hf_***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(ghp_[a-zA-Z0-9]{20,})\b', 'ghp_***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(github_pat_[a-zA-Z0-9_]{20,})\b', 'github_pat_***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(AKIA[0-9A-Z]{16})\b', '***[REDACTED AWS KEY]***')

    # 3. Bearer токени (Authorization: Bearer <token>)
    $res = [regex]::Replace($res, '(?i)(bearer\s+)[a-zA-Z0-9_\-\.]{20,}', '${1}***[REDACTED]***')

    # 4. Паролі та секрети у параметрах/конфігураціях ($password, $pass, $pwd, api_key, secret, token = "...")
    $res = [regex]::Replace($res, '(?i)([$]?(?:password|pass|pwd)\s*[:=]\s*[\x22\x27])(?![^\x22\x27]*\[REDACTED\])[^\r\n\x22\x27]{4,}([\x22\x27])', '${1}***[REDACTED]***${2}')
    $res = [regex]::Replace($res, '(?i)([$]?(?:api[_-]?key|secret|token)\s*[:=]\s*[\x22\x27])(?![^\x22\x27]*\[REDACTED\])[^\r\n\x22\x27]{4,}([\x22\x27])', '${1}***[REDACTED]***${2}')

    return $res
}

function Format-AiScriptDiff {
    <#
    .SYNOPSIS
        Формує простий, швидкий та детермінований Unified Diff між існуючим та новим текстом.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [string]$OldLabel = "Existing File",
        [string]$NewLabel = "New AI Script",
        [switch]$PassThru
    )

    $oldLines = if ($OldText) { $OldText -split '\r?\n' } else { @() }
    $newLines = if ($NewText) { $NewText -split '\r?\n' } else { @() }

    $diffRecords = [System.Collections.Generic.List[psobject]]::new()
    $i = 0
    $j = 0
    $maxSteps = ($oldLines.Count + $newLines.Count) * 2 + 10
    $steps = 0

    while (($i -lt $oldLines.Count -or $j -lt $newLines.Count) -and ($steps -lt $maxSteps)) {
        $steps++
        $o = if ($i -lt $oldLines.Count) { $oldLines[$i] } else { $null }
        $n = if ($j -lt $newLines.Count) { $newLines[$j] } else { $null }

        if ($null -ne $o -and $null -ne $n -and $o -eq $n) {
            $diffRecords.Add([PSCustomObject]@{ Type = "Unchanged"; Line = "  $o" })
            $i++; $j++
        } elseif ($null -ne $o -and $null -ne $n -and $o -ne $n) {
            if (($j + 1) -lt $newLines.Count -and $newLines[$j + 1] -eq $o) {
                $diffRecords.Add([PSCustomObject]@{ Type = "Added"; Line = "+ $n" })
                $j++
            } elseif (($i + 1) -lt $oldLines.Count -and $oldLines[$i + 1] -eq $n) {
                $diffRecords.Add([PSCustomObject]@{ Type = "Removed"; Line = "- $o" })
                $i++
            } else {
                $diffRecords.Add([PSCustomObject]@{ Type = "Removed"; Line = "- $o" })
                $diffRecords.Add([PSCustomObject]@{ Type = "Added"; Line = "+ $n" })
                $i++; $j++
            }
        } elseif ($null -ne $o -and $null -eq $n) {
            $diffRecords.Add([PSCustomObject]@{ Type = "Removed"; Line = "- $o" })
            $i++
        } elseif ($null -eq $o -and $null -ne $n) {
            $diffRecords.Add([PSCustomObject]@{ Type = "Added"; Line = "+ $n" })
            $j++
        } else {
            break
        }
    }

    Write-Host ""
    Write-Host "    --- $OldLabel" -ForegroundColor Red
    Write-Host "    +++ $NewLabel" -ForegroundColor Green
    foreach ($dl in $diffRecords) {
        switch ($dl.Type) {
            "Added"     { Write-Host "    $($dl.Line)" -ForegroundColor Green }
            "Removed"   { Write-Host "    $($dl.Line)" -ForegroundColor Red }
            "Unchanged" { Write-Host "    $($dl.Line)" -ForegroundColor DarkGray }
        }
    }
    Write-Host ""

    if ($PassThru) {
        return @($diffRecords)
    }
}

function Save-AiScriptFile {
    <#
    .SYNOPSIS
        Безпечний атомарний запис AI-скрипту з показом diff та підтвердженням при перезаписі.
    .DESCRIPTION
        Перевіряє наявність файлу за вказаним шляхом. Якщо файл існує:
        1. Якщо новий вміст повністю збігається з існуючим: повертає інформаційне повідомлення без зайвих дій.
        2. Якщо вміст відрізняється: відображає unified diff і вимагає явного підтвердження [y/N].
        3. Якщо підтверджено: виконує атомарний запис через тимчасовий файл з кодуванням UTF-8 BOM.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Content,

        [switch]$Force,

        [string]$ConfirmInput,

        [switch]$PassThru
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $fileExists = Test-Path -Path $resolvedPath -PathType Leaf
    $diff = @()

    if ($fileExists) {
        $existingContent = try {
            [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
        } catch {
            Get-Content -Path $resolvedPath -Raw -ErrorAction SilentlyContinue
        }

        if ($null -ne $existingContent -and $existingContent.Trim() -eq $Content.Trim()) {
            Write-Host "    ℹ [TerminalAI] File already exists with identical content: $resolvedPath" -ForegroundColor DarkCyan
            if ($PassThru) {
                return [PSCustomObject]@{
                    Saved  = $true
                    Status = "Identical"
                    Path   = $resolvedPath
                    Diff   = @()
                }
            }
            return $true
        }

        # Файл існує і відрізняється: показуємо diff
        Write-Host ""
        Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "    │             ⚠  EXISTING FILE OVERWRITE WARNING  ⚠           │" -ForegroundColor Yellow
        Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host "    File: $resolvedPath" -ForegroundColor Cyan

        $diff = Format-AiScriptDiff -OldText $existingContent -NewText $Content -OldLabel "Existing File" -NewLabel "New AI Script" -PassThru

        if (-not $Force) {
            $confirmed = $false
            if ($PSBoundParameters.ContainsKey('ConfirmInput')) {
                $response = $ConfirmInput
            } else {
                try {
                    $isInteractive = [Environment]::UserInteractive
                    if ([Console]::IsInputRedirected) { $isInteractive = $false }
                } catch { $isInteractive = $true }

                if (-not $isInteractive) {
                    Write-Host "    ✖ Non-interactive session. Overwrite canceled for safety." -ForegroundColor Red
                    if ($PassThru) {
                        return [PSCustomObject]@{
                            Saved  = $false
                            Status = "BlockedNonInteractive"
                            Path   = $resolvedPath
                            Diff   = $diff
                        }
                    }
                    return $false
                }

                $response = Read-Host "    Overwrite this file? [y/N]"
            }

            if ($response -match '^(y|yes|так|т)$') {
                $confirmed = $true
            }

            if (-not $confirmed) {
                Write-Host "    ✖ Overwrite canceled by user." -ForegroundColor DarkGray
                if ($PassThru) {
                    return [PSCustomObject]@{
                        Saved  = $false
                        Status = "OverwriteDenied"
                        Path   = $resolvedPath
                        Diff   = $diff
                    }
                }
                return $false
            }
        }
    }

    # Атомарний запис: пишемо у .tmp, потім замінюємо
    $enc = New-Object System.Text.UTF8Encoding($true)
    $dir = [System.IO.Path]::GetDirectoryName($resolvedPath)
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $tmpPath = "$resolvedPath.tmp." + [System.Guid]::NewGuid().ToString("N")
    try {
        [System.IO.File]::WriteAllText($tmpPath, $Content, $enc)
        if ($fileExists) {
            [System.IO.File]::Copy($tmpPath, $resolvedPath, $true)
            [System.IO.File]::Delete($tmpPath)
        } else {
            [System.IO.File]::Move($tmpPath, $resolvedPath)
        }
        Write-Host "    ✔ File successfully saved: $resolvedPath" -ForegroundColor Green
        if ($PassThru) {
            return [PSCustomObject]@{
                Saved  = $true
                Status = if ($fileExists) { "Overwritten" } else { "Created" }
                Path   = $resolvedPath
                Diff   = if ($fileExists) { $diff } else { @() }
            }
        }
        return $true
    } catch {
        if (Test-Path $tmpPath) {
            Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host "    ✖ Error saving file: $($_.Exception.Message)" -ForegroundColor Red
        if ($PassThru) {
            return [PSCustomObject]@{
                Saved  = $false
                Status = "Error"
                Path   = $resolvedPath
                Error  = $_.Exception.Message
            }
        }
        return $false
    }
}

function New-AiScript {
    <#
    .SYNOPSIS
        Генерує повноцінний PowerShell-сценарій (.ps1) з обробкою помилок та параметрами.
    .EXAMPLE
        ai-script "Архівація логів за останній місяць та відправка сповіщення" -OutputPath ./backup_logs.ps1 -Edit
    #>
    [CmdletBinding()]
    [Alias("ai-script")]
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Description,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [switch]$Edit,

        [string]$Model
    )

    $fullDesc = ($Description -join " ").Trim()
    $cfg = Get-TerminalAiConfig
    $activeModel = if ($Model) { $Model } else { $cfg.Model }
    $isUk = ($cfg.Language -ne "en")

    Write-Host "`n  [AI-Script] $(Get-TerminalAiText 'Scripting')" -ForegroundColor Cyan
    $taskLabel = if ($isUk) { "Завдання:" } else { "Task:" }
    Write-Host "  $taskLabel $fullDesc" -ForegroundColor DarkGray

    $scriptSystemPrompt = @"
You are a Principal PowerShell Engineer.
Write a production-grade, modular, well-commented PowerShell script for PowerShell 7.
Requirements:
1. Include a Help/Documentation block (<# .SYNOPSIS ... #>).
2. Use [CmdletBinding()] and a strongly-typed param() block with sensible defaults.
3. Wrap operations in robust try/catch blocks with informative error logging.
4. Output clean, readable, executable PowerShell script code.
5. If using markdown code fences, format them cleanly.
"@

    $rawResponse = Invoke-OllamaApi -Prompt $fullDesc -SystemPrompt $scriptSystemPrompt -Model $activeModel -Temperature 0.2
    if (-not $rawResponse) { return }

    $scriptContent = Format-AiCodeOutput -Text $rawResponse

    if ($OutputPath) {
        $saved = Save-AiScriptFile -Path $OutputPath -Content $scriptContent
        if ($saved -and $Edit) {
            if (Get-Command code -ErrorAction SilentlyContinue) {
                code $OutputPath
            } else {
                notepad $OutputPath
            }
        }
    } else {
        Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
        Write-Host $scriptContent -ForegroundColor White
        Write-Host ("=" * 70) + "`n" -ForegroundColor Cyan

        Write-Host "  $(Get-TerminalAiText 'SaveScriptPrompt')" -NoNewline -ForegroundColor Yellow
        $resp = Read-Host
        if ($resp -match '^(y|yes|так|т)$') {
            $defaultName = "script_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".ps1"
            $promptFileName = (Get-TerminalAiText "EnterFileName") -f $defaultName
            $savePath = Read-Host "  $promptFileName"
            if ([string]::IsNullOrWhiteSpace($savePath)) { $savePath = $defaultName }
            Save-AiScriptFile -Path $savePath -Content $scriptContent
        }
    }
}

function Invoke-AiAssistant {
    <#
    .SYNOPSIS
        Запускає інтерактивного AI-асистента (чат/агента) для сесії Windows Terminal або PowerShell.
    .DESCRIPTION
        Запускає REPL-сесію з підтримкою багатокрокового діалогу, Tab-автодоповненням слеш-команд
        (/help, /models, /model, /lang, /copy, /save), перемиканням мови (uk/en) та моделі.
    .EXAMPLE
        ai-chat
    .EXAMPLE
        ai-chat -Model qwen2.5-coder:7b
    #>
    [CmdletBinding()]
    [Alias("ai-chat", "ai-assistant")]
    param(
        [Parameter(Position = 0)]
        [string]$Model
    )

    $assistantScript = Join-Path $PSScriptRoot "TerminalAiAssistant.ps1"
    if (-not (Test-Path $assistantScript)) {
        $module = Get-Module TerminalAI -ListAvailable | Select-Object -First 1
        if ($module) {
            $assistantScript = Join-Path $module.ModuleBase "TerminalAiAssistant.ps1"
        }
    }

    if (Test-Path $assistantScript) {
        $params = @{}
        if ($Model) { $params["Model"] = $Model }
        & $assistantScript @params
    } else {
        Write-Error "[TerminalAI] TerminalAiAssistant.ps1 не знайдено у '$PSScriptRoot'."
    }
}

function Send-OllamaHttpAsync {
    [CmdletBinding()]
    param(
        [string]$Endpoint = "api/generate",
        [hashtable]$Payload
    )

    $cfg = Get-TerminalAiConfig
    $targetUrl = "$($cfg.OllamaUrl.TrimEnd('/'))/$($Endpoint.TrimStart('/'))"
    $bodyJson = $Payload | ConvertTo-Json -Depth 6

    if (-not ([System.Management.Automation.PSTypeName]'System.Net.Http.HttpClient').Type) {
        try { Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue } catch { }
    }

    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.Timeout = [TimeSpan]::FromSeconds($cfg.TimeoutSeconds)
    $httpContent = [System.Net.Http.StringContent]::new($bodyJson, [System.Text.Encoding]::UTF8, "application/json")
    $postTask = $httpClient.PostAsync($targetUrl, $httpContent)

    return @{
        Client = $httpClient
        Task   = $postTask
        Url    = $targetUrl
    }
}

# --- PSREADLINE ІНТЕГРАЦІЯ (ГАРЯЧІ КЛАВІШІ) ---

function Register-TerminalAiKeyHandler {
    [CmdletBinding()]
    param(
        [string[]]$Chord
    )

    if (-not (Get-Module -Name PSReadLine)) {
        try {
            Import-Module PSReadLine -ErrorAction Stop
        } catch {
            Write-Warning " [TerminalAI] PSReadLine не знайдено. Інлайн-гарячі клавіші недоступні."
            return
        }
    }

    $cfg = Get-TerminalAiConfig

    # Реєструємо F2, Ctrl+G (з урахуванням регістру та розкладки), Ctrl+Alt+A
    $targetChords = [System.Collections.Generic.List[string]]::new()
    $targetChords.Add("F2")
    foreach ($cg in @("Ctrl+g", "Ctrl+G", "Ctrl+п", "Ctrl+П")) {
        $targetChords.Add($cg)
    }
    foreach ($ca in @("Ctrl+Alt+a", "Ctrl+Alt+A")) {
        $targetChords.Add($ca)
    }
    if ($Chord) {
        foreach ($c in $Chord) {
            if (-not $targetChords.Contains($c)) { $targetChords.Add($c) }
        }
    } elseif ($cfg.HotkeyChord) {
        $custom = $cfg.HotkeyChord
        if (-not $targetChords.Contains($custom)) { $targetChords.Add($custom) }
        if (-not $targetChords.Contains($custom.ToLower())) { $targetChords.Add($custom.ToLower()) }
        if (-not $targetChords.Contains($custom.ToUpper())) { $targetChords.Add($custom.ToUpper()) }
    }

    $keyHandler = {
        param($key, $arg)

        $line = ""
        $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $query = $line.Trim()
        # Очищуємо від префіксів коментарів, аліасів та шаблонів
        if ($query -match '^(?:#\s*\[AI[^\]]*\]:?|#|\?\?)\s*(.*)') {
            $query = $Matches[1].Trim()
        }
        if ($query -match '^\[AI[^\]]*\]:?\s*(.*)') {
            $query = $Matches[1].Trim()
        }

        $cfg = Get-TerminalAiConfig

        if ([string]::IsNullOrWhiteSpace($query)) {
            # Якщо рядок порожній або містить лише префікс, вставляємо шаблон для запиту
            $promptPlaceholder = if ($cfg.Language -eq "en") { "# [AI Prompt]: " } else { "# [AI Запит]: " }
            $currLine = ""
            $currCursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currLine, [ref]$currCursor)
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, $promptPlaceholder)
            return
        }

        try {
            $activeModel = $cfg.Model
            $sysPrompt = Get-AiSystemPrompt
            $payload = @{
                model      = $activeModel
                prompt     = $query
                system     = $sysPrompt
                stream     = $false
                keep_alive = "1h"
                options    = @{
                    temperature = 0.0
                    num_ctx     = 1024
                    num_predict = 120
                }
            }

            $asyncCall = Send-OllamaHttpAsync -Endpoint "api/generate" -Payload $payload
            $httpClient = $asyncCall.Client
            $postTask = $asyncCall.Task

            # Кадри анімації спінера та відлік секунд у реальному часі
            $spinnerFrames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $frameIdx = 0

            # Скорочуємо текст запиту якщо він довгий, щоб рядок не переповнював вікно
            $displayQuery = if ($query.Length -gt 45) { $query.Substring(0, 42) + "..." } else { $query }

            # Одразу виводимо початковий стан індикатора (0s), щоб користувач миттєво бачив таймер
            $currLine = ""
            $currCursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currLine, [ref]$currCursor)
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, "# [AI ⠋ 0s] $displayQuery")

            while (-not $postTask.IsCompleted) {
                $spinner = $spinnerFrames[$frameIdx % $spinnerFrames.Length]
                $sec = [Math]::Floor($stopwatch.Elapsed.TotalSeconds)
                $statusText = "# [AI $spinner ${sec}s] $displayQuery"

                $currLine = ""
                $currCursor = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currLine, [ref]$currCursor)
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, $statusText)

                Start-Sleep -Milliseconds 120
                $frameIdx++
            }
            $stopwatch.Stop()

            $cleanCode = ""
            try {
                $httpResponse = $postTask.GetAwaiter().GetResult()
                if ($httpResponse.IsSuccessStatusCode) {
                    $respString = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    $json = $respString | ConvertFrom-Json
                    $cleanCode = Format-AiCodeOutput -Text $json.response
                }
            }
            catch { }
            finally {
                $httpClient.Dispose()
            }

            $currLine = ""
            $currCursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currLine, [ref]$currCursor)

            if (-not [string]::IsNullOrWhiteSpace($cleanCode)) {
                # Замінюємо індикатор на згенеровану готову команду
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, $cleanCode)
            } else {
                # Інформуємо про помилку або відсутність результату та відновлюємо рядок
                $msg = if ($cfg.Language -eq "uk") { "# [AI: Ollama offline / помилка відповіді]" } else { "# [AI: Ollama offline / error response]" }
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, "$msg $displayQuery")
                Start-Sleep -Milliseconds 900
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, "$msg $displayQuery".Length, $line)
            }
        }
        catch {
            # Безпечне відновлення рядка у разі винятку з індикацією помилки
            try {
                $errLine = ""
                $errCursor = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$errLine, [ref]$errCursor)
                $errMsg = if ($cfg.Language -eq "uk") { "# [AI: Ollama offline / помилка з'єднання]" } else { "# [AI: Ollama offline / connection error]" }
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $errLine.Length, "$errMsg $displayQuery")
                Start-Sleep -Milliseconds 900
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, "$errMsg $displayQuery".Length, $line)
            } catch { }
        }
    }

    foreach ($c in $targetChords) {
        try {
            Set-PSReadLineKeyHandler -Chord $c -ScriptBlock $keyHandler -Description "Terminal AI: Generate PowerShell command" -ErrorAction SilentlyContinue
        }
        catch { }
    }
}

$script:TerminalAiCachedModels = $null
$script:TerminalAiCacheTime = [datetime]::MinValue

$script:TerminalAiGetModels = {
    param([string]$word = "")
    $now = [datetime]::UtcNow
    if ($script:TerminalAiCachedModels -and ($now - $script:TerminalAiCacheTime).TotalSeconds -lt 20) {
        return ($script:TerminalAiCachedModels | Where-Object { $_.CompletionText -like "$word*" })
    }

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
    try {
        $cfg = Get-TerminalAiConfig
        $url = if ($cfg.OllamaUrl) { $cfg.OllamaUrl } else { "http://127.0.0.1:11434" }
        $url = $url -replace 'localhost', '127.0.0.1'
        $res = Invoke-RestMethod -Uri "$url/api/tags" -Method Get -TimeoutSec 1 -ErrorAction Stop
        if ($res.models) {
            foreach ($m in $res.models) {
                $sizeGb = [math]::Round($m.size / 1GB, 1)
                $tooltip = "$($m.name) ($sizeGb GB)"
                $results.Add([System.Management.Automation.CompletionResult]::new($m.name, $m.name, 'ParameterValue', $tooltip))
            }
        }
    }
    catch { }

    if ($results.Count -eq 0) {
        $defaults = @('qwen2.5-coder:7b', 'granite4.2:8b', 'deepseek-coder:6.7b', 'qwen2.5-coder:1.5b')
        foreach ($d in $defaults) {
            $results.Add([System.Management.Automation.CompletionResult]::new($d, $d, 'ParameterValue', $d))
        }
    }
    $script:TerminalAiCachedModels = $results
    $script:TerminalAiCacheTime = $now
    return ($results | Where-Object { $_.CompletionText -like "$word*" })
}

function Register-TerminalAiArgumentCompleters {
    <#
    .SYNOPSIS
        Реєструє динамічні обробники автодоповнення (Tab completion) для TerminalAI.
    .DESCRIPTION
        Забезпечує автодоповнення по Tab для підкоманд (help, status, models, model, lang, config),
        тем довідки (all, shortcuts, models, examples, workflow, config), мов інтерфейсу (en, uk)
        та встановлених моделей Ollama.
    #>
    [CmdletBinding()]
    param()

    $commands = @('Invoke-AiCommand', 'ai', '??', 'Invoke-AiCommandFast', 'ai-fast', 'aif')

    # 1. Автодоповнення параметрів -Topic для Show-TerminalAiHelp / ai-help
    $topicCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $topics = @(
            [System.Management.Automation.CompletionResult]::new('all', 'all', 'ParameterValue', 'Complete overview & command map'),
            [System.Management.Automation.CompletionResult]::new('shortcuts', 'shortcuts', 'ParameterValue', 'Keybindings, flags, and aliases cheat-sheet'),
            [System.Management.Automation.CompletionResult]::new('models', 'models', 'ParameterValue', 'Ollama coding models & VRAM requirements'),
            [System.Management.Automation.CompletionResult]::new('examples', 'examples', 'ParameterValue', 'Practical DevOps & sysadmin examples'),
            [System.Management.Automation.CompletionResult]::new('workflow', 'workflow', 'ParameterValue', 'Windows Terminal interactive workflow guide'),
            [System.Management.Automation.CompletionResult]::new('config', 'config', 'ParameterValue', 'Configuration parameters & options')
        )
        $topics | Where-Object { $_.CompletionText -like "$wordToComplete*" }
    }
    Register-ArgumentCompleter -CommandName @('Show-TerminalAiHelp', 'ai-help') -ParameterName 'Topic' -ScriptBlock $topicCompleter -ErrorAction SilentlyContinue

    # 2. Динамічне автодоповнення моделей Ollama для параметра -Model
    $modelCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        & $script:TerminalAiGetModels $wordToComplete
    }
    Register-ArgumentCompleter -CommandName $commands -ParameterName 'Model' -ScriptBlock $modelCompleter -ErrorAction SilentlyContinue

    # 3. Контекстне автодоповнення для Prompt (підкоманди, теми, мови, моделі)
    $promptCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $elements = $commandAst.CommandElements
        $tokens = @()
        foreach ($el in $elements) {
            $t = $el.Extent.Text.Trim().Trim('"').Trim("'")
            if (-not [string]::IsNullOrWhiteSpace($t)) { $tokens += $t }
        }

        # Перший аргумент після самої команди (напр. "aif <tab>" або "ai <tab>")
        if ($tokens.Count -le 1 -or ($tokens.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($wordToComplete))) {
            $subcommands = @(
                [System.Management.Automation.CompletionResult]::new('help', 'help', 'ParameterValue', 'Educational guides & cheat-sheets'),
                [System.Management.Automation.CompletionResult]::new('shortcuts', 'shortcuts', 'ParameterValue', 'Keybindings, flags, and aliases guide'),
                [System.Management.Automation.CompletionResult]::new('status', 'status', 'ParameterValue', 'System information, active model and language'),
                [System.Management.Automation.CompletionResult]::new('alias', 'alias', 'ParameterValue', 'Configure short PowerShell aliases (on | off)'),
                [System.Management.Automation.CompletionResult]::new('models', 'models', 'ParameterValue', 'List installed Ollama models'),
                [System.Management.Automation.CompletionResult]::new('model', 'model', 'ParameterValue', 'Switch active Ollama model'),
                [System.Management.Automation.CompletionResult]::new('lang', 'lang', 'ParameterValue', 'Switch interface language (en | uk)'),
                [System.Management.Automation.CompletionResult]::new('examples', 'examples', 'ParameterValue', 'Practical command examples'),
                [System.Management.Automation.CompletionResult]::new('workflow', 'workflow', 'ParameterValue', 'Interactive terminal workflow guide'),
                [System.Management.Automation.CompletionResult]::new('config', 'config', 'ParameterValue', 'View configuration JSON'),
                [System.Management.Automation.CompletionResult]::new('fonts', 'fonts', 'ParameterValue', 'List available terminal fonts')
            )
            return ($subcommands | Where-Object { $_.CompletionText -like "$wordToComplete*" })
        }

        # Другий аргумент: перевіряємо перший токен
        $firstArg = $tokens[1].ToLowerInvariant()

        if ($firstArg -in @('alias', 'aliases', 'аліас', 'аліаси')) {
            $aliasOpts = @(
                [System.Management.Automation.CompletionResult]::new('on', 'on', 'ParameterValue', 'Enable short PowerShell aliases (gps, gci, select, ?, %)'),
                [System.Management.Automation.CompletionResult]::new('off', 'off', 'ParameterValue', 'Disable short aliases (use full cmdlet names)'),
                [System.Management.Automation.CompletionResult]::new('status', 'status', 'ParameterValue', 'Check current alias mode')
            )
            return ($aliasOpts | Where-Object { $_.CompletionText -like "$wordToComplete*" })
        }

        if ($firstArg -in @('help', 'довідка', 'допомога')) {
            $topics = @(
                [System.Management.Automation.CompletionResult]::new('all', 'all', 'ParameterValue', 'Complete overview & command map'),
                [System.Management.Automation.CompletionResult]::new('shortcuts', 'shortcuts', 'ParameterValue', 'Keybindings, flags, and aliases guide'),
                [System.Management.Automation.CompletionResult]::new('models', 'models', 'ParameterValue', 'Ollama coding models & VRAM requirements'),
                [System.Management.Automation.CompletionResult]::new('examples', 'examples', 'ParameterValue', 'Practical DevOps & sysadmin examples'),
                [System.Management.Automation.CompletionResult]::new('workflow', 'workflow', 'ParameterValue', 'Windows Terminal interactive workflow guide'),
                [System.Management.Automation.CompletionResult]::new('config', 'config', 'ParameterValue', 'Configuration parameters & options')
            )
            return ($topics | Where-Object { $_.CompletionText -like "$wordToComplete*" })
        }

        if ($firstArg -in @('model', 'set-model', 'use-model')) {
            return (& $script:TerminalAiGetModels $wordToComplete)
        }

        if ($firstArg -in @('lang', 'language', 'set-lang', 'мова')) {
            $langs = @(
                [System.Management.Automation.CompletionResult]::new('en', 'en', 'ParameterValue', 'English language'),
                [System.Management.Automation.CompletionResult]::new('uk', 'uk', 'ParameterValue', 'Ukrainian language (Українська)')
            )
            return ($langs | Where-Object { $_.CompletionText -like "$wordToComplete*" })
        }

        return @()
    }
    Register-ArgumentCompleter -CommandName $commands -ParameterName 'Prompt' -ScriptBlock $promptCompleter -ErrorAction SilentlyContinue
}

# --- АЛІАСИ ТА АВТОЗАВАНТАЖЕННЯ МОДУЛЯ ---
Set-Alias -Name ai-help -Value Show-TerminalAiHelp
Set-Alias -Name ai-font -Value Set-TerminalAiFont
Set-Alias -Name ai-fonts -Value Show-TerminalAiFonts
Set-Alias -Name ai-lang -Value Set-TerminalAiLanguage
Set-Alias -Name ai-lang-permanent -Value Set-TerminalAiDefaultLanguage
Set-Alias -Name ai-lang-default -Value Set-TerminalAiDefaultLanguage
Set-Alias -Name ai-chat -Value Invoke-AiAssistant
Set-Alias -Name ai-assistant -Value Invoke-AiAssistant

Register-TerminalAiKeyHandler
Register-TerminalAiArgumentCompleters

# Експорт функцій та аліасів
Export-ModuleMember -Function @(
    "Invoke-AiCommand",
    "Invoke-AiFix",
    "New-AiScript",
    "Invoke-AiAssistant",
    "Show-TerminalAiHelp",
    "Register-TerminalAiArgumentCompleters",
    "Get-TerminalAiConfig",
    "Set-TerminalAiConfig",
    "Get-TerminalAiModels",
    "Show-TerminalAiModels",
    "Get-WindowsTerminalSettingsPath",
    "Get-TerminalAiFonts",
    "Show-TerminalAiFonts",
    "Set-TerminalAiFont",
    "Set-TerminalAiLanguage",
    "Set-TerminalAiDefaultLanguage",
    "Register-TerminalAiKeyHandler",
    "Invoke-OllamaApi",
    "Format-AiCodeOutput",
    "Show-AiAnswer",
    "Show-AiCodeCard",
    "Show-AiActionMenu",
    "Get-TerminalAiText",
    "Show-TerminalAiWelcome",
    "Get-AiSystemPrompt",
    "Clear-AiInputBuffer",
    "Get-AiMenuKeyPress",
    "Test-AiCommandAst",
    "Invoke-AiExecutionGate",
    "Protect-AiSecretData",
    "Format-AiScriptDiff",
    "Save-AiScriptFile"
) -Alias @(
    "ai",
    "??",
    "ai-help",
    "ai-fix",
    "fix-error",
    "ai-script",
    "ai-font",
    "ai-fonts",
    "ai-lang",
    "ai-lang-permanent",
    "ai-lang-default",
    "ai-chat",
    "ai-assistant",
    "Clean-AiCodeOutput"
)
