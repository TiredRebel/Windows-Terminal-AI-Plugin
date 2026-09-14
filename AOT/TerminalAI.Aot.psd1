@{
    RootModule = 'bin/Release/net10.0/TerminalAI.Aot.dll'
    ModuleVersion = '1.0.0'
    GUID = 'a07e1143-4a07-4a07-b007-a07e11434a07'
    Author = 'TiredRebel'
    CompanyName = 'TerminalAI'
    Copyright = '(c) 2026. All rights reserved.'
    Description = 'Compiled managed .NET 10 helper module for TerminalAI (reuses HTTP connections via SocketsHttpHandler)'
    PowerShellVersion = '7.0'
    CmdletsToExport = @('Invoke-AiCommandFast')
    AliasesToExport = @('ai-fast', 'aif')
    FunctionsToExport = @()
    VariablesToExport = @()
}
