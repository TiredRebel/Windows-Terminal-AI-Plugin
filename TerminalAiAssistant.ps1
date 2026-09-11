# TerminalAiAssistant.ps1 - Інтерактивний AI-Асистент для Windows Terminal (Спліт-панель / Окремий агент)
# Може запускатися через 'ai-chat', у боковій панелі Windows Terminal або як окремий скрипт

param(
    [string]$Model
)

$PSScriptRootCurrent = Split-Path -Parent $MyInvocation.MyCommand.Definition
$modulePath = Join-Path $PSScriptRootCurrent "TerminalAI.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}

$cfg = Get-TerminalAiConfig
$activeModel = if ($Model) { $Model } else { $cfg.Model }

function Get-AssistantDict {
    param([string]$Lang)
    $dict = @{
        "uk" = @{
            "Title"           = "TERMINAL AI ASSISTANT (OLLAMA LOCAL)"
            "ModelLabel"      = "Модель:"
            "EndpointLabel"   = "Ендпоінт:"
            "LangLabel"       = "Мова:"
            "CommandsHeader"  = "Доступні команди:"
            "DescHelp"        = "Показати детальну довідку з командами"
            "DescModels"      = "Переглянути встановлені моделі Ollama"
            "DescModel"       = "Змінити активну модель"
            "DescLang"        = "Змінити мову (наприклад: /lang permanent uk)"
            "DescCopy"        = "Скопіювати останній згенерований блок коду"
            "DescSave"        = "Зберегти останній код у файл .ps1"
            "DescClear"       = "Очистити екран"
            "DescExit"        = "Вийти з асистента"
            "TabHint"         = "💡 Підказка: натискайте Tab для автодоповнення слеш-команд (/help, /models, /model, /lang)!"
            "PromptInvitation"= "Задайте питання або опишіть потрібний скрипт (українською чи англійською):"
            "PromptLabel"     = "🤖 AI-Prompt> "
            "Thinking"        = "  [AI: Формую відповідь...]"
            "Copied"          = "✔ Останній блок коду скопійовано в буфер обміну!"
            "NoCode"          = "Немає збереженого коду для копіювання."
            "Saved"           = "✔ Скрипт успішно збережено у:"
            "ModelChanged"    = "✔ Активну модель змінено на:"
            "LangChanged"     = "✔ Мову інтерфейсу змінено на українську!"
            "LangChangedPermanent" = "✔ Мову успішно зафіксовано як ПОСТІЙНУ: uk (config.json + `$env:TERMINAL_AI_LANG)!"
            "LangCurrent"     = "Поточна мова: uk (Українська). Щоб перемкнути: /lang en або /lang permanent en"
            "CodeHint"        = "[💡 Підказка: введіть /copy щоб скопіювати згенерований код, або /save щоб зберегти у файл]"
            "Goodbye"         = "До зустрічі!"
            "HelpTitle"       = "✦ Terminal AI Assistant • Швидка довідка"
        }
        "en" = @{
            "Title"           = "TERMINAL AI ASSISTANT (OLLAMA LOCAL)"
            "ModelLabel"      = "Model:"
            "EndpointLabel"   = "Endpoint:"
            "LangLabel"       = "Language:"
            "CommandsHeader"  = "Available commands:"
            "DescHelp"        = "Show detailed command reference"
            "DescModels"      = "View installed Ollama models"
            "DescModel"       = "Change active model"
            "DescLang"        = "Change language (e.g.: /lang permanent en)"
            "DescCopy"        = "Copy last generated code block"
            "DescSave"        = "Save last code to a .ps1 file"
            "DescClear"       = "Clear screen"
            "DescExit"        = "Exit assistant"
            "TabHint"         = "💡 Tip: press Tab to autocomplete slash-commands (/help, /models, /model, /lang)!"
            "PromptInvitation"= "Ask a question or describe a PowerShell script:"
            "PromptLabel"     = "🤖 AI-Prompt> "
            "Thinking"        = "  [AI: Generating response...]"
            "Copied"          = "✔ Last code block copied to clipboard!"
            "NoCode"          = "No code block available to copy."
            "Saved"           = "✔ Script successfully saved to:"
            "ModelChanged"    = "✔ Active model changed to:"
            "LangChanged"     = "✔ Interface language changed to English!"
            "LangChangedPermanent" = "✔ Language successfully set as PERMANENT: en (config.json + `$env:TERMINAL_AI_LANG)!"
            "LangCurrent"     = "Current language: en (English). To switch: /lang uk or /lang permanent uk"
            "CodeHint"        = "[💡 Hint: type /copy to copy generated code, or /save to save to file]"
            "Goodbye"         = "Goodbye!"
            "HelpTitle"       = "✦ Terminal AI Assistant • Quick Reference"
        }
    }
    $targetLang = if ($Lang -eq "en") { "en" } else { "uk" }
    return $dict[$targetLang]
}

function Show-AssistantHeader {
    param(
        [string]$Model,
        [string]$Lang
    )
    $txt = Get-AssistantDict -Lang $Lang

    try {
        $host.UI.RawUI.WindowTitle = "Terminal AI Assistant [$Model]"
    } catch { }

    try {
        Clear-Host
    } catch { }
    Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              $($txt.Title)                ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host " $($txt.ModelLabel)    " -NoNewline -ForegroundColor Gray
    Write-Host "$Model" -ForegroundColor Green
    Write-Host " $($txt.EndpointLabel) " -NoNewline -ForegroundColor Gray
    Write-Host "$($cfg.OllamaUrl)" -ForegroundColor DarkGray
    Write-Host " $($txt.LangLabel)     " -NoNewline -ForegroundColor Gray
    $langDisplay = if ($Lang -eq "en") { "en (English)" } else { "uk (Українська)" }
    Write-Host "$langDisplay" -ForegroundColor Yellow
    Write-Host " $($txt.CommandsHeader)" -ForegroundColor Gray
    Write-Host "   /help         - $($txt.DescHelp)" -ForegroundColor DarkCyan
    Write-Host "   /models       - $($txt.DescModels)" -ForegroundColor DarkCyan
    Write-Host "   /model <name> - $($txt.DescModel)" -ForegroundColor DarkCyan
    Write-Host "   /lang <uk|en> - $($txt.DescLang)" -ForegroundColor DarkCyan
    Write-Host "   /copy         - $($txt.DescCopy)" -ForegroundColor DarkCyan
    Write-Host "   /save [file]  - $($txt.DescSave)" -ForegroundColor DarkCyan
    Write-Host "   /clear        - $($txt.DescClear)" -ForegroundColor DarkCyan
    Write-Host "   /exit         - $($txt.DescExit)" -ForegroundColor DarkCyan
    Write-Host ("─" * 68) -ForegroundColor DarkGray
    Write-Host "$($txt.TabHint)" -ForegroundColor DarkYellow
    Write-Host "$($txt.PromptInvitation)`n" -ForegroundColor White
}

function Show-AssistantHelpCard {
    param([string]$Lang)
    $txt = Get-AssistantDict -Lang $Lang
    $isUk = ($Lang -ne "en")

    Write-Host ""
    Write-Host "    $($txt.HelpTitle)" -ForegroundColor Cyan
    Write-Host "    ╭──────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
    Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
    $items = @(
        @{ Cmd = "/help";         Desc = $txt.DescHelp },
        @{ Cmd = "/models";       Desc = $txt.DescModels },
        @{ Cmd = "/model <name>"; Desc = $txt.DescModel },
        @{ Cmd = "/lang [perm]";  Desc = $txt.DescLang },
        @{ Cmd = "/copy";         Desc = $txt.DescCopy },
        @{ Cmd = "/save [file]";  Desc = $txt.DescSave },
        @{ Cmd = "/clear";        Desc = $txt.DescClear },
        @{ Cmd = "/exit";         Desc = $txt.DescExit }
    )
    foreach ($it in $items) {
        $row = "    │   {0,-14} - {1,-46}│" -f $it.Cmd, $it.Desc
        Write-Host $row -ForegroundColor White
    }
    Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
    Write-Host "    ╰──────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
    Write-Host ""
    if ($isUk) {
        Write-Host "    💡 Автодоповнення: наберіть '/' і натисніть Tab для вибору команди!" -ForegroundColor DarkGray
        Write-Host "    💡 Модель: наберіть '/model ' і натисніть Tab для вибору встановленої моделі Ollama" -ForegroundColor DarkGray
        Write-Host "    💡 Мова: наберіть '/lang ' і натисніть Tab (uk, en, permanent uk, permanent en)`n" -ForegroundColor DarkGray
    } else {
        Write-Host "    💡 Autocomplete: type '/' and press Tab to cycle through slash-commands!" -ForegroundColor DarkGray
        Write-Host "    💡 Model: type '/model ' and press Tab to cycle through installed Ollama models" -ForegroundColor DarkGray
        Write-Host "    💡 Language: type '/lang ' and press Tab (en, uk, permanent en, permanent uk)`n" -ForegroundColor DarkGray
    }
}

function Read-AssistantLine {
    param(
        [string]$Prompt = "🤖 AI-Prompt> "
    )

    Write-Host $Prompt -NoNewline -ForegroundColor Green

    # Якщо ввід перенаправлено (automated/non-interactive), використовуємо стандартний Read-Host
    if ([Console]::IsInputRedirected) {
        return (Read-Host)
    }

    $slashCommands = @("/help", "/models", "/model", "/lang", "/copy", "/save", "/clear", "/exit")
    $buffer = [System.Text.StringBuilder]::new()
    $tabMatches = @()
    $tabIndex = -1
    $lastWasTab = $false

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $vk = $key.VirtualKeyCode
        $ch = $key.Character

        # Tab (VK 9) - автодоповнення
        if ($vk -eq 9) {
            $currText = $buffer.ToString()
            if (-not $lastWasTab) {
                if ($currText.StartsWith("/model ")) {
                    $prefix = $currText.Substring(7).Trim()
                    try {
                        $models = (Get-TerminalAiModels).name
                        $tabMatches = @($models | Where-Object { $_ -like "$prefix*" } | ForEach-Object { "/model $_" })
                    } catch { $tabMatches = @() }
                } elseif ($currText.StartsWith("/lang ")) {
                    $prefix = $currText.Substring(6).Trim()
                    $langOptions = @("uk", "en", "permanent uk", "permanent en")
                    $tabMatches = @($langOptions | Where-Object { $_ -like "$prefix*" } | ForEach-Object { "/lang $_" })
                } elseif ($currText.StartsWith("/")) {
                    $tabMatches = @($slashCommands | Where-Object { $_ -like "$currText*" })
                } else {
                    $tabMatches = @($slashCommands)
                }
                $tabIndex = 0
            } else {
                $tabIndex++
            }

            if ($tabMatches.Count -gt 0) {
                $selected = $tabMatches[$tabIndex % $tabMatches.Count]

                $eraseCount = $buffer.Length
                if ($eraseCount -gt 0) {
                    $backspaces = "`b" * $eraseCount
                    $spaces = " " * $eraseCount
                    [Console]::Write($backspaces + $spaces + $backspaces)
                }

                $buffer.Clear() | Out-Null
                $buffer.Append($selected) | Out-Null
                [Console]::Write($selected)
            }

            $lastWasTab = $true
            continue
        }

        $lastWasTab = $false

        # Enter (VK 13)
        if ($vk -eq 13) {
            [Console]::WriteLine()
            return $buffer.ToString()
        }

        # Backspace (VK 8)
        if ($vk -eq 8) {
            if ($buffer.Length -gt 0) {
                $buffer.Remove($buffer.Length - 1, 1) | Out-Null
                [Console]::Write("`b `b")
            }
            continue
        }

        # Escape (VK 27) - очистити рядок
        if ($vk -eq 27) {
            $eraseCount = $buffer.Length
            if ($eraseCount -gt 0) {
                $backspaces = "`b" * $eraseCount
                $spaces = " " * $eraseCount
                [Console]::Write($backspaces + $spaces + $backspaces)
            }
            $buffer.Clear() | Out-Null
            continue
        }

        # Звичайні символи
        if (-not [char]::IsControl($ch)) {
            $buffer.Append($ch) | Out-Null
            [Console]::Write($ch)
        }
    }
}

$currentLang = if ($cfg.Language -eq "en") { "en" } else { "uk" }
Show-AssistantHeader -Model $activeModel -Lang $currentLang

$lastCodeBlock = ""

while ($true) {
    $txt = Get-AssistantDict -Lang $currentLang
    $inputQuery = Read-AssistantLine -Prompt $txt.PromptLabel

    if ([string]::IsNullOrWhiteSpace($inputQuery)) { continue }
    $inputQuery = $inputQuery.Trim().Trim([char]0xFEFF, [char]0x200B)

    # Обробка службових команд
    if ($inputQuery -in @("/exit", "exit", "quit", ":q")) {
        Write-Host "$($txt.Goodbye)`n" -ForegroundColor Cyan
        break
    }
    elseif ($inputQuery -in @("/help", "/?", "help", "?")) {
        Show-AssistantHelpCard -Lang $currentLang
        continue
    }
    elseif ($inputQuery -in @("/clear", "clear", "cls")) {
        Show-AssistantHeader -Model $activeModel -Lang $currentLang
        continue
    }
    elseif ($inputQuery -eq "/models") {
        Show-TerminalAiModels
        continue
    }
    elseif ($inputQuery -match '^/model(?:\s+(.+))?$') {
        $targetModel = $Matches[1]
        if ([string]::IsNullOrWhiteSpace($targetModel)) {
            Show-TerminalAiModels
        } else {
            $activeModel = $targetModel.Trim()
            Set-TerminalAiConfig -Model $activeModel | Out-Null
            $host.UI.RawUI.WindowTitle = "Terminal AI Assistant [$activeModel]"
            Write-Host "$($txt.ModelChanged) $activeModel`n" -ForegroundColor Green
        }
        continue
    }
    elseif ($inputQuery -match '^/lang(?:-permanent)?(?:\s+(.+))?$') {
        $rawArg = $Matches[1]
        if ([string]::IsNullOrWhiteSpace($rawArg)) {
            Write-Host "$($txt.LangCurrent)`n" -ForegroundColor Yellow
        } else {
            $parts = $rawArg.Trim().ToLower() -split '\s+'
            $targetLang = ""
            $isPermanent = $inputQuery.StartsWith("/lang-permanent")
            foreach ($p in $parts) {
                if ($p -in @("permanent", "save", "default", "--permanent", "-p", "постійно")) {
                    $isPermanent = $true
                } elseif ($p -in @("en", "eng", "english")) {
                    $targetLang = "en"
                } elseif ($p -in @("uk", "ua", "ukr", "ukrainian")) {
                    $targetLang = "uk"
                }
            }
            if (-not $targetLang) {
                $targetLang = if ($parts[0] -in @("en", "eng", "english")) { "en" } else { "uk" }
            }
            $currentLang = $targetLang
            if ($isPermanent) {
                Set-TerminalAiLanguage -Language $currentLang -Permanent | Out-Null
            } else {
                Set-TerminalAiLanguage -Language $currentLang -Permanent | Out-Null
            }
            $txt = Get-AssistantDict -Lang $currentLang
            if ($isPermanent) {
                Write-Host "$($txt.LangChangedPermanent)`n" -ForegroundColor Green
            } else {
                Write-Host "$($txt.LangChanged)`n" -ForegroundColor Green
            }
        }
        continue
    }
    elseif ($inputQuery -eq "/copy") {
        if (-not [string]::IsNullOrWhiteSpace($lastCodeBlock)) {
            Set-Clipboard -Value $lastCodeBlock
            Write-Host "$($txt.Copied)`n" -ForegroundColor Green
        } else {
            Write-Host "$($txt.NoCode)`n" -ForegroundColor Yellow
        }
        continue
    }
    elseif ($inputQuery -match '^/save(?:\s+(.+))?$') {
        if ([string]::IsNullOrWhiteSpace($lastCodeBlock)) {
            Write-Host "$($txt.NoCode)`n" -ForegroundColor Yellow
            continue
        }
        $targetFile = $Matches[1]
        if ([string]::IsNullOrWhiteSpace($targetFile)) {
            $targetFile = "ai_script_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".ps1"
        }
        Set-Content -Path $targetFile -Value $lastCodeBlock -Encoding UTF8
        Write-Host "$($txt.Saved) $(Convert-Path $targetFile)`n" -ForegroundColor Green
        continue
    }

    $langInstruction = if ($currentLang -eq "uk") { "Respond strictly in Ukrainian language." } else { "Respond in English." }
    $systemPrompt = @"
You are Terminal AI Assistant, an interactive engineering companion built for PowerShell and Windows Terminal.
Current Environment: PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) on Windows.
$langInstruction
Help the user create robust scripts, troubleshoot errors, automate workflows, and inspect system architecture.
Always prefer clean, idiomatic PowerShell 7 syntax. Format scripts in markdown code blocks.
"@

    Write-Host "`n$($txt.Thinking)`n" -ForegroundColor DarkGray

    $reply = Invoke-OllamaApi -Prompt $inputQuery -SystemPrompt $systemPrompt -Model $activeModel -Temperature 0.3
    if ($reply) {
        Write-Host $reply -ForegroundColor White

        if ($reply -match '(?s)```(?:powershell|pwsh)?\r?\n?(.*?)\r?\n?```') {
            $lastCodeBlock = $Matches[1].Trim()
            Write-Host "`n$($txt.CodeHint)" -ForegroundColor DarkCyan
        }
    }

    Write-Host "`n" + ("─" * 68) -ForegroundColor DarkGray
}
