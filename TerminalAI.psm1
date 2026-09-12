# TerminalAI.psm1 - PowerShell AI Розширення на базі локальної Ollama
# Requires -Version 5.1

# Забезпечуємо повну підтримку UTF-8 для коректного відображення кирилиці в консолі
try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
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

    # Видаляємо блок markdown (```powershell ... ``` або ``` ... ```)
    if ($clean -match '(?si)```(?:powershell|pwsh)?\r?\n?(.*?)\r?\n?```') {
        $clean = $Matches[1].Trim()
    }
    # Видаляємо одинарні зворотні лапки якщо рядок ними обгорнутий
    if ($clean.StartsWith('`') -and $clean.EndsWith('`') -and $clean.Length -gt 2) {
        $clean = $clean.Substring(1, $clean.Length - 2).Trim()
    }

    return $clean
}
Set-Alias -Name Clean-AiCodeOutput -Value Format-AiCodeOutput

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
            "MenuExplain"       = "Пояснити код"
            "MenuAsk"           = "Текстова відповідь"
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
            "MenuExplain"       = "Explain code"
            "MenuAsk"           = "Text answer"
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

    $lines = $Code -split "\r?\n"
    $maxCodeLen = 0
    foreach ($l in $lines) {
        if ($l.Length -gt $maxCodeLen) { $maxCodeLen = $l.Length }
    }

    $conWidth = 80
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 20) {
            $conWidth = $Host.UI.RawUI.WindowSize.Width
        }
    } catch { }

    $maxAllowed = [Math]::Max(66, $conWidth - 6)
    $boxInnerWidth = [Math]::Min($maxAllowed, [Math]::Max(64, $maxCodeLen + 4))

    $headerLabel = " ✦ $Title"
    if ($Model) { $headerLabel += " • $Model" }

    Write-Host ""
    Write-Host ("    $headerLabel") -ForegroundColor Cyan
    Write-Host ("    ╭" + ("─" * $boxInnerWidth) + "╮") -ForegroundColor $BorderColor
    Write-Host ("    │" + (" " * $boxInnerWidth) + "│") -ForegroundColor $BorderColor

    foreach ($l in $lines) {
        $chunks = @()
        $maxLineLen = $boxInnerWidth - 4
        if ($l.Length -le $maxLineLen) {
            $chunks = @($l)
        } else {
            $rem = $l
            while ($rem.Length -gt $maxLineLen) {
                $chunks += $rem.Substring(0, $maxLineLen)
                $rem = $rem.Substring($maxLineLen)
            }
            if ($rem.Length -gt 0) { $chunks += $rem }
        }

        foreach ($chunk in $chunks) {
            $padRight = $boxInnerWidth - 4 - $chunk.Length
            if ($padRight -lt 0) { $padRight = 0 }
            Write-Host "    │  " -NoNewline -ForegroundColor $BorderColor
            Write-Host $chunk -NoNewline -ForegroundColor $CodeColor
            Write-Host ((" " * $padRight) + "  │") -ForegroundColor $BorderColor
        }
    }

    Write-Host ("    │" + (" " * $boxInnerWidth) + "│") -ForegroundColor $BorderColor
    Write-Host ("    ╰" + ("─" * $boxInnerWidth) + "╯") -ForegroundColor $BorderColor
    Write-Host ""
}

function Show-AiActionMenu {
    $tEnter = Get-TerminalAiText "MenuEnter"
    $tCopy = Get-TerminalAiText "MenuCopy"
    $tInsert = Get-TerminalAiText "MenuInsert"
    $tExplain = Get-TerminalAiText "MenuExplain"
    $tAsk = Get-TerminalAiText "MenuAsk"
    $tCancel = Get-TerminalAiText "MenuCancel"

    Write-Host "    [Enter] " -NoNewline -ForegroundColor Green
    Write-Host ("{0,-18}" -f $tEnter) -NoNewline -ForegroundColor White
    Write-Host "[C] " -NoNewline -ForegroundColor Yellow
    Write-Host ("{0,-18}" -f $tCopy) -NoNewline -ForegroundColor White
    Write-Host "[I] " -NoNewline -ForegroundColor Cyan
    Write-Host $tInsert -ForegroundColor White

    Write-Host "    [X]     " -NoNewline -ForegroundColor DarkYellow
    Write-Host ("{0,-18}" -f $tExplain) -NoNewline -ForegroundColor White
    Write-Host "[A] " -NoNewline -ForegroundColor Magenta
    Write-Host ("{0,-18}" -f $tAsk) -NoNewline -ForegroundColor White
    Write-Host " [Esc] " -NoNewline -ForegroundColor Gray
    Write-Host "$tCancel`n" -ForegroundColor White
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
        [string[]]$AllowedActions = @('Execute', 'Copy', 'Insert', 'Ask', 'Explain', 'Cancel')
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

        # 4. I (Insert) - англійська I/i, українська І/і, або фізична I в укр розкладці (Ш/ш)
        if ('Insert' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::I -or $vk -eq 73 -or $keyChar -in @('i', 'I', 'і', 'І', 'ш', 'Ш')) {
                return 'Insert'
            }
        }

        # 5. A (Ask) - англійська A/a, українська А/а, або фізична A в укр розкладці (Ф/ф)
        if ('Ask' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::A -or $vk -eq 65 -or $keyChar -in @('a', 'A', 'а', 'А', 'ф', 'Ф')) {
                return 'Ask'
            }
        }

        # 6. X (Explain) - англійська X/x, українська Х/х, або фізична X в укр розкладці (Ч/ч)
        if ('Explain' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::X -or $vk -eq 88 -or $keyChar -in @('x', 'X', 'х', 'Х', 'ч', 'Ч')) {
                return 'Explain'
            }
        }
    }
}

function Invoke-OllamaApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$SystemPrompt = "",
        [string]$Model,
        [double]$Temperature,
        [switch]$Stream
    )

    $cfg = Get-TerminalAiConfig
    $targetModel = if ($Model) { $Model } else { $cfg.Model }
    $targetUrl = "$($cfg.OllamaUrl.TrimEnd('/'))/api/generate"
    $targetTemp = if ($PSBoundParameters.ContainsKey('Temperature')) { $Temperature } else { $cfg.Temperature }

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
        Write-Host ("    " + ("─" * 66)) + "`n" -ForegroundColor DarkCyan
    }
}

function Get-AiSystemPrompt {
    return @"
You are an elite PowerShell 7 and Windows Systems engineer.
Target Environment: PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) on Windows.
Goal: Translate the user's natural language request into a single, efficient, idiomatic, robust PowerShell command or pipeline.
Rules:
1. Output ONLY the raw executable PowerShell code without markdown or explanations.
2. Always prefer standard, robust PowerShell cmdlets: Get-Process (prefer over Get-Counter for process inspection), Get-ChildItem, Where-Object, Select-Object, Measure-Object, Sort-Object.
3. NEVER use fragile performance counter paths like Get-Counter '\Process(*)\% Processor Time' unless specifically asked for counter samples.
4. NEVER hallucinate or invent fake cmdlets. Only use genuine PowerShell 7 cmdlets or installed tools.
5. If the user asks about the active model, settings, or configuration, return: Get-TerminalAiConfig
6. If the user asks to list installed models, return: Show-TerminalAiModels
7. If the action is potentially destructive, include safe filtering and never use -Force or -Recurse recklessly.
"@
}

function Invoke-AiCommand {
    <#
    .SYNOPSIS
        Генерує команду PowerShell за описом природною мовою через локальну Ollama.
    .DESCRIPTION
        Приймає запит українською або англійською, генерує команду PowerShell,
        пропонує варіанти: виконати, скопіювати, вставити у буфер, пояснити або скасувати.
    .EXAMPLE
        ai знайти всі файли більше 100MB у поточній папці
    .EXAMPLE
        ai which model do you use to autocomplete?
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

        [switch]$Explain,

        [Alias("chat", "question")]
        [switch]$Ask,

        [string]$Model
    )

    $cfg = Get-TerminalAiConfig
    $fullPrompt = if ($Prompt) { ($Prompt -join " ").Trim() } else { "" }
    $isUk = ($cfg.Language -ne "en")

    if ([string]::IsNullOrWhiteSpace($fullPrompt)) {
        Write-Host ""
        if ($isUk) {
            Write-Host "    ✦ Terminal AI • Швидка довідка" -ForegroundColor Cyan
            Write-Host "    ╭──────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
            Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
            Write-Host "    │   Використання:  ai <опис команди природною мовою>               │" -ForegroundColor White
            Write-Host "    │                  ?? <опис команди>                               │" -ForegroundColor White
            Write-Host "    │                  F2 (інлайн-генерація з живим таймером)          │" -ForegroundColor Yellow
            Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
            Write-Host "    │   Приклади:                                                      │" -ForegroundColor DarkCyan
            Write-Host "    │     ai показати 5 процесів з найбільшим CPU                      │" -ForegroundColor Green
            Write-Host "    │     ai знайти всі файли .log більше 50MB                         │" -ForegroundColor Green
            Write-Host "    │     ai model <модель>   (змінити модель Ollama)                  │" -ForegroundColor Green
            Write-Host "    │     ai models           (список встановлених моделей)            │" -ForegroundColor Green
            Write-Host "    │     ai font <шрифт>     (обрати шрифт Windows Terminal)          │" -ForegroundColor Green
            Write-Host "    │     ai fonts            (список моноширинних шрифтів)            │" -ForegroundColor Green
            Write-Host "    │     ai lang uk | en     (перемкнути мову інтерфейсу)             │" -ForegroundColor Green
            Write-Host "    │     ai lang permanent uk|en (встановити постійну мову)           │" -ForegroundColor Green
            Write-Host "    │     ai-chat             (інтерактивний агент з Tab-доповненням)  │" -ForegroundColor Green
            Write-Host "    │     ai-fix              (аналіз та виправлення помилки)          │" -ForegroundColor Green
            Write-Host "    │     ai-script `"бекграундний бекап`" (генератор .ps1)              │" -ForegroundColor Green
            Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
            Write-Host "    ╰──────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        } else {
            Write-Host "    ✦ Terminal AI • Quick Reference" -ForegroundColor Cyan
            Write-Host "    ╭──────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
            Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
            Write-Host "    │   Usage:         ai <natural language prompt>                    │" -ForegroundColor White
            Write-Host "    │                  ?? <prompt>                                     │" -ForegroundColor White
            Write-Host "    │                  F2 (inline generation with live timer)          │" -ForegroundColor Yellow
            Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
            Write-Host "    │   Examples:                                                      │" -ForegroundColor DarkCyan
            Write-Host "    │     ai show top 5 processes by CPU usage                         │" -ForegroundColor Green
            Write-Host "    │     ai find all .log files larger than 50MB                      │" -ForegroundColor Green
            Write-Host "    │     ai model <name>     (change active Ollama model)             │" -ForegroundColor Green
            Write-Host "    │     ai models           (view installed models)                  │" -ForegroundColor Green
            Write-Host "    │     ai font <name>      (change Windows Terminal font)           │" -ForegroundColor Green
            Write-Host "    │     ai fonts            (list monospace fonts)                   │" -ForegroundColor Green
            Write-Host "    │     ai lang en | uk     (switch interface language)              │" -ForegroundColor Green
            Write-Host "    │     ai lang permanent en|uk (set permanent default language)     │" -ForegroundColor Green
            Write-Host "    │     ai-chat             (interactive agent with Tab complete)    │" -ForegroundColor Green
            Write-Host "    │     ai-fix              (diagnose and fix last error)            │" -ForegroundColor Green
            Write-Host "    │     ai-script `"backup logs`" (generate .ps1 script)               │" -ForegroundColor Green
            Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
            Write-Host "    ╰──────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        }
        Write-Host ""
        return
    }

    $activeModel = if ($Model) { $Model } else { $cfg.Model }

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

        Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
        Write-Host "    ╰──────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "    💡 $hintModel" -ForegroundColor DarkGray
        Write-Host "    💡 $hintFont" -ForegroundColor DarkGray
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

    # 4. Якщо явно запитано текстову відповідь (-Ask)
    if ($Ask) {
        Show-AiAnswer -Question $fullPrompt -Model $activeModel
        return
    }

    Write-Host "`n  ✦ $(Get-TerminalAiText 'Connecting') ($activeModel)..." -ForegroundColor Cyan

    $systemPrompt = Get-AiSystemPrompt
    $rawResponse = Invoke-OllamaApi -Prompt $fullPrompt -SystemPrompt $systemPrompt -Model $activeModel -Temperature 0.0
    if ([string]::IsNullOrWhiteSpace($rawResponse)) {
        return
    }

    # Очищаємо залишки буфера перед виведенням результату та меню дій
    Clear-AiInputBuffer

    $command = Format-AiCodeOutput -Text $rawResponse

    # 5. Перевірка на неіснуючий командлет (запобігання галюцинаціям)
    $firstWord = ($command.Trim() -split '[\s|\(]')[0].TrimStart('(').Trim()
    $isUnknownCmdlet = $false
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
        Invoke-Expression $command
        return
    }

    # Якщо вказано -Explain
    if ($Explain) {
        Show-AiExplanation -Command $command -Model $activeModel
        return
    }

    # Дворівневе структуроване меню дій
    Show-AiActionMenu

    $action = Get-AiMenuKeyPress -AllowedActions @('Execute', 'Copy', 'Insert', 'Ask', 'Explain', 'Cancel')
    switch ($action) {
        'Execute' {
            Write-Host "    ▶ $(Get-TerminalAiText 'Executing')`n" -ForegroundColor Yellow
            Invoke-Expression $command
        }
        'Cancel' {
            Write-Host "    $(Get-TerminalAiText 'Canceled')`n" -ForegroundColor DarkGray
        }
        'Copy' {
            Set-Clipboard -Value $command
            Write-Host "    ✔ $(Get-TerminalAiText 'Copied')`n" -ForegroundColor Green
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
        }
        'Ask' {
            Show-AiAnswer -Question $fullPrompt -Model $activeModel
        }
        'Explain' {
            Write-Host ""
            Show-AiExplanation -Command $command -Model $activeModel
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

    $response = Invoke-OllamaApi -Prompt $fixPrompt -Model $activeModel -Temperature 0.2
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
        Show-AiCodeCard -Code $fixedCode -Title (Get-TerminalAiText "CardTitleFixed") -Model $activeModel -CodeColor Green

        Write-Host "    [Enter] " -NoNewline -ForegroundColor Green
        Write-Host ("{0,-18}" -f (Get-TerminalAiText "MenuEnter")) -NoNewline -ForegroundColor White
        Write-Host "[C] " -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,-18}" -f (Get-TerminalAiText "MenuCopy")) -NoNewline -ForegroundColor White
        Write-Host "[I] " -NoNewline -ForegroundColor Cyan
        Write-Host (Get-TerminalAiText "MenuInsert") -ForegroundColor White
        Write-Host "    [Esc]   " -NoNewline -ForegroundColor Gray
        Write-Host (Get-TerminalAiText "MenuCancel") + "`n" -ForegroundColor White

        $fixAction = Get-AiMenuKeyPress -AllowedActions @('Execute', 'Copy', 'Insert', 'Cancel')
        switch ($fixAction) {
            'Execute' {
                Write-Host "    ▶ $(Get-TerminalAiText 'ExecutingFixed')`n" -ForegroundColor Yellow
                Invoke-Expression $fixedCode
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
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        Set-Content -Path $resolvedPath -Value $scriptContent -Encoding UTF8
        Write-Host "  ✔ $(Get-TerminalAiText 'SavedAt') $resolvedPath" -ForegroundColor Green

        if ($Edit) {
            if (Get-Command code -ErrorAction SilentlyContinue) {
                code $resolvedPath
            } else {
                notepad $resolvedPath
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
            Set-Content -Path $savePath -Value $scriptContent -Encoding UTF8
            Write-Host "  ✔ $(Get-TerminalAiText 'SavedAt') $(Convert-Path $savePath)" -ForegroundColor Green
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
            $ollamaUrl = "$($cfg.OllamaUrl.TrimEnd('/'))/api/generate"

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
            $bodyJson = $payload | ConvertTo-Json -Depth 6

            $httpClient = [System.Net.Http.HttpClient]::new()
            $httpClient.Timeout = [TimeSpan]::FromSeconds($cfg.TimeoutSeconds)
            $httpContent = [System.Net.Http.StringContent]::new($bodyJson, [System.Text.Encoding]::UTF8, "application/json")
            $postTask = $httpClient.PostAsync($ollamaUrl, $httpContent)

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
                # Відновлюємо початковий запит якщо відповідь порожня
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, $line)
            }
        }
        catch {
            # Безпечне відновлення рядка у разі винятку
            try {
                $errLine = ""
                $errCursor = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$errLine, [ref]$errCursor)
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $errLine.Length, $line)
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

# --- АЛІАСИ ТА АВТОЗАВАНТАЖЕННЯ МОДУЛЯ ---
Set-Alias -Name ai-font -Value Set-TerminalAiFont
Set-Alias -Name ai-fonts -Value Show-TerminalAiFonts
Set-Alias -Name ai-lang -Value Set-TerminalAiLanguage
Set-Alias -Name ai-lang-permanent -Value Set-TerminalAiDefaultLanguage
Set-Alias -Name ai-lang-default -Value Set-TerminalAiDefaultLanguage
Set-Alias -Name ai-chat -Value Invoke-AiAssistant
Set-Alias -Name ai-assistant -Value Invoke-AiAssistant

Register-TerminalAiKeyHandler

# Експорт функцій та аліасів
Export-ModuleMember -Function @(
    "Invoke-AiCommand",
    "Invoke-AiFix",
    "New-AiScript",
    "Invoke-AiAssistant",
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
    "Get-AiMenuKeyPress"
) -Alias @(
    "ai",
    "??",
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
