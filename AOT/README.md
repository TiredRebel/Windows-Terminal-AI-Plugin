# TerminalAI.Aot — managed .NET 10 helper for PowerShell

**English (canonical)** | [Ukrainian](README.uk.md) | [Main guide](../README.md)

`TerminalAI.Aot` is the compiled C# command path for TerminalAI on PowerShell 7+ (`net10.0`). It exposes `Invoke-AiCommandFast` through `aif` and `ai-fast`, uses the shared TerminalAI configuration, calls Ollama over HTTP, analyzes generated PowerShell, and can delegate agent tasks to the Core module.

The installer, status cards, help, menus, and errors are English-only. `Language` selects the requested language for model-generated `-Ask` and `-Explain` prose; it does not localize the UI or raw command generation.

`AOT` is a historical path and project identifier. The current project builds a managed .NET 10 DLL with `dotnet build` and does not define `<PublishAot>`.

The public release channel is still the older `v0.1.0-preview1`; preview2 in the repository is an unpublished candidate. Preview binaries are currently unsigned; signing and signature verification remain release gates.

> [!IMPORTANT]
> Model-generated commands are untrusted input. Review them before execution. AST checks and WhatIf previews are guardrails, not a sandbox. Commands run with the current user's privileges.

<!-- sync:audience -->
## Who this component is for

This helper is for TerminalAI users who want the compiled C# command path and for maintainers who build or test that implementation. It requires PowerShell 7+ and .NET 10, does not support Windows PowerShell 5.1, and depends on the Core product for shared configuration and agent delegation.

<!-- sync:advantages -->
## Advantages

- **Compiled local processing:** command handling, HTTP orchestration, AST analysis, console input, and clipboard operations run in the managed .NET 10 module; model response time still depends on Ollama, the model, and hardware.
- **Shared configuration:** the C# and PowerShell paths use the same TerminalAI settings and model selection.
- **Execution guardrails:** syntax validation, risk classification, confirmation, supported WhatIf previews, and pattern-based secret redaction remain in the workflow.
- **Protected script output:** diff review, overwrite protection, and UTF-8 BOM writes are available.
- **Optional adoption:** keep the PowerShell implementation and install this helper only on compatible PowerShell 7+ systems.

<!-- sync:requirements -->
## Requirements

- Windows 10 20H2+ or Windows 11
- PowerShell 7+
- compatible .NET 10 runtime
- installed TerminalAI Core product
- reachable configured Ollama endpoint and an available model

<!-- sync:install -->
## Install and import

The main installer installs Core before the Aot product:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Install-TerminalAi.ps1 -Products Core,Aot
```

If `Ollama` is also selected, installing it or downloading a model requires a separate interactive `y` or `yes`; `-AutoConfirm` and `-NonInteractive` do not authorize those external changes. TerminalAI uninstallation preserves Ollama and all models.

To build and import the project from a source checkout:

```powershell
dotnet build .\AOT\TerminalAI.Aot.csproj -c Release
pwsh -NoProfile -Command "Import-Module .\AOT\bin\Release\net10.0\TerminalAI.Aot.dll -Force; Get-Command aif"
```

If a PowerShell process has loaded the DLL, Windows may prevent that file from being overwritten. Test a new build in a fresh `pwsh -NoProfile` process.

<!-- sync:usage -->
## Usage

```powershell
aif "find files larger than 100 MB"
aif "show listening TCP ports" -Execute
aif "get the default gateway" -Copy
aif "find processes using more than 1 GB" -Alias
aif "how do PowerShell pipelines stream objects?" -Ask
aif "create a backup script" -SavePath .\backup.ps1
aif agent "inspect git diff and run relevant tests"
```

| Parameter | Aliases | Purpose |
| --- | --- | --- |
| `-Prompt` | position 0 | Prompt or management subcommand. |
| `-Model` | — | Ollama model for this call. |
| `-Execute` | `-x`, `-y` | Send generated code through the execution gate. |
| `-Copy` | `-c` | Copy output after the C# sanitizer handles recognized patterns. |
| `-Explain` | — | Request a structured explanation. |
| `-Ask` | `-chat`, `-question` | Request prose instead of a command. |
| `-Agent` | `-Autonomous` | Delegate to Core's `Invoke-AiAgent`. |
| `-Alias` | `-a`, `-Short`, `-UseAliases` | Prefer short PowerShell aliases. |
| `-SavePath` | `-Save`, `-OutFile` | Save output with diff and overwrite checks. |
| `-Force` | `-f` | Overwrite an existing output file without the prompt. |
| `-ConfirmInput` | — | Supply `y` or `n` to the execution gate, mainly for tests. |

Management subcommands are `models`, `model <name>`, `lang <en|uk>`, `status`, `config`, `help`, and `agent <task>`. `lang` changes model-generated prose, not UI text.

After generation, the menu supports `Enter` to execute through the gate, `C` to copy, `I` to insert, `S` to toggle aliases, `W` to save, `X` to explain, `A` to ask a prose question, and `Esc` to cancel.

<!-- sync:safety -->
## Safety model

`AotCommandAstAnalyzer` classifies commands as `ReadOnly`, `SystemChange`, `Deletion`, `NetworkChange`, `ServiceOrProcess`, `Registry`, `DiskOrPartition`, `DynamicOrUnknown`, or `ExternalProgram`. Risk levels are `Low`, `Medium`, `High`, and `Critical`.

Syntax errors are blocked. High, critical, dynamic, and unresolved operations require confirmation. WhatIf is used only for PowerShell commands that support `ShouldProcess`; it is not added to arbitrary external programs.

`AotSecretSanitizer` recognizes selected API keys, bearer tokens, password arguments, and private-key blocks before selected display and clipboard paths. It is a deterministic pattern filter and cannot detect unknown secret formats.

<!-- sync:configuration -->
## Configuration and language

The helper reads `~/.terminal-ai/config.json` or the directory selected by `TERMINAL_AI_CONFIG_DIR`. Primary settings are `OllamaUrl`, `Model`, `Language`, `Temperature`, `TimeoutSeconds`, `UseAliases`, and the agent settings.

```powershell
aif status
aif models
aif model qwen2.5-coder:7b
aif lang uk
aif config
```

The full configuration reference is in the [Technical and maintainer guide](../docs/TECHNICAL.md#configuration-reference).

<!-- sync:limitations -->
## Limitations

- The helper uses Win32 clipboard and console APIs and is intended for Windows.
- `aif -Agent` requires the imported TerminalAI Core module and a separately installed Claude Code CLI.
- The configured endpoint determines the data boundary.
- Model inference usually dominates response time; compiling the local command path does not remove that cost.
- The PowerShell and C# paths are separate implementations, so behavior parity must be tested.

<!-- sync:development -->
## Build and test

```powershell
dotnet build .\AOT\TerminalAI.Aot.csproj -c Release

Get-ChildItem .\AOT\tests\*.Tests.ps1 | ForEach-Object {
    pwsh -NoProfile -ExecutionPolicy Bypass -File $_.FullName
}
```

The suites cover AST analysis, the execution gate, secret redaction, script output, HTTP errors and timeouts, and agent delegation. The current run is the source of truth; this guide does not freeze a passing count.

<!-- sync:technical -->
## More technical detail

See the English [Technical and maintainer guide](../docs/TECHNICAL.md#aot-helper-internals) for the class map, HTTP behavior, development checks, and documentation verification.

The English AOT README is canonical. [README.uk.md](README.uk.md) is its Ukrainian translation and follows the same ordered sync sections.
