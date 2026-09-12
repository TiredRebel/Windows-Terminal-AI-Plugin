# TerminalAiAssistant.ps1 - Інтерактивний AI-Асистент для Windows Terminal (Спліт-панель / Окремий агент)
# Може запускатися через 'ai-chat', у боковій панелі Windows Terminal або як окремий скрипт

param(
    [string]$Model
)

# Забезпечуємо повну підтримку UTF-8 для консолі
try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

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
            "DescReset"       = "Скинути історію діалогу (нова сесія)"
            "DescContext"     = "Переглянути історію та контекст діалогу"
            "DescInspect"     = "Інспекція поточного PowerShell середовища"
            "DescRun"         = "Виконати останній згенерований код (з підтвердженням)"
            "DescRead"        = "Прочитати локальний файл та переглянути/додати до контексту"
            "DescExit"        = "Вийти з асистента"
            "TabHint"         = "💡 Підказка: натискайте Tab для автодоповнення слеш-команд (/help, /run, /read, /reset, /inspect)!"
            "PromptInvitation"= "Задайте питання або опишіть потрібний скрипт (українською чи англійською):"
            "PromptLabel"     = "🤖 AI-Prompt> "
            "Thinking"        = "  [AI: Формую відповідь...]"
            "Copied"          = "✔ Останній блок коду скопійовано в буфер обміну!"
            "NoCode"          = "Немає збереженого коду для копіювання чи виконання."
            "Saved"           = "✔ Скрипт успішно збережено у:"
            "ModelChanged"    = "✔ Активну модель змінено на:"
            "LangChanged"     = "✔ Мову інтерфейсу змінено на українську!"
            "LangChangedPermanent" = "✔ Мову успішно зафіксовано як ПОСТІЙНУ: uk (config.json + `$env:TERMINAL_AI_LANG)!"
            "LangCurrent"     = "Поточна мова: uk (Українська). Щоб перемкнути: /lang en або /lang permanent en"
            "ContextReset"    = "✔ Історію діалогу, журнал системних помилок та збережений код успішно очищено! Розпочато нову чисту сесію."
            "ContextEmpty"    = "Історія діалогу наразі порожня."
            "ContextTurns"    = "✦ Історія діалогу (повідомлень у контексті: {0}):"
            "EnvTitle"        = "✦ Інспекція середовища Windows Terminal AI:"
            "RunPrompt"       = "Підтвердження виконання PowerShell коду:"
            "RunConfirm"      = "Виконати цей код зараз?"
            "Running"         = "Виконання коду..."
            "RunSuccess"      = "Код успішно виконано!"
            "RunError"        = "Помилка під час виконання"
            "AskFix"          = "Бажаєте передати цю помилку AI для аналізу та виправлення?"
            "RunCancelled"    = "Виконання скасовано користувачем."
            "CodeHint"        = "[💡 Підказка: введіть /run щоб виконати код, /copy щоб скопіювати, або /save щоб зберегти у файл]"
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
            "DescReset"       = "Reset conversation history (fresh session)"
            "DescContext"     = "View conversation history and context"
            "DescInspect"     = "Inspect current PowerShell environment"
            "DescRun"         = "Execute last generated code (with confirmation)"
            "DescRead"        = "Read local file and inspect/add to context"
            "DescExit"        = "Exit assistant"
            "TabHint"         = "💡 Tip: press Tab to autocomplete slash-commands (/help, /run, /read, /reset, /inspect)!"
            "PromptInvitation"= "Ask a question or describe a PowerShell script:"
            "PromptLabel"     = "🤖 AI-Prompt> "
            "Thinking"        = "  [AI: Generating response...]"
            "Copied"          = "✔ Last code block copied to clipboard!"
            "NoCode"          = "No code block available to copy or execute."
            "Saved"           = "✔ Script successfully saved to:"
            "ModelChanged"    = "✔ Active model changed to:"
            "LangChanged"     = "✔ Interface language changed to English!"
            "LangChangedPermanent" = "✔ Language successfully set as PERMANENT: en (config.json + `$env:TERMINAL_AI_LANG)!"
            "LangCurrent"     = "Current language: en (English). To switch: /lang uk or /lang permanent uk"
            "ContextReset"    = "✔ Conversation history, system error log, and cached code successfully cleared! Starting fresh session."
            "ContextEmpty"    = "Conversation history is currently empty."
            "ContextTurns"    = "✦ Conversation history ({0} messages in context):"
            "EnvTitle"        = "✦ Environment Inspection for Windows Terminal AI:"
            "RunPrompt"       = "PowerShell code execution confirmation:"
            "RunConfirm"      = "Execute this code now?"
            "Running"         = "Executing code..."
            "RunSuccess"      = "Code executed successfully!"
            "RunError"        = "Execution error"
            "AskFix"          = "Would you like AI to analyze and fix this error?"
            "RunCancelled"    = "Execution cancelled by user."
            "CodeHint"        = "[💡 Hint: type /run to execute code, /copy to copy, or /save to save to file]"
            "Goodbye"         = "Goodbye!"
            "HelpTitle"       = "✦ Terminal AI Assistant • Quick Reference"
        }
    }
    $targetLang = if ($Lang -in @("uk", "ua")) { "uk" } else { "en" }
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
    $langDisplay = if ($Lang -in @("uk", "ua")) { "uk (Українська)" } else { "en (English)" }
    Write-Host "$langDisplay" -ForegroundColor Yellow
    Write-Host " $($txt.CommandsHeader)" -ForegroundColor Gray
    Write-Host "   /help         - $($txt.DescHelp)" -ForegroundColor DarkCyan
    Write-Host "   /run          - $($txt.DescRun)" -ForegroundColor DarkCyan
    Write-Host "   /read <path>  - $($txt.DescRead)" -ForegroundColor DarkCyan
    Write-Host "   /models       - $($txt.DescModels)" -ForegroundColor DarkCyan
    Write-Host "   /model <name> - $($txt.DescModel)" -ForegroundColor DarkCyan
    Write-Host "   /lang <uk|en> - $($txt.DescLang)" -ForegroundColor DarkCyan
    Write-Host "   /context      - $($txt.DescContext)" -ForegroundColor DarkCyan
    Write-Host "   /reset        - $($txt.DescReset)" -ForegroundColor DarkCyan
    Write-Host "   /inspect      - $($txt.DescInspect)" -ForegroundColor DarkCyan
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
    $isUk = ($Lang -in @("uk", "ua"))

    Write-Host ""
    Write-Host "    $($txt.HelpTitle)" -ForegroundColor Cyan
    Write-Host "    ╭──────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
    Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
    $items = @(
        @{ Cmd = "/help";         Desc = $txt.DescHelp },
        @{ Cmd = "/run";          Desc = $txt.DescRun },
        @{ Cmd = "/read <file>";  Desc = $txt.DescRead },
        @{ Cmd = "/models";       Desc = $txt.DescModels },
        @{ Cmd = "/model <name>"; Desc = $txt.DescModel },
        @{ Cmd = "/lang [perm]";  Desc = $txt.DescLang },
        @{ Cmd = "/context";      Desc = $txt.DescContext },
        @{ Cmd = "/reset";        Desc = $txt.DescReset },
        @{ Cmd = "/inspect";      Desc = $txt.DescInspect },
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
        Write-Host "    💡 Виконання: наберіть '/run' для безпечного запуску останнього згенерованого коду" -ForegroundColor DarkGray
        Write-Host "    💡 Читання файлу: наберіть '/read <файл>' для інспекції файлів робочої папки`n" -ForegroundColor DarkGray
    } else {
        Write-Host "    💡 Autocomplete: type '/' and press Tab to cycle through slash-commands!" -ForegroundColor DarkGray
        Write-Host "    💡 Execution: type '/run' to safely execute the last generated code block" -ForegroundColor DarkGray
        Write-Host "    💡 File reader: type '/read <file>' to inspect local files in workspace`n" -ForegroundColor DarkGray
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

    $slashCommands = @("/help", "/models", "/model", "/lang", "/context", "/reset", "/inspect", "/run", "/read", "/copy", "/save", "/clear", "/exit")
    $buffer = [System.Text.StringBuilder]::new()
    $tabMatches = @()
    $tabIndex = -1
    $lastWasTab = $false

    while ($true) {
        $vk = 0
        $ch = [char]0

        try {
            $keyInfo = [System.Console]::ReadKey($true)
            $vk = [int]$keyInfo.Key
            $ch = $keyInfo.KeyChar
        }
        catch {
            try {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $vk = $key.VirtualKeyCode
                $ch = $key.Character
            }
            catch {
                return (Read-Host)
            }
        }

        # Ctrl+C (VK 3)
        if ([int]$ch -eq 3) {
            Write-Host "^C"
            return ""
        }

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
                } elseif ($currText.StartsWith("/read ")) {
                    $prefix = $currText.Substring(6).Trim()
                    try {
                        $searchFilter = if ([string]::IsNullOrWhiteSpace($prefix)) { "*" } else { "$prefix*" }
                        $files = @(Get-ChildItem -Path . -File -Filter $searchFilter -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                        if ($files.Count -eq 0 -and (Test-Path $PSScriptRoot)) {
                            $files = @(Get-ChildItem -Path $PSScriptRoot -File -Filter $searchFilter -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                        }
                        $tabMatches = @($files | ForEach-Object { "/read $_" })
                    } catch { $tabMatches = @() }
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
                    Write-Host -NoNewline ("`b" * $eraseCount + " " * $eraseCount + "`b" * $eraseCount)
                }

                $buffer.Clear() | Out-Null
                $buffer.Append($selected) | Out-Null
                Write-Host -NoNewline $selected
            }

            $lastWasTab = $true
            continue
        }

        $lastWasTab = $false

        # Enter (VK 13)
        if ($vk -eq 13) {
            Write-Host ""
            return $buffer.ToString()
        }

        # Backspace (VK 8)
        if ($vk -eq 8) {
            if ($buffer.Length -gt 0) {
                $buffer.Remove($buffer.Length - 1, 1) | Out-Null
                Write-Host -NoNewline "`b `b"
            }
            continue
        }

        # Escape (VK 27) - очистити рядок
        if ($vk -eq 27) {
            $eraseCount = $buffer.Length
            if ($eraseCount -gt 0) {
                Write-Host -NoNewline ("`b" * $eraseCount + " " * $eraseCount + "`b" * $eraseCount)
            }
            $buffer.Clear() | Out-Null
            continue
        }

        # Звичайні символи (з повною підтримкою Unicode, кирилиці та пробілів)
        if (-not [char]::IsControl($ch) -and [int]$ch -gt 0) {
            $buffer.Append($ch) | Out-Null
            Write-Host -NoNewline $ch
        }
    }
}

function Add-AssistantHistoryMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [int]$MaxHistory = 16
    )

    if ($null -eq $script:AiChatHistory) {
        $script:AiChatHistory = [System.Collections.Generic.List[hashtable]]::new()
    }

    # Детерміноване маскування секретних даних перед збереженням у контекст
    $sanitized = if (Get-Command Protect-AiSecretData -ErrorAction SilentlyContinue) {
        Protect-AiSecretData -Text $Content
    } else {
        $Content
    }

    $script:AiChatHistory.Add(@{ role = $Role; content = $sanitized })

    # FIFO обмеження глибини контексту
    while ($script:AiChatHistory.Count -gt $MaxHistory) {
        $script:AiChatHistory.RemoveAt(0)
    }
}

$currentLang = if ($cfg.Language -in @("uk", "ua")) { "uk" } else { "en" }
Show-AssistantHeader -Model $activeModel -Lang $currentLang

$lastCodeBlock = ""
$script:AiChatHistory = [System.Collections.Generic.List[hashtable]]::new()

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
    elseif ($inputQuery -in @("/reset", "/new", "reset", "clear-history")) {
        $script:AiChatHistory.Clear()
        $lastCodeBlock = ""
        $global:Error.Clear()
        Write-Host "$($txt.ContextReset)`n" -ForegroundColor Green
        continue
    }
    elseif ($inputQuery -in @("/context", "/history", "history")) {
        if ($script:AiChatHistory.Count -eq 0) {
            Write-Host "$($txt.ContextEmpty)`n" -ForegroundColor Yellow
        } else {
            $headerMsg = $txt.ContextTurns -f $script:AiChatHistory.Count
            Write-Host "`n$headerMsg" -ForegroundColor Cyan
            $turnIdx = 1
            for ($i = 0; $i -lt $script:AiChatHistory.Count; $i++) {
                $msgItem = $script:AiChatHistory[$i]
                $roleColor = if ($msgItem.role -eq "user") { "Green" } else { "DarkCyan" }
                $roleLabel = if ($msgItem.role -eq "user") { "🧑 User" } else { "🤖 Assistant" }
                $snippet = if ($msgItem.content.Length -gt 100) { $msgItem.content.Substring(0, 97) + "..." } else { $msgItem.content }
                $snippet = $snippet.Replace("`r", " ").Replace("`n", " ")
                Write-Host "  [$($turnIdx)] ${roleLabel}: $snippet" -ForegroundColor $roleColor
                $turnIdx++
            }
            Write-Host ""
        }
        continue
    }
    elseif ($inputQuery -match '^/inspect(?:\s+(.+))?$') {
        $inspectSub = $Matches[1]
        Write-Host "`n$($txt.EnvTitle)" -ForegroundColor Cyan
        Write-Host "  • PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor Gray
        Write-Host "  • OS: $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
        Write-Host "  • Working Directory: $((Get-Location).Path)" -ForegroundColor Gray
        Write-Host "  • Active Model: $activeModel" -ForegroundColor Gray
        Write-Host "  • Active Language: $currentLang" -ForegroundColor Gray
        if ($global:Error.Count -gt 0) {
            Write-Host "  • Last System Error: $($global:Error[0].Exception.Message)" -ForegroundColor Red
        } else {
            Write-Host "  • Last System Error: None" -ForegroundColor Gray
        }
        if ($inspectSub -match 'add|inject|context') {
            $envNote = "Environment Context: PS $($PSVersionTable.PSVersion), Path: $((Get-Location).Path), LastError: $(if ($global:Error.Count -gt 0) { $global:Error[0].Exception.Message } else { 'None' })"
            Add-AssistantHistoryMessage -Role "user" -Content $envNote
            Write-Host "  ✔ Environment snapshot added to conversation context!" -ForegroundColor Green
        }
        Write-Host ""
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
        Save-AiScriptFile -Path $targetFile -Content $lastCodeBlock
        Write-Host ""
        continue
    }
    elseif ($inputQuery -in @("/run", "/exec", "run", "exec")) {
        if ([string]::IsNullOrWhiteSpace($lastCodeBlock)) {
            Write-Host "$($txt.NoCode)`n" -ForegroundColor Yellow
            continue
        }
        Write-Host "`n✦ $($txt.RunPrompt)" -ForegroundColor Yellow
        Write-Host ("─" * 68) -ForegroundColor DarkGray
        Write-Host $lastCodeBlock -ForegroundColor Cyan
        Write-Host ("─" * 68) -ForegroundColor DarkGray

        $confirm = Read-AssistantLine -Prompt "$($txt.RunConfirm) [y/N]: "
        if ($confirm -match '^(y|yes|так|т)$') {
            Write-Host "`n$($txt.Running)`n" -ForegroundColor Green
            $errCountBefore = $global:Error.Count
            $lastExitBefore = $LASTEXITCODE
            $hasExecutionError = $false
            $capturedErrorMessage = ""
            $wasDeniedOrBlocked = $false

            try {
                $gateRes = Invoke-AiExecutionGate -Command $lastCodeBlock -ReturnOutput -AutoConfirm -PassThru
                if (-not $gateRes.Executed) {
                    if ($gateRes.Status -eq "Denied") {
                        $wasDeniedOrBlocked = $true
                    } else {
                        $hasExecutionError = $true
                        $capturedErrorMessage = "Command execution was blocked ($($gateRes.Status))"
                    }
                } else {
                    # Safely render output stream to host as a coherent collection to preserve formatting pipeline objects
                    if ($null -ne $gateRes.Output) {
                        $gateRes.Output | Out-Host
                    }

                    # Check for any ErrorRecords in the returned output stream
                    $streamErrors = @($gateRes.Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                    if ($streamErrors.Count -gt 0) {
                        $hasExecutionError = $true
                        $firstErr = $streamErrors[0]
                        $capturedErrorMessage = if ($firstErr.Exception -and $firstErr.Exception.Message) {
                            $firstErr.Exception.Message
                        } else {
                            $firstErr.ToString()
                        }
                    }

                    if (-not $hasExecutionError -and ($global:Error.Count -gt $errCountBefore)) {
                        $hasExecutionError = $true
                        $newErr = $global:Error[0]
                        $capturedErrorMessage = if ($newErr.Exception -and $newErr.Exception.Message) {
                            $newErr.Exception.Message
                        } else {
                            $newErr.ToString()
                        }
                    }

                    if (-not $hasExecutionError -and ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $lastExitBefore)) {
                        $hasExecutionError = $true
                        $capturedErrorMessage = "Native process exited with code $LASTEXITCODE"
                    }
                }
            } catch {
                $hasExecutionError = $true
                $capturedErrorMessage = if ($_.Exception -and $_.Exception.Message) {
                    $_.Exception.Message
                } else {
                    $_.ToString()
                }
            }

            if ($wasDeniedOrBlocked) {
                # User declined gate confirmation or execution was blocked non-interactively
            } elseif ($hasExecutionError) {
                Write-Host "`n✖ $($txt.RunError): $capturedErrorMessage`n" -ForegroundColor Red

                # Запитуємо користувача, чи передати помилку AI для негайного аналізу та виправлення
                $fixConfirm = Read-AssistantLine -Prompt "$($txt.AskFix) [Y/n]: "
                if ($fixConfirm -notmatch '^(n|no|ні)$') {
                    $bt3 = '```'
                    $errContext = "When executing this PowerShell command:`n$bt3" + "powershell`n$lastCodeBlock`n$bt3`nAn error occurred:`n$capturedErrorMessage`nPlease analyze this failure and provide a corrected, robust version."
                    Add-AssistantHistoryMessage -Role "user" -Content $errContext

                    Write-Host "`n$($txt.Thinking)`n" -ForegroundColor DarkGray
                    $reply = Invoke-OllamaApi -Messages $script:AiChatHistory -SystemPrompt $systemPrompt -Model $activeModel -Temperature 0.2
                    if ($reply) {
                        Add-AssistantHistoryMessage -Role "assistant" -Content $reply
                        Write-Host $reply -ForegroundColor White

                        if ($reply -match '(?s)```(?:powershell|pwsh)?\r?\n?(.*?)\r?\n?```') {
                            $lastCodeBlock = $Matches[1].Trim()
                            Write-Host "`n$($txt.CodeHint)" -ForegroundColor DarkCyan
                        }
                    }
                }
            } else {
                Write-Host "`n✔ $($txt.RunSuccess)`n" -ForegroundColor Green
            }
        } else {
            Write-Host "$($txt.RunCancelled)`n" -ForegroundColor DarkGray
        }
        continue
    }
    elseif ($inputQuery -match '^/read(?:\s+(.+))?$') {
        $rawTarget = $Matches[1]
        if ([string]::IsNullOrWhiteSpace($rawTarget)) {
            $msg = if ($currentLang -in @("uk", "ua")) { "Вкажіть файл для читання: /read <файл>" } else { "Specify file path: /read <file>" }
            Write-Host "$msg`n" -ForegroundColor Yellow
            continue
        }
        $rawTarget = $rawTarget.Trim().Trim('"', "'")
        $resolvedPath = $null

        if (Test-Path $rawTarget) {
            $resolvedPath = (Resolve-Path $rawTarget).Path
        } else {
            $searchCandidates = @(
                $PSScriptRoot,
                "$PSScriptRoot\..",
                "E:\Windows Terminal Ai plugin",
                "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\TerminalAI",
                "$HOME\.terminal-ai"
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) }

            foreach ($candidateDir in $searchCandidates) {
                $candidateFile = Join-Path $candidateDir $rawTarget
                if (Test-Path $candidateFile) {
                    $resolvedPath = (Resolve-Path $candidateFile).Path
                    break
                }
            }
        }

        if (-not $resolvedPath -or -not (Test-Path $resolvedPath)) {
            if ($currentLang -in @("uk", "ua")) {
                Write-Host "Файл не знайдено: $rawTarget" -ForegroundColor Red
                Write-Host "  Перевірені розташування:" -ForegroundColor DarkGray
                Write-Host "    • Поточна папка: $((Get-Location).Path)" -ForegroundColor DarkGray
                Write-Host "    • Папка модуля: $PSScriptRoot" -ForegroundColor DarkGray
                Write-Host "  Підказка: вкажіть повний шлях або натисніть Tab після '/read ' для автодоповнення файлів." -ForegroundColor DarkGray
            } else {
                Write-Host "File not found: $rawTarget" -ForegroundColor Red
                Write-Host "  Checked locations:" -ForegroundColor DarkGray
                Write-Host "    • Current directory: $((Get-Location).Path)" -ForegroundColor DarkGray
                Write-Host "    • Module directory: $PSScriptRoot" -ForegroundColor DarkGray
                Write-Host "  Tip: provide full path or press Tab after '/read ' to autocomplete files." -ForegroundColor DarkGray
            }
            Write-Host ""
            continue
        }

        $isLocal = ($resolvedPath.StartsWith((Get-Location).Path))
        if (-not $isLocal) {
            Write-Host "  ✔ Found: $resolvedPath" -ForegroundColor DarkCyan
        }

        $lines = @(Get-Content -Path $resolvedPath -TotalCount 100 -ErrorAction SilentlyContinue)
        $contentHeader = if ($currentLang -in @("uk", "ua")) { "✦ Вміст $resolvedPath (перші 100 рядків):" } else { "✦ Content of $resolvedPath (first 100 lines):" }
        Write-Host "`n$contentHeader" -ForegroundColor Cyan
        Write-Host ("─" * 68) -ForegroundColor DarkGray
        $lines | Out-Host
        Write-Host ("─" * 68) -ForegroundColor DarkGray

        $askPrompt = if ($currentLang -in @("uk", "ua")) { "Додати вміст цього файлу до контексту діалогу? [Y/n]: " } else { "Add this file content to conversation context? [Y/n]: " }
        $injectConfirm = Read-AssistantLine -Prompt $askPrompt
        if ($injectConfirm -notmatch '^(n|no|ні)$') {
            $bt3 = '```'
            $fileNote = "Local file inspected: $resolvedPath`n$bt3`n" + ($lines -join "`n") + "`n$bt3"
            Add-AssistantHistoryMessage -Role "user" -Content $fileNote
            $okMsg = if ($currentLang -in @("uk", "ua")) { "✔ Вміст файлу додано до контексту діалогу!`n" } else { "✔ File content added to conversation context!`n" }
            Write-Host $okMsg -ForegroundColor Green
        }
        continue
    }

    $langInstruction = if ($currentLang -in @("uk", "ua")) {
        "LANGUAGE ENFORCEMENT: You MUST respond strictly in Ukrainian (Українська мова). Under NO circumstances should you respond in Russian (Русский язык)."
    } else {
        "LANGUAGE ENFORCEMENT: Respond primarily in English. If the user explicitly asks in Ukrainian, you may respond in Ukrainian. Under NO circumstances should you respond in Russian (Русский язык)."
    }
    $systemPrompt = @"
You are Terminal AI Assistant, an interactive engineering companion built for PowerShell and Windows Terminal.
Current Environment: PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) on Windows.
$langInstruction
Help the user create robust scripts, troubleshoot errors, automate workflows, and inspect system architecture.
Always prefer clean, idiomatic PowerShell 7 syntax. Format scripts in markdown code blocks.
Maintain context from previous conversation turns to provide relevant follow-up assistance.
"@

    # Додаємо репліку користувача в історію діалогу через санітизатор з FIFO обмеженням
    Add-AssistantHistoryMessage -Role "user" -Content $inputQuery

    Write-Host "`n$($txt.Thinking)`n" -ForegroundColor DarkGray

    $reply = Invoke-OllamaApi -Messages $script:AiChatHistory -SystemPrompt $systemPrompt -Model $activeModel -Temperature 0.3
    if ($reply) {
        Add-AssistantHistoryMessage -Role "assistant" -Content $reply
        Write-Host $reply -ForegroundColor White

        if ($reply -match '(?s)```(?:powershell|pwsh)?\r?\n?(.*?)\r?\n?```') {
            $lastCodeBlock = $Matches[1].Trim()
            Write-Host "`n$($txt.CodeHint)" -ForegroundColor DarkCyan
        }
    } else {
        # При помилці вилучаємо останній запит користувача, щоб не засмічувати історію
        if ($script:AiChatHistory.Count -gt 0 -and $script:AiChatHistory[$script:AiChatHistory.Count - 1].role -eq "user") {
            $script:AiChatHistory.RemoveAt($script:AiChatHistory.Count - 1)
        }
    }

    Write-Host "`n" + ("─" * 68) -ForegroundColor DarkGray
}
