# TerminalAI technical and maintainer guide

[Canonical user guide](../README.md) | [C# helper guide](../AOT/README.md)

This English-only document holds detailed implementation, configuration, build, test, and release-maintainer material moved out of the user-focused README files. The English README files are canonical; Ukrainian translations contain the same ordered user-facing sections.

## Installation details

The root installer accepts these options:

| Parameter | Meaning |
| --- | --- |
| `-Products <Core,Ollama,Aot,WindowsTerminal,All>` | Select one or more products. The default is `All`. Core is required by Aot and WindowsTerminal. |
| `-Scope CurrentUser\|AllUsers` | Install for the current user or all users. `AllUsers` requires administrator rights. |
| `-Language en\|uk` | Set the initial language for model-generated prose. Application UI remains English. |
| `-PreferredModel <name>` | Select an Ollama model without hardware-based recommendation. |
| `-SkipOllamaCheck` | Compatibility shortcut that removes Ollama from the product selection. |
| `-SkipTerminalConfig` | Compatibility shortcut that removes WindowsTerminal from the product selection. |
| `-AutoConfirm` | Accept supported installer defaults. |
| `-ModifySettingsJson` | Also update the legacy Windows Terminal `settings.json` action list after a backup. |
| `-CustomProfilePath`, `-CustomModulePath`, `-CustomFragmentPath` | Override destinations for controlled deployments and tests. |

Each product also has a standalone installer:

```powershell
pwsh -ExecutionPolicy Bypass -File .\installers\Install-Core.ps1
pwsh -ExecutionPolicy Bypass -File .\installers\Install-Ollama.ps1
pwsh -ExecutionPolicy Bypass -File .\installers\Install-Aot.ps1
pwsh -ExecutionPolicy Bypass -File .\installers\Install-WindowsTerminal.ps1
```

Install Core before Aot or WindowsTerminal. The main installer preserves that order automatically. Windows PowerShell 5.1 skips the managed .NET 10 helper because it cannot load the `net10.0` assembly.

For a temporary session, `bootstrap.ps1` downloads the versioned GitHub Release asset, imports the module into the current process, checks Ollama and the model, and registers the inline key handler without adding the normal persistent profile block. Inspect remote content before executing a piped script.

## PowerShell command reference

### `Invoke-AiCommand` (`ai`, `??`)

| Parameter | Aliases | Purpose |
| --- | --- | --- |
| `-Prompt` | position 0 | Natural-language request or management subcommand. |
| `-Execute` | `-x`, `-y` | Execute after the applicable gate and confirmations. |
| `-Copy` | `-c` | Copy the generated command as-is. Inspect it for secrets. |
| `-Alias` | `-a`, `-Short`, `-UseAliases` | Prefer short PowerShell aliases. |
| `-Explain` | — | Request a structured explanation. |
| `-Ask` | `-chat`, `-question` | Request prose instead of a command. |
| `-Preview` | `-w`, `-WhatIf` | Request supported WhatIf preview. |
| `-Model` | — | Override the Ollama model for this call. |

Management subcommands include `help`, `status`, `models`, `model <name>`, `lang <en|uk>`, `font`, `fonts`, `alias`, and `config`. The permanent language forms add the Windows user-environment write:

```powershell
ai lang uk
ai lang permanent uk
ai-lang-permanent uk
Set-TerminalAiDefaultLanguage uk
```

### Inline PSReadLine generation

`Register-TerminalAiKeyHandler` registers `F2`, `Ctrl+G`, `Ctrl+Alt+A`, and a distinct configured chord. The handler removes supported comment or prompt prefixes and sends a non-streaming `/api/generate` request. An empty line becomes `# [AI Prompt]: `. While waiting, the line shows an elapsed-time spinner; success replaces it with generated code, while failure restores the original input after an error indicator.

The inline request uses temperature `0.0`, context size `1024`, prediction limit `120`, and `keep_alive = "1h"`. Those are implementation settings, not latency guarantees.

### `New-AiScript` (`ai-script`)

| Parameter | Purpose |
| --- | --- |
| `-Description` | Positional natural-language description. |
| `-OutputPath` | Optional `.ps1` destination. |
| `-Edit` | Open the saved script in VS Code or Notepad. |
| `-Model` | Override the model for this call. |

The save path is normalized, missing directories may be created, existing content is shown as a diff, and interactive confirmation is required before overwrite. New content is written as UTF-8 with BOM through a temporary file. `ai-script` intentionally has no `-Force` parameter.

### Interactive assistant

The assistant calls Ollama `/api/chat`, stores at most 16 messages by default, and evicts the oldest entries first. Recognized secret patterns are redacted before messages enter history. `/read` adds a bounded local text file to context; `/run` routes the latest code block through the PowerShell execution gate; `/save` uses overwrite checks. `/copy` copies the latest block as-is.

The language commands have two persistence levels:

- `/lang en` or `/lang uk` updates `config.json` and the current process.
- `/lang permanent en`, `/lang permanent uk`, and `/lang-permanent ...` additionally write user-level `TERMINAL_AI_LANG` for later processes.

### Agent mode

`Invoke-AiAgent` (`ai-agent`) accepts:

| Parameter | Aliases | Purpose |
| --- | --- | --- |
| `-Prompt` | position 0 | Task passed to Claude Code. |
| `-Model` | — | Model used for this agent invocation. |
| `-WorkingDir` | — | Agent working directory. |
| `-Resume` | — | Resume an earlier session in the directory. |
| `-Print` | — | Run non-interactively and print the result. |
| `-ConfirmTrust` | `-Force`, `-y`, `-Yes` | Skip TerminalAI's directory-trust prompt; Claude Code permissions remain active. |
| `-CheckOnly` | — | Check executable, endpoint, model, and working-directory readiness without launching. |

TerminalAI sets `ANTHROPIC_BASE_URL` from `OllamaUrl`, sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, removes selected ambient provider keys in the child process, and uses `~/.terminal-ai/claude` unless configured otherwise. These measures reduce unintended routing but do not independently prove the behavior of the separately installed CLI. The target still needs an Anthropic-compatible `/v1/messages` transport; `/api/tags` and `/api/show` readiness alone do not prove it.

## Configuration reference

Configuration lives in `~/.terminal-ai/config.json`. `TERMINAL_AI_CONFIG_DIR` selects a different directory. `TERMINAL_AI_LANG` takes precedence for the model-response language.

| Setting | Default | Purpose |
| --- | --- | --- |
| `OllamaUrl` | `http://localhost:11434` | Ollama base URL. |
| `Model` | `qwen2.5-coder:7b` | Default generation and chat model. |
| `Language` | `en` | Requested model-prose language: `en` or `uk`. |
| `Font` | `Cascadia Code` | Preferred Windows Terminal font. |
| `Temperature` | `0.2` | Sampling temperature where not overridden. |
| `TimeoutSeconds` | `120` | HTTP timeout. |
| `HotkeyChord` | `Ctrl+Alt+A` | Configured inline shortcut. |
| `AutoCopy` | `false` | Command auto-copy preference. |
| `ShowExplanation` | `true` | Explanation display preference. |
| `UseAliases` | `false` | Prefer short aliases. |
| `AgentModel` | `qwen2.5-coder:7b` | Default agent model. |
| `ClaudeExecutable` | empty | Explicit Claude Code path. |
| `AgentDataDirectory` | empty | Agent data-directory override. |

Useful commands:

```powershell
ai status
ai config
ai models
ai model qwen2.5-coder:7b
ai fonts
ai font "Cascadia Code"
Set-TerminalAiFont -Font "Cascadia Code" -Size 13
Set-TerminalAiConfig -OllamaUrl http://localhost:11434 -TimeoutSeconds 120
```

## Safety internals

The PowerShell and C# implementations use the PowerShell parser rather than regular expressions alone for command structure. They inspect nested commands, invocation operators, aliases, parameters, splatting, and literal or unresolved targets.

Categories are `ReadOnly`, `SystemChange`, `Deletion`, `NetworkChange`, `ServiceOrProcess`, `Registry`, `DiskOrPartition`, `DynamicOrUnknown`, and `ExternalProgram`. Risk levels are `Low`, `Medium`, `High`, and `Critical`. Syntax errors are blocked. High, critical, dynamic, and unresolved operations require explicit confirmation. Exact treatment depends on the whole AST result, not only the command name.

WhatIf preview is available only when the PowerShell commands involved support `ShouldProcess`. It is not appended to arbitrary external programs.

Secret filtering is deterministic and pattern-based. It recognizes selected bearer tokens, API-key formats, password-like arguments, and private-key blocks. Unknown formats can pass through. Standard PowerShell `ai -Copy`, menu copy, error-fix copy, and assistant `/copy` use the generated content as-is; the compiled helper applies `AotSecretSanitizer` to its selected display and clipboard paths.

## Ollama transport and model performance

TerminalAI does not invoke `ollama run` for normal generation. The PowerShell implementation uses `/api/generate` for one-shot and inline requests, `/api/chat` for the assistant, and `/api/tags` for discovery. Agent readiness also checks `/api/show`. The C# helper uses `/api/generate` and expects the response text in the top-level `response` field.

HTTP provides structured JSON, explicit request settings, cancellation or timeout handling, and connection reuse. Ollama remains responsible for loading models and managing inference memory. Because `OllamaUrl` is configurable, these requests are not necessarily local.

Observed response time depends on model size and quantization, context, CPU/GPU, available RAM/VRAM, Ollama configuration, and cache state. This repository does not include a reproducible performance benchmark, so it does not make fixed latency claims. Start with a model that fits available memory, verify it with `ollama list`, and compare representative prompts on the target system. Generation requests ask Ollama to keep the model loaded for one hour; actual behavior depends on the installed Ollama version and configuration.

## Project architecture

```text
Install-TerminalAi.ps1
  -> orchestrates installers/Install-*.ps1
  -> installs TerminalAI.psd1, TerminalAI.psm1, and companion scripts
  -> writes ~/.terminal-ai/config.json
  -> adds a marked profile import block
  -> deploys terminalai.json

TerminalAI.psm1
  -> TerminalAiConfig.ps1       configuration, response language, fonts
  -> TerminalAiAssistant.ps1    interactive /api/chat session
  -> TerminalAiAgent.ps1        optional Claude Code launcher
  -> Ollama /api/generate       one-shot and inline generation
  -> AST analyzer and gate      pre-execution inspection
  -> TerminalAI.Aot.dll         optional PowerShell 7+ C# path
```

The PowerShell and C# paths share configuration and major workflows but are separate implementations. Tests, rather than documentation, establish behavior parity.

## AOT helper internals

The historical `AOT` directory contains a normal `net10.0` C# project. `TerminalAI.Aot.csproj` builds a managed DLL and does not define `<PublishAot>`.

```text
AOT/
├── AiConfig.cs                  shared JSON configuration loader
├── AotCommandAstAnalyzer.cs     AST categories, risks, and targets
├── AotExecutionGate.cs          confirmation and supported WhatIf flow
├── AotClipboard.cs              Win32 clipboard interop
├── AotSecretSanitizer.cs        pattern-based redaction
├── AotDiffRenderer.cs           bounded unified-diff rendering
├── AotScriptSafety.cs           overwrite checks and UTF-8 BOM output
├── OllamaClient.cs              HTTP requests, timeout, cancellation
├── PowerShellAliasConverter.cs  short and full cmdlet conversion
├── Win32Console.cs              console rendering and key input
├── InvokeAiCommandFastCmdlet.cs `Invoke-AiCommandFast`, `aif`, `ai-fast`
└── TerminalAI.Aot.csproj        managed .NET 10 project
```

`Invoke-AiCommandFast` supports `-Execute`, `-Copy`, `-Alias`, `-Explain`, `-Ask`, `-Agent`, `-SavePath`, `-Force`, `-Model`, and test-oriented `-ConfirmInput`. Its interactive menu offers execute, copy, insert, alias toggle, save, explain, ask, and cancel actions.

If a loaded DLL causes a Windows file lock, use a fresh process:

```powershell
pwsh -NoProfile -Command "Import-Module .\AOT\bin\Release\net10.0\TerminalAI.Aot.dll -Force; Get-Command aif"
```

## Windows Terminal integration

The default path uses a fragment file rather than editing `settings.json`. `terminalai.json` defines two profiles and four actions:

- `Terminal AI Assistant`
- `PowerShell with TerminalAI`
- `AI: Ask Ollama (ai)`
- `AI: Fix last error (ai-fix)`
- `AI: Generate script (ai-script)`
- `AI: Open assistant in split pane`

The split-pane action uses a vertical pane with size `0.4`. `-ModifySettingsJson` enables the older settings mutation path; the installer creates a backup first.

## Build and verification

Run PowerShell suites in a fresh `pwsh` process:

```powershell
pwsh -NoProfile -File .\tests\P0-SecurityGate.Tests.ps1
pwsh -NoProfile -File .\tests\P1-UxAssistant.Tests.ps1
pwsh -NoProfile -File .\tests\P2-MultiUserStability.Tests.ps1
pwsh -NoProfile -File .\tests\P3-AgentMode.Tests.ps1
pwsh -NoProfile -File .\tests\P4-Packaging.Tests.ps1

Get-ChildItem .\AOT\tests\*.Tests.ps1 | ForEach-Object {
    pwsh -NoProfile -ExecutionPolicy Bypass -File $_.FullName
}

pwsh -NoProfile -File .\Test-TerminalAi.ps1
dotnet build .\AOT\TerminalAI.Aot.csproj -c Release
git diff --check
```

Use the current run as the source of truth; documentation intentionally does not freeze test counts. PowerShell 5.1 compatibility should be syntax-checked separately because the C# helper is PowerShell 7+ only.

## Documentation verification

The default check is deterministic and does not use the network. It verifies README sync-marker order, local Markdown files and anchors, prohibited terminology, and agreement between documented release tags and archive names:

```powershell
pwsh -NoProfile -File .\tools\Test-DocumentationQuality.ps1
```

Use the explicit live mode only when network access is available:

```powershell
pwsh -NoProfile -File .\tools\Test-DocumentationQuality.ps1 -Live
```

Live mode queries the GitHub Releases API, the authoritative `microsoft/winget-pkgs` manifest path, and the PowerShell Gallery OData endpoint. Exit code `0` means every checked result agrees with the documentation, `1` means a contradiction or another documentation failure, and `2` means at least one live result is unknown or unreachable. An unknown result is not evidence that a channel is live or pending.

## Release channel status

These statuses describe the current documentation baseline and must not be promoted without authoritative verification:

| Channel | Status | Documented evidence |
| --- | --- | --- |
| GitHub Release | `live` | `v0.1.0-preview1` release page and `TerminalAI-v0.1.0-preview1-win-x64.zip` asset |
| WinGet | `pending` | Publication is not confirmed; the proposed identifier is `TiredRebel.TerminalAI` |
| PowerShell Gallery | `pending` | Publication of module `TerminalAI` is not confirmed |

The GitHub-generated source archives are not installer assets. A live verification should query all three authoritative channels and return an explicit unknown status if a service cannot be checked.
