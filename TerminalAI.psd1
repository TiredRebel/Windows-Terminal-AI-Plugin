# TerminalAI.psd1 - Маніфест модуля TerminalAI

@{
    # Ідентифікація модуля
    RootModule = 'TerminalAI.psm1'
    ModuleVersion = '1.0.0'
    GUID = '9b6d8f50-32fa-4cb8-8dc7-95f2081d0ef5'
    Author = 'Windows Terminal AI'
    CompanyName = 'Community'
    Copyright = '(c) 2026. All rights reserved.'

    # Module Description
    Description = 'Windows Terminal and PowerShell AI assistant: command generation, multi-line scripts, automated error fixing, and inline hotkeys powered by local Ollama.'

    # Мінімальна версія PowerShell
    PowerShellVersion = '5.1'

    # Необхідні модулі
    RequiredModules = @()

    # Вкладені модулі (AOT DLL завантажується динамічно у TerminalAI.psm1 для PowerShell 7+)
    NestedModules = @()

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
        'Get-AiMenuKeyPress',
        'Show-TerminalAiHelp',
        'Register-TerminalAiArgumentCompleters',
        'Test-AiCommandAst',
        'Invoke-AiExecutionGate',
        'Protect-AiSecretData',
        'Format-AiScriptDiff',
        'Save-AiScriptFile',
        'Test-TerminalAiInstallation',
        'Invoke-AiAgent',
        'Test-AiAgentReadiness'
    )

    # Cmdlets to export
    CmdletsToExport = @('Invoke-AiCommandFast')

    # Змінні, що експортуються
    VariablesToExport = @()

    # Аліаси, що експортуються
    AliasesToExport = @(
        'ai',
        '??',
        'ai-help',
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
        'ai-doctor',
        'ai-agent',
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
