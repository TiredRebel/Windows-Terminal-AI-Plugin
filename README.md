# TerminalAI — Ollama assistance for PowerShell and Windows Terminal

**English (canonical)** | [Ukrainian](README.uk.md) | [C# helper](AOT/README.md)

TerminalAI is a Windows PowerShell module that sends command-generation and chat requests to a configured Ollama endpoint. It provides command and script drafting, error diagnosis, an interactive assistant, Windows Terminal integration, pre-execution checks, and an optional Claude Code launcher.

The default `OllamaUrl` is the local endpoint `http://localhost:11434`, so core requests are local by default. The endpoint is configurable, and agent mode launches a separately installed Claude Code CLI; review those configurations to understand the actual data boundary. The installer and application UI are English-only. `Language` selects `en` or `uk` for model-generated prose, not the UI.

> [!IMPORTANT]
> Model-generated commands are untrusted input. Review them before execution. AST checks and WhatIf previews are guardrails, not a sandbox. Commands run with the current user's privileges.

<!-- sync:audience -->
## Who TerminalAI is for

TerminalAI is intended for Windows users who work in PowerShell and can review generated commands, including:

- developers and DevOps engineers who want terminal-based command, script, and troubleshooting assistance;
- administrators and support engineers who want PowerShell drafts with a visible review step;
- PowerShell learners who want commands accompanied by explanations;
- users who prefer a locally configured Ollama workflow for core features.

<!-- sync:advantages -->
## Advantages

- **Terminal workflow:** generate commands and scripts, diagnose errors, and chat from PowerShell or Windows Terminal.
- **Local by default:** core requests can stay on the machine when `OllamaUrl` points to local Ollama; no cloud API key is required for those requests.
- **Review before execution:** parsing, risk classification, confirmation gates, and supported WhatIf previews sit between model output and execution.
- **Selectable installation:** install all products or choose Core, Ollama, Aot, and WindowsTerminal. Core is required by Aot and WindowsTerminal.
- **Shell coverage:** Core supports PowerShell 7+ and Windows PowerShell 5.1; the optional compiled helper supports PowerShell 7+ with .NET 10.
- **Diagnostics:** `ai-doctor` checks the module, profile, terminal integration, Ollama, selected model, safety helpers, and optional agent setup.

<!-- sync:requirements -->
## Requirements

**OS:** Windows 10 20H2+ or Windows 11. Current-user installation does not require administrator rights; `-Scope AllUsers` does. The Ollama product is installed machine-wide independently of that scope.

| Product | Shell | Additional requirement |
| --- | --- | --- |
| **Core** — `ai`, `ai-fix`, `ai-script`, `ai-chat`, `ai-doctor` | PowerShell 7+ recommended, or Windows PowerShell 5.1 | — |
| **Ollama** — detection, optional installation, model setup | Either | Internet for the first download; several GB per model; a GPU is optional |
| **Aot** — managed .NET 10 helper, `aif` / `ai-fast` | PowerShell 7+ | Compatible .NET 10 runtime; Core must already be installed |
| **WindowsTerminal** — fragment profiles and actions | Either | [Windows Terminal](https://aka.ms/terminal) 1.18+; Core must already be installed |

The default model is `qwen2.5-coder:7b`; `qwen2.5-coder:3b` is an alternative for systems with less available memory. `ai-agent` additionally requires a separately installed Claude Code CLI.

<!-- sync:install -->
## Install

The confirmed release channel is GitHub Releases:

- [Download `TerminalAI-v0.1.0-preview1-win-x64.zip`](https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/download/v0.1.0-preview1/TerminalAI-v0.1.0-preview1-win-x64.zip)
- [Release notes for `v0.1.0-preview1`](https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/tag/v0.1.0-preview1)

The public channel is still the older `v0.1.0-preview1`. Preview2 in this repository is an unpublished release candidate and has no public download link.

Preview binaries are currently unsigned. Release signing and verification are release gates, not features claimed by this preview.

> [!IMPORTANT]
> Install from the versioned asset under **Releases**. GitHub's generated source archives are not installers.

Extract the archive, open PowerShell in that directory, and run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Install-TerminalAi.ps1
. $PROFILE
```

For Windows PowerShell 5.1, replace `pwsh` with `powershell.exe`. The default installs all four products. To select products or the initial model-response language:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Install-TerminalAi.ps1 -Products Core,Ollama -Language uk
```

PowerShell Gallery and WinGet availability is not currently confirmed. Do not use their installation commands until the channel is verified. Source checkout and temporary bootstrap options remain available:

```powershell
git clone https://github.com/TiredRebel/Windows-Terminal-AI-Plugin.git
cd Windows-Terminal-AI-Plugin
pwsh -ExecutionPolicy Bypass -File .\Install-TerminalAi.ps1

# Inspect remote content before piping it to PowerShell.
irm https://raw.githubusercontent.com/TiredRebel/Windows-Terminal-AI-Plugin/main/bootstrap.ps1 | iex
```

See [Technical and maintainer guide](docs/TECHNICAL.md#installation-details) for every installer option and individual-product commands.

### Temporary portable session

Run `bootstrap.ps1 -Mode Portable` to load the module into the current PowerShell process without updating the current-user profile or existing TerminalAI configuration. Language selection is process-scoped. If the bootstrapper downloads a runtime package, extracted files and other temporary downloads may remain under `$env:TEMP`; remove them when no longer needed.

<!-- sync:commands -->
## Commands and workflows

| Command | Purpose |
| --- | --- |
| `ai` / `??` | Generate one command with the PowerShell implementation. |
| `aif` / `ai-fast` | Generate one command with the managed .NET 10 helper on PowerShell 7+. |
| `ai-fix` / `fix-error` | Diagnose the latest PowerShell error and propose a correction. |
| `ai-script` | Generate a multi-line PowerShell script and optionally save it. |
| `ai-chat` / `ai-assistant` | Start the interactive assistant with bounded history. |
| `ai-agent` | Launch Claude Code against the configured endpoint. |
| `ai-doctor` | Check the installation and configured services. |
| `ai-help` | Show built-in help. |

Examples:

```powershell
ai "find files larger than 100 MB"
ai "show listening TCP ports" -Execute
ai "get the default gateway" -Copy
ai "explain this pipeline" -Explain
ai-fix
ai-script "create a disk-space report" -OutputPath .\Get-DiskReport.ps1 -Edit
ai-doctor
```

At a PSReadLine prompt, type a comment and press `F2`, `Ctrl+G`, or the configured `Ctrl+Alt+A` chord. TerminalAI replaces the line with generated PowerShell. Shortcut availability depends on PSReadLine and the active console host.

`ai-script` protects existing files with a diff and confirmation prompt; it has no `-Force` option. Review every generated path and command before use.

<!-- sync:assistant -->
## Interactive assistant

```powershell
ai-chat
ai-chat -Model qwen2.5-coder:7b
```

The assistant uses Ollama's `/api/chat` endpoint, keeps bounded FIFO history, and applies pattern-based redaction before storing conversation messages. Pattern matching cannot detect every secret.

| Slash command | Action |
| --- | --- |
| `/help`, `/?` | Show assistant help. |
| `/models`, `/model <name>` | List or select an Ollama model. |
| `/lang <en\|uk>` | Save the model-response language to `config.json` and update the current process. |
| `/lang permanent <en\|uk>`, `/lang-permanent <en\|uk>` | Do the same and also write user-level `TERMINAL_AI_LANG`. |
| `/context`, `/reset` | Show history use or clear history. |
| `/inspect [clear]` | Show diagnostic context or clear the recorded last error. |
| `/run` | Send the latest code block through the execution gate. |
| `/read <path>` | Add a size-checked local text file to context. |
| `/copy` | Copy the latest code block; inspect it for secrets first. |
| `/save [path.ps1]` | Save the latest code block with overwrite protection. |
| `/clear`, `/exit` | Clear the screen or end the session. |

<!-- sync:agent -->
## Optional agent mode

`ai-agent` launches a separately installed Claude Code executable. TerminalAI points `ANTHROPIC_BASE_URL` at the configured `OllamaUrl` and uses `~/.terminal-ai/claude` as its default data directory.

```powershell
ai-agent -CheckOnly
ai-agent "inspect the current git diff and run relevant tests"
ai-agent -WorkingDir C:\src\project -Model qwen2.5-coder:7b
ai-agent -Resume
ai-agent -Print "summarize this project"
```

The target must provide the API behavior expected by Claude Code, including `/v1/messages`; readiness checks of Ollama model endpoints do not prove that compatibility. Claude Code keeps its own permissions and may read, modify, or run content allowed by those permissions.

<!-- sync:compiled-helper -->
## Managed .NET 10 helper

On PowerShell 7+, the Core module can load `TerminalAI.Aot.dll` and expose `Invoke-AiCommandFast` as `aif` and `ai-fast`.

```powershell
aif "find large log files"
aif "restart the Spooler service" -Execute
aif "how do PowerShell pipelines stream objects?" -Ask
```

`AOT` is a historical path and project identifier. The current `net10.0` project produces a managed DLL with `dotnet build`; it does not define `<PublishAot>`. See the [C# helper guide](AOT/README.md).

<!-- sync:safety -->
## Safety model

Both command paths parse generated PowerShell before execution. The analyzers classify commands into nine categories and four risk levels. Syntax errors are blocked; high, critical, dynamic, and unresolved operations require confirmation.

WhatIf preview is offered only when the involved PowerShell commands support `ShouldProcess`; TerminalAI does not append `-WhatIf` to arbitrary external programs. Commands still execute in the caller's process with the caller's privileges.

Secret handling is pattern-based. The assistant sanitizes recognized patterns before adding messages to its history, and the C# helper sanitizes selected display and clipboard paths. Standard PowerShell `ai -Copy` and assistant `/copy` copy the generated block as-is, so inspect copied content yourself.

<!-- sync:configuration -->
## Configuration and language

Configuration is stored in `~/.terminal-ai/config.json`, or below `TERMINAL_AI_CONFIG_DIR`. `TERMINAL_AI_LANG` takes precedence over the file for the requested model-response language.

```powershell
Get-TerminalAiConfig
Set-TerminalAiConfig -Model qwen2.5-coder:7b -Temperature 0.2
Set-TerminalAiConfig -OllamaUrl http://localhost:11434 -TimeoutSeconds 120
Set-TerminalAiLanguage -Language uk
Set-TerminalAiLanguage -Language en -Permanent
```

The non-permanent language command still saves `config.json` and updates the current process. `-Permanent` additionally writes user-level `TERMINAL_AI_LANG` for future processes. Application text remains English.

<!-- sync:terminal -->
## Windows Terminal integration

By default, the installer copies `terminalai.json` to the Windows Terminal fragment directory without editing `settings.json`. It adds two profiles and actions for `ai`, `ai-fix`, `ai-script`, and an assistant split pane. `-ModifySettingsJson` enables the legacy action-injection path after a backup.

```powershell
ai fonts
ai font "Cascadia Code"
Set-TerminalAiFont -Font "Cascadia Code" -Size 13
```

<!-- sync:troubleshooting -->
## Troubleshooting

- **Ollama connection fails:** run `ollama list`; if needed, start `ollama serve`, then confirm `OllamaUrl` with `Get-TerminalAiConfig`.
- **A shortcut does not respond:** run `Import-Module TerminalAI -Force`, confirm PSReadLine is active, and try `F2`.
- **Text encoding is wrong:** use a Unicode-capable font and UTF-8 console output; the installer adds UTF-8 profile settings.
- **Installation state is unclear:** run `ai-doctor` or `Test-TerminalAiInstallation -PassThru`.

<!-- sync:uninstall -->
## Uninstall

```powershell
pwsh -ExecutionPolicy Bypass -File .\Uninstall-TerminalAi.ps1
# Also remove ~/.terminal-ai/config.json:
pwsh -ExecutionPolicy Bypass -File .\Uninstall-TerminalAi.ps1 -PurgeConfig
```

Without `-PurgeConfig`, the uninstaller keeps `~/.terminal-ai`.

<!-- sync:technical -->
## Technical and maintainer documentation

The [Technical and maintainer guide](docs/TECHNICAL.md) contains the full installer and parameter references, configuration fields, architecture, transport details, performance guidance, build and test commands, documentation checks, and release-channel verification.

The English README is canonical. [README.uk.md](README.uk.md) is its Ukrainian translation and follows the same ordered sync sections.

<!-- sync:license -->
## License status

TerminalAI is distributed under the [MIT License](LICENSE).
