# TerminalAI — local Ollama assistance for PowerShell and Windows Terminal

[Ukrainian](README.uk.md) | **English** | [C# binary module](AOT/README.md)

TerminalAI is a Windows PowerShell module that sends command-generation and chat requests to a configured Ollama endpoint. It provides one-shot command generation, an interactive assistant, error diagnosis, script generation, Windows Terminal integration, safety checks before execution, and an optional Claude Code agent launcher backed by Ollama.

TerminalAI is local by default when configured with a local Ollama endpoint (`http://localhost:11434`). The default model is `qwen2.5-coder:7b`. The built-in installer and application interfaces, including status, help, menu, and error text, are English-only. The `Language` setting accepts `en` or `uk` as the requested language for model-generated prose responses such as answers, explanations, diagnoses, and interactive chat replies; it does not localize the UI. Because `OllamaUrl` is user-configurable and agent mode delegates to an external Claude Code CLI, actual privacy and data boundaries depend on how these endpoints and tools are configured.

> [!IMPORTANT]
> Generated commands are untrusted input. Review them before execution. AST checks and WhatIf previews are safety guardrails, NOT a security sandbox. TerminalAI parses PowerShell syntax, classifies risk, and requires confirmation for high-risk or unresolved operations.

## Requirements

TerminalAI installs as four independent products, each with its own requirements. Shared across all of them: **OS:** Windows 10 (20H2+) or Windows 11; installing for the current user needs no special rights, while `-Scope AllUsers` requires Administrator (except for the Ollama product, which installs at the machine level regardless of that flag).

| Product | Shell | Additional requirements |
| :--- | :--- | :--- |
| **Core** — the PowerShell module (`ai`, `ai-fix`, `ai-script`, `ai-chat`, `ai-doctor`) | PowerShell 7+ (pwsh) recommended, or Windows PowerShell 5.1 | — |
| **Ollama** — detects/installs Ollama, checks hardware, pulls a model | either of the above | Internet access for the first download (via winget or the official installer); a few GB of free disk space per model; a GPU helps but is not required |
| **Aot** — compiled .NET 10 helper (`aif` / `ai-fast`) | PowerShell 7+ only | a compatible .NET 10 runtime; automatically skipped on Windows PowerShell 5.1, since .NET Framework 4.8 cannot load a .NET 10 assembly |
| **WindowsTerminal** — fragment extension, command-palette actions, split pane | either of the above | [Windows Terminal](https://aka.ms/terminal) 1.18+ installed |

- Recommended Ollama model: `qwen2.5-coder:7b` (or `qwen2.5-coder:3b` on weaker GPUs)
- Optional, not installed by this installer: a separately installed Claude Code CLI for `ai-agent`

## 📦 Quick Start & Installation Options

### 1. Primary: Built GitHub Release (Recommended)

Download the pre-built versioned release archive:

- **Download:** [**TerminalAI-v0.1.0-preview1-win-x64.zip**](https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/download/v0.1.0-preview1/TerminalAI-v0.1.0-preview1-win-x64.zip)
- **Release Page:** [GitHub Releases v0.1.0-preview1](https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/tag/v0.1.0-preview1)

> [!IMPORTANT]
> Use the assets listed under Releases to install TerminalAI. GitHub’s automatically generated Source code archives are not installers.

#### Installation Steps:
1. Download `TerminalAI-v0.1.0-preview1-win-x64.zip` from the release link above and extract it to a local folder.
2. Open PowerShell (`pwsh` or `powershell.exe`) in the extracted directory and run the installer:
   ```powershell
   pwsh -ExecutionPolicy Bypass -File .\Install-TerminalAi.ps1
   ```
   *(For Windows PowerShell 5.1, run `powershell.exe -ExecutionPolicy Bypass -File .\Install-TerminalAi.ps1`)*
3. By default, the installer deploys all four products automatically:
   - Verifies connectivity with local Ollama (`http://localhost:11434`) and detects installed models.
   - Registers the `TerminalAI` module in `$env:PSModulePath`.
   - Adds a marked auto-import block to `$PROFILE` (saved in UTF-8 with BOM).
   - Deploys the **Fragment Extension** to Windows Terminal (`%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\TerminalAI`).

   Need only a specific product? Use the `-Products` parameter described below.
4. Reload your terminal profile or run:
   ```powershell
   . $PROFILE
   ```

---

### 2. Upcoming Package Channels (Submission in Progress)

> [!NOTE]
> The following channels are currently undergoing submission and review. They are not yet live for direct installation.

- **WinGet (Windows Package Manager — Upcoming)**:
  ```powershell
  # Upcoming - manifest submitted to microsoft/winget-pkgs:
  # winget install TiredRebel.TerminalAI
  ```
  *The WinGet manifest has been prepared and submitted for inclusion in the Windows Package Manager community repository.*

- **PowerShell Gallery (Upcoming)**:
  ```powershell
  # Upcoming - undergoing gallery publishing verification:
  # Install-Module -Name TerminalAI -Scope CurrentUser
  ```
  *PowerShell Gallery packaging is prepared and pending release publication.*

---

### 3. Alternative & Portable Options

- **Option A: Portable Bootstrapper (Temporary Session)**:
  For evaluating TerminalAI in a temporary, memory-only session without modifying system profiles or permanent module paths:
  ```powershell
  irm https://raw.githubusercontent.com/TiredRebel/Windows-Terminal-AI-Plugin/main/bootstrap.ps1 | iex
  ```
  *Loads the module into the current session memory, checks Ollama and active model, registers the `F2` hotkey, and is immediately ready to use for the active session without permanent profile changes.*

  Standalone 1-click execution is also available via **`TerminalAI-Portable.cmd`** or the native executable **`terminalai.exe`**.

- **Option B: Installation from Git Source Repository**:
  Clone the repository and run the local installer:
  ```powershell
  git clone https://github.com/TiredRebel/Windows-Terminal-AI-Plugin.git
  cd Windows-Terminal-AI-Plugin
  pwsh -ExecutionPolicy Bypass -File .\Install-TerminalAi.ps1
  ```

### Installer options

| Parameter | Meaning |
| --- | --- |
| `-Products <Core,Ollama,Aot,WindowsTerminal,All>` | Which products to install (comma-separated for more than one). Defaults to `All` — exactly what earlier installer versions always did. |
| `-Scope CurrentUser|AllUsers` | Install for the current user (default) or all users. `AllUsers` requires Administrator rights. |
| `-Language en|uk` | Set the initial requested language for model-generated prose responses. The installer and application interfaces remain English-only. |
| `-PreferredModel <name>` | Select an Ollama model without using the hardware recommendation. |
| `-SkipOllamaCheck` | Drop the Ollama product (a compatibility shortcut for `-Products` without `Ollama`). |
| `-SkipTerminalConfig` | Drop the WindowsTerminal product (a compatibility shortcut for `-Products` without `WindowsTerminal`). |
| `-AutoConfirm` | Accept installer defaults where supported. |
| `-ModifySettingsJson` | Also update legacy Windows Terminal `settings.json` actions after creating a backup. |
| `-CustomProfilePath`, `-CustomModulePath`, `-CustomFragmentPath` | Override destinations, primarily for controlled deployments and tests. |

### Installing individual products

Each product also ships as its own script under `installers\`, so it can be (re)installed later without running the whole bundle:

```powershell
# Just the PowerShell module + Ollama, no Windows Terminal and no C# module:
pwsh -ExecutionPolicy Bypass -File .\Install-TerminalAi.ps1 -Products Core,Ollama

# The same, via the standalone scripts:
pwsh -ExecutionPolicy Bypass -File .\installers\Install-Core.ps1
pwsh -ExecutionPolicy Bypass -File .\installers\Install-Ollama.ps1

# Add the compiled .NET 10 helper (aif) or the Windows Terminal integration later,
# once Core is already installed:
pwsh -ExecutionPolicy Bypass -File .\installers\Install-Aot.ps1
pwsh -ExecutionPolicy Bypass -File .\installers\Install-WindowsTerminal.ps1
```

The **Aot** and **WindowsTerminal** products assume **Core** is already registered: without it, the `TerminalAI` module has no compiled helper to load, and the split-pane action has no assistant script to point at.

## Command map

| Command | Purpose |
| --- | --- |
| `ai` / `??` | Generate one command with the PowerShell implementation. |
| `aif` / `ai-fast` | Generate one command with the compiled .NET 10 helper on PowerShell 7+. |
| `ai-fix` / `fix-error` | Diagnose `$global:Error[0]` and propose a corrected command. |
| `ai-script` | Generate a multi-line PowerShell script and optionally save it. |
| `ai-chat` / `ai-assistant` | Start the interactive assistant with bounded session history. |
| `ai-agent` | Launch Claude Code against the configured Ollama endpoint. |
| `ai-doctor` | Check the installed module, profile, terminal fragment, Ollama, model, safety helpers, and optional agent mode. |
| `ai-help` | Show built-in help. |

### One-shot command generation

```powershell
ai "find files larger than 100 MB"
ai "show listening TCP ports" -Execute
ai "get the default gateway" -Copy
ai "find processes using more than 1 GB" -Alias
ai "explain PowerShell remoting" -Ask
ai "stop the Spooler service" -Preview
ai "explain this pipeline" -Explain
ai "show services" -Model qwen2.5-coder:7b
```

`Invoke-AiCommand` accepts `-Execute` (`-x`, `-y`), `-Copy` (`-c`), `-Alias` (`-a`, `-Short`, `-UseAliases`), `-Explain`, `-Ask` (`-chat`, `-question`), `-Preview` (`-w`, `-WhatIf`), and `-Model`.

Without a prompt, `ai` shows its quick-reference card. It also recognizes management subcommands such as `help`, `status`, `models`, `model <name>`, `lang <en|uk>`, `font`, `fonts`, `alias`, and `config`; `lang` changes the requested language for model-generated prose, not the application UI.

### Inline generation

At a PSReadLine prompt, type a comment describing the command, then press `F2`, `Ctrl+G`, or the configured `Ctrl+Alt+A` chord:

```powershell
# show the five processes using the most CPU
```

TerminalAI replaces the input with generated PowerShell code. Review the result before pressing Enter. Shortcut availability depends on PSReadLine and the active console host.

### Error diagnosis

After a failed PowerShell command:

```powershell
ai-fix
ai-fix -Model qwen2.5-coder:7b
```

The diagnostic request includes the latest PowerShell error message, failed input line, and script location when available. Treat those values as data that will be sent to the configured Ollama endpoint.

### Script generation

```powershell
ai-script "create a disk-space report with error handling"
ai-script "create a disk-space report" -OutputPath .\Get-DiskReport.ps1 -Edit
```

`New-AiScript` accepts `-Description` (position 0), `-OutputPath`, `-Edit`, and `-Model`. Existing files are compared and require confirmation before overwrite; non-interactive overwrite is blocked. New files are written as UTF-8 with BOM. `ai-script` does not expose a `-Force` parameter.

## Interactive assistant

```powershell
ai-chat
ai-chat -Model qwen2.5-coder:7b
```

The assistant sends conversation history to Ollama's `/api/chat` endpoint. It sanitizes recognized secret patterns before storing messages and keeps a bounded FIFO history. Redaction is pattern-based and cannot guarantee detection of every secret.

| Slash command | Action |
| --- | --- |
| `/help`, `/?` | Show assistant help. |
| `/models` | List models reported by Ollama. |
| `/model <name>` | Change the model for this session. |
| `/lang <en|uk>` | Change the requested language for model-generated chat replies; `permanent` also persists it in the Windows user environment. |
| `/context` | Show history usage. |
| `/reset` | Clear conversation history. |
| `/inspect [clear]` | Show diagnostic context; `clear` removes the recorded last error. |
| `/run` | Send the latest code block through the PowerShell execution gate. |
| `/read <path>` | Add a local text file to the conversation context, subject to size checks. |
| `/copy` | Copy the latest code block; inspect it for secrets first. |
| `/save [path.ps1]` | Save the latest code block using overwrite protection. |
| `/clear` | Clear the screen without clearing history. |
| `/exit` | End the assistant session. |

## Optional agent mode

`ai-agent` starts an installed Claude Code executable with `ANTHROPIC_BASE_URL` pointed at the configured Ollama URL and uses a separate data directory, `~/.terminal-ai/claude` by default.

```powershell
ai-agent -CheckOnly
ai-agent "inspect the current git diff and run relevant tests"
ai-agent -WorkingDir C:\src\project -Model qwen2.5-coder:7b
ai-agent -Resume
ai-agent -Print "summarize this project"
```

`Invoke-AiAgent` accepts `-Prompt`, `-Model`, `-WorkingDir`, `-Resume`, `-Print`, `-ConfirmTrust` (aliases: `-Force`, `-y`, `-Yes`), and `-CheckOnly`. `-ConfirmTrust` skips TerminalAI's launch prompt; Claude Code retains its own permission model.

TerminalAI also sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and removes selected ambient provider keys in the child process. These settings reduce unintended external traffic but are not an independent guarantee about every behavior of the separately installed Claude Code CLI.

## Compiled .NET 10 helper command path

On PowerShell 7+, the main module dynamically loads `TerminalAI.Aot.dll` (a managed .NET 10 C# binary module) and exports `Invoke-AiCommandFast` as `aif` and `ai-fast`.

```powershell
aif "find large log files"
aif "restart the Spooler service" -Execute
aif "how do PowerShell pipelines stream objects?" -Ask
aif agent "inspect git status"
```

The C# project targets `net10.0`. Despite the historical `AOT` directory and assembly name, the project currently builds a standard managed DLL with `dotnet build`; it does not define a NativeAOT publish configuration. See the [C# component guide](AOT/README.md).

## Safety model

Generated commands are untrusted input. Always review them before execution. Both command paths parse generated PowerShell before execution. AST checks and WhatIf previews are safety guardrails, NOT a security sandbox. The analyzers inspect nested commands, aliases, parameters, literal or unresolved targets, dynamic invocation, and splatting. They use nine categories:

`ReadOnly`, `SystemChange`, `Deletion`, `NetworkChange`, `ServiceOrProcess`, `Registry`, `DiskOrPartition`, `DynamicOrUnknown`, and `ExternalProgram`.

Risk levels are `Low`, `Medium`, `High`, and `Critical`. Syntax errors are blocked. High, critical, dynamic, and unresolved operations require explicit confirmation. `-Preview` is available only where the involved PowerShell commands support `ShouldProcess`; TerminalAI does not append `-WhatIf` to arbitrary external programs.

Secret sanitization covers recognized API keys, bearer tokens, password-like arguments, and private-key blocks before selected display, history, or clipboard operations. It is a defense-in-depth filter, not a substitute for reviewing generated commands and removing sensitive input.

## Configuration

Configuration is stored in `~/.terminal-ai/config.json`, or under the directory specified by `TERMINAL_AI_CONFIG_DIR`. `TERMINAL_AI_LANG` takes precedence for the requested model-response language. Built-in UI and status/error messages remain English.

```powershell
Get-TerminalAiConfig
Set-TerminalAiConfig -Model qwen2.5-coder:7b -Temperature 0.2
Set-TerminalAiConfig -OllamaUrl http://localhost:11434 -TimeoutSeconds 120
Set-TerminalAiLanguage -Language uk
Set-TerminalAiLanguage -Language en -Permanent
```

| Setting | Default | Purpose |
| --- | --- | --- |
| `OllamaUrl` | `http://localhost:11434` | Ollama base URL. |
| `Model` | `qwen2.5-coder:7b` | Default generation and chat model. |
| `Language` | `en` | Requested language for model-generated prose responses (`en` or `uk`); it does not localize application text. |
| `Font` | `Cascadia Code` | Preferred Windows Terminal font. |
| `Temperature` | `0.2` | Default sampling temperature where a command does not override it. |
| `TimeoutSeconds` | `120` | HTTP request timeout. |
| `HotkeyChord` | `Ctrl+Alt+A` | Configured inline shortcut. |
| `AutoCopy` | `false` | Copy behavior preference. |
| `ShowExplanation` | `true` | Explanation display preference. |
| `UseAliases` | `false` | Prefer short PowerShell aliases. |
| `AgentModel` | `qwen2.5-coder:7b` | Default model for `ai-agent`. |
| `ClaudeExecutable` | empty | Optional explicit Claude Code path. |
| `AgentDataDirectory` | empty | Optional agent configuration directory override. |

## Windows Terminal integration

By default the installer copies `terminalai.json` to a Windows Terminal fragment directory without editing `settings.json`. The fragment defines four profiles and four actions for `ai`, `ai-fix`, `ai-script`, and an assistant split pane. Use `-ModifySettingsJson` only for the legacy action-injection path; the installer backs up the file first.

Font commands read and update Windows Terminal settings:

```powershell
ai fonts
ai font "Cascadia Code"
Set-TerminalAiFont -Font "Cascadia Code" -Size 13
```

## Architecture

```text
Install-TerminalAi.ps1
  -> installs TerminalAI.psd1 / TerminalAI.psm1 and companion scripts
  -> writes ~/.terminal-ai/config.json
  -> adds a marked profile import block
  -> deploys terminalai.json

TerminalAI.psm1
  -> TerminalAiConfig.ps1       configuration, response language, fonts
  -> TerminalAiAssistant.ps1    interactive /api/chat session
  -> TerminalAiAgent.ps1        optional Claude Code launcher
  -> Ollama /api/generate       one-shot generation
  -> AST analyzer and gate      pre-execution inspection
  -> TerminalAI.Aot.dll         optional PowerShell 7 C# command path
```

The PowerShell and C# paths share the configuration file and major user workflows, but they are separate implementations. Behavior parity should be verified by tests rather than assumed.

## Verification and development

Syntax check:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\check_syntax.ps1
```

Deterministic root checks, with live Ollama calls skipped:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Test-TerminalAi.ps1
```

Add `-RunLiveTests` only when Ollama is running and model inference is intentionally in scope.

Focused suites:

```powershell
Get-ChildItem .\tests\*.Tests.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName }
Get-ChildItem .\AOT\tests\*.Tests.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName }
```

Build the C# component:

```powershell
dotnet build .\AOT\TerminalAI.Aot.csproj -c Release
```

The post-build target copies the DLL to the repository root. A loaded DLL may remain locked by an existing PowerShell process; validate a new build in a fresh `pwsh -NoProfile` session.

## Troubleshooting

Run the built-in diagnostics first:

```powershell
ai-doctor
Test-TerminalAiInstallation -PassThru
```

- **Ollama cannot be reached:** run `ollama list`, then `ollama serve` if necessary; confirm `OllamaUrl`.
- **The model is missing:** run `ollama pull <model>` or select an installed model with `ai model <name>`.
- **A shortcut does not respond:** use a PSReadLine-capable interactive host and reload with `Import-Module TerminalAI -Force`.
- **Cyrillic is rendered incorrectly:** use a Unicode font and set `[Console]::InputEncoding`, `[Console]::OutputEncoding`, and `$OutputEncoding` to UTF-8.
- **The C# command is unavailable:** use PowerShell 7+, verify the root DLL exists, and check the module import diagnostics.
- **Agent mode is unavailable:** run `ai-agent -CheckOnly`; verify the Claude Code executable, Ollama, selected model, and working directory.

## Uninstall

```powershell
pwsh -ExecutionPolicy Bypass -File .\Uninstall-TerminalAi.ps1
```

The uninstaller removes the installed module directory, the marked profile block, and the Windows Terminal fragment for the selected scope. It preserves `~/.terminal-ai` by default. To remove configuration too:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Uninstall-TerminalAi.ps1 -PurgeConfig
```

Use `-Scope AllUsers` from an elevated PowerShell session for an all-users installation.

## License status

TerminalAI is released under the [MIT License](LICENSE).
