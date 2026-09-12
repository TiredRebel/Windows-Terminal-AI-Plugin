# TerminalAI.psd1 - Маніфест модуля TerminalAI

@{
    # Ідентифікація модуля
    RootModule = 'TerminalAI.psm1'
    ModuleVersion = '1.0.0'
    GUID = '9b6d8f50-32fa-4cb8-8dc7-95f2081d0ef5'
    Author = 'Windows Terminal AI'
    CompanyName = 'Community'
    Copyright = '(c) 2026. All rights reserved.'

    # Опис модуля
    Description = 'Розширення для Windows Terminal та PowerShell: генерація команд, багаторядкових сценаріїв, автовиправлення помилок та інлайн-гарячі клавіші на базі локальної Ollama.'

    # Мінімальна версія PowerShell
    PowerShellVersion = '5.1'

    # Необхідні модулі
    RequiredModules = @()

    # Вкладені модулі
    NestedModules = @('TerminalAI.Aot.dll')

    # Функції, що експортуються
    FunctionsToExport = @(
        'Invoke-AiCommand',
        'Invoke-AiFix',
        'New-AiScript',
        'Invoke-AiAssistant',
        'Get-TerminalAiConfig',
        'Set-TerminalAiConfig',
        'Get-TerminalAiModels',
        'Show-TerminalAiModels',
        'Get-WindowsTerminalSettingsPath',
        'Get-TerminalAiFonts',
        'Show-TerminalAiFonts',
        'Set-TerminalAiFont',
        'Set-TerminalAiLanguage',
        'Set-TerminalAiDefaultLanguage',
        'Register-TerminalAiKeyHandler',
        'Invoke-OllamaApi',
        'Format-AiCodeOutput',
        'Show-AiAnswer',
        'Show-AiCodeCard',
        'Show-AiActionMenu',
        'Get-TerminalAiText',
        'Show-TerminalAiWelcome',
        'Get-AiSystemPrompt',
        'Clear-AiInputBuffer',
        'Get-AiMenuKeyPress'
    )

    # Командлети, що експортуються
    CmdletsToExport = @(
        'Invoke-AiCommandFast'
    )

    # Змінні, що експортуються
    VariablesToExport = @()

    # Аліаси, що експортуються
    AliasesToExport = @(
        'ai',
        '??',
        'ai-fast',
        'aif',
        'ai-fix',
        'fix-error',
        'ai-script',
        'ai-font',
        'ai-fonts',
        'ai-lang',
        'ai-lang-permanent',
        'ai-lang-default',
        'ai-chat',
        'ai-assistant',
        'Clean-AiCodeOutput'
    )

    # Приватні дані та теги
    PrivateData = @{
        PSData = @{
            Tags = @('AI', 'Ollama', 'WindowsTerminal', 'PowerShell', 'Copilot', 'LLM')
            ProjectUri = 'https://github.com/microsoft/terminal'
        }
    }
}
