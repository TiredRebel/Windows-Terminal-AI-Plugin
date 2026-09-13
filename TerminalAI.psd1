# TerminalAI.psd1 - TerminalAI module manifest

@{
    # Module identity
    RootModule = 'TerminalAI.psm1'
    ModuleVersion = '0.1.0'
    GUID = '9b6d8f50-32fa-4cb8-8dc7-95f2081d0ef5'
    Author = 'TiredRebel'
    CompanyName = 'TerminalAI'
    Copyright = '(c) 2026 TiredRebel. All rights reserved.'

    # Module Description
    Description = 'PowerShell AI assistant for Windows Terminal and console: command generation, multi-line scripts, error fixing, and compiled .NET 10 helper powered by Ollama. Local by default when configured with local Ollama.'

    # Minimum PowerShell version
    PowerShellVersion = '5.1'

    # Compatible PowerShell editions
    CompatiblePSEditions = @('Desktop', 'Core')

    # Required modules
    RequiredModules = @()

    # Nested modules (the compiled DLL loads dynamically from TerminalAI.psm1 on PowerShell 7+)
    NestedModules = @()

    # Exported functions
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

    # Exported variables
    VariablesToExport = @()

    # Exported aliases
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

    # Private data and tags
    PrivateData = @{
        PSData = @{
            Prerelease = 'preview1'
            Tags = @('AI', 'Ollama', 'WindowsTerminal', 'PowerShell', 'Copilot', 'LLM', 'LocalAI', 'DotNet10')
            ProjectUri = 'https://github.com/TiredRebel/Windows-Terminal-AI-Plugin'
            LicenseUri = 'https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/blob/main/LICENSE'
            ReleaseNotes = 'TerminalAI v0.1.0-preview1: Local-by-default Ollama integration, fail-closed AST risk analysis, compiled .NET 10 helper module, multi-user installer, ai-doctor diagnostics, optional Claude Code agent mode.'
        }
    }
}
