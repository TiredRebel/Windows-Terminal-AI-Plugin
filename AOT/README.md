# TerminalAI.Aot — Managed .NET 10 C# Binary Module for PowerShell

**English** | [Українська](README.uk.md) | [Main documentation](../README.en.md)

Managed .NET 10 C# binary module (compiled .NET 10 helper) for TerminalAI on PowerShell 7+ (`net10.0`). The historical `AOT` name does not mean the current project produces a NativeAOT executable: `TerminalAI.Aot.csproj` builds a standard managed DLL with `dotnet build` and has no NativeAOT (`PublishAot`) configuration.

> [!IMPORTANT]
> Generated commands are untrusted input. Review them before execution. AST checks and WhatIf previews are safety guardrails, NOT a security sandbox. TerminalAI parses PowerShell syntax, classifies risk, and requires confirmation for high-risk or unresolved operations.

---

## 1. Architecture

`TerminalAI.Aot` is a compiled .NET 10 helper (managed binary PowerShell module `TerminalAI.Aot.dll`) that provides an alternative implementation of command generation and local processing:
- **Persistent HTTP Client**: A shared `HttpClient` backed by `SocketsHttpHandler` reuses connections for Ollama requests.
- **Direct AST Analysis**: Employs PowerShell 7 native `System.Management.Automation.Language.Parser` directly in C# for instant command structure and parameter verification.
- **Win32 Direct Interop**: Native P/Invoke for clipboard operations (`OpenClipboard`/`SetClipboardData`) and console scan codes, avoiding child process spawns or shell pipeline overhead.
- **Shared user contract**: The module reads `~/.terminal-ai/config.json` and supports the main one-shot generation, model, language, safety, save, and agent workflows. Verify parity with the PowerShell path through tests rather than assuming it.

---

## 2. Security Architecture

> [!NOTE]
> All generated commands are treated as untrusted input. AST parsing and WhatIf simulation are safety guardrails, NOT a security sandbox. Execution occurs in the caller's PowerShell process with the user's current privileges.

### A. Fail-Closed AST Command Classification
Before any command is executed, `AotCommandAstAnalyzer` decomposes the pipeline into its AST components:
- **9 Command Categories**: `ReadOnly`, `SystemChange`, `Deletion`, `NetworkChange`, `ServiceOrProcess`, `Registry`, `DiskOrPartition`, `DynamicOrUnknown`, and `ExternalProgram`.
- **4 Risk Tiers**: `Low`, `Medium`, `High`, `Critical`.
- **Dynamic Invocation Detection**: Identifies dynamic invocation (`& $var`, `Invoke-Expression`) and splatting (`@params`), blocking unvalidated execution.
- **Invalid Parameter Detection**: Validates parameters against session cmdlet metadata to detect model hallucinations before invocation.

### B. Fail-Closed Execution Gate
Execution is mediated by `AotExecutionGate`:
- **Syntax Error Blocking**: Any command containing parser syntax errors is blocked immediately before execution.
- **Interactive Confirmation**: Operations classified as `High`, `Critical`, or `DynamicOrUnknown` require explicit user confirmation (`[y/N]`), even if `-Execute` was passed.
- **Safe `-WhatIf` Preview Simulation**: Cmdlets supporting `SupportsShouldProcess` can be safely previewed; external binary executables that do not support ShouldProcess are blocked with `PreviewUnavailable` to prevent unintended execution.

### C. Secret Sanitization & Safe Clipboard
- **Deterministic Token Redaction**: `AotSecretSanitizer` redacts sensitive tokens (OpenAI `sk-***`, GitHub PATs, AWS access keys, Slack tokens, private PEM keys, and cmdlet password arguments) before rendering cards or copying to clipboard.
- **No Script Block Clipboard**: Pure Win32 clipboard API eliminates script injection vectors during copy operations.

### D. Safe Script Generation & Unified Diff Preview
- **Multi-line Script Detection**: Recognizes multi-line automation scripts and functions.
- **Overwrite Protection**: Compares proposed script content against existing target files.
  - Identical files: reports `Status = "Identical"` without unnecessary disk writes.
  - Differing files: renders a colorized unified diff (`+ Added`, `- Removed`, `  Unchanged`) and prompts `[y/N]`.
  - Non-interactive sessions: safely blocks overwrites (`Status = "BlockedNonInteractive"`).
- **Atomic UTF-8 BOM Writing**: Writes atomically via temporary files (`.tmp.<guid>`) with standard UTF-8 BOM encoding.

### E. Resilient HTTP & Timeout Management
- **Configurable Timeouts**: Wires `AiConfig.TimeoutSeconds` to per-request `CancellationTokenSource` instances, eliminating hardcoded delays.
- **Friendly Diagnostics**: Generates actionable, human-friendly error messages on connection refused (prompting `ollama serve`), timeouts, and missing models (HTTP 404 prompting `ollama pull <model>`).

### F. Safe Autonomous Agent Delegation
- **Typed Runspace Invocation**: When the `-Agent` (`-Autonomous`) flag is passed or when the prompt begins with the prefix `agent <task>`, `InvokeAiCommandFastCmdlet` delegates execution to the parent module's `Invoke-AiAgent` cmdlet.
- **Zero Raw String Parsing**: Uses strongly-typed `PowerShell.Create(RunspaceMode.CurrentRunspace).AddCommand("Invoke-AiAgent")` with parameter binding, preserving environmental safety and avoiding command injection.
- **Graceful Fallback**: If the parent module is not imported, displays a clean guidance message directing the user to run `Import-Module TerminalAI` without crashing.

---

## 3. Building, Deployment & Testing

### Build Command:
```powershell
dotnet build .\AOT\TerminalAI.Aot.csproj -c Release
```

### Handling Process File Locks:
When `TerminalAI.Aot.dll` is actively loaded in a running PowerShell or Windows Terminal session, the Windows kernel prevents overwriting the file.
- The project file `TerminalAI.Aot.csproj` incorporates `ContinueOnError="true"` and automatic retries in its `PostBuild` copy target, allowing compilation to succeed even if an existing instance is running.
- To safely test new builds, reload the assembly in a fresh `pwsh -NoProfile` session or run:
  ```powershell
  Remove-Module TerminalAI.Aot -ErrorAction SilentlyContinue
  Import-Module ./AOT/bin/Release/net10.0/TerminalAI.Aot.dll
  ```

### Running Automated Test Suites:
The AOT component includes seven deterministic test scripts:
```powershell
# Run all AOT test suites in PowerShell 7:
Get-ChildItem -Path ./AOT/tests/*.Tests.ps1 | ForEach-Object {
    Write-Host "Running: $($_.Name)" -ForegroundColor Cyan
    & $_.FullName
}
```

| Suite | Description |
| :--- | :--- |
| `AotAstAnalyzer.Tests.ps1` | AST parsing, categories, risk tiers, targets, and parameter verification. |
| `AotExecutionGate.Tests.ps1` | Fail-closed execution, confirmation, and WhatIf behavior. |
| `AotSecretSanitizer.Tests.ps1` | Pattern-based secret redaction and clipboard handling. |
| `AotSecurity.Tests.ps1` | End-to-end security boundary checks. |
| `AotScriptSafety.Tests.ps1` | Multi-line detection, diff output, and UTF-8 BOM file writing. |
| `AotHttpClient.Tests.ps1` | Timeouts, cancellation, and HTTP diagnostics. |
| `AotAgentDelegation.Tests.ps1` | Agent routing and graceful fallback. |

The current test run is the source of truth; this document intentionally does not freeze a passing count.

---

## 4. Usage Reference

### Primary Aliases:
- `aif <prompt>`: Fast compiled .NET 10 helper execution
- `ai-fast <prompt>`: Descriptive alias
- `Invoke-AiCommandFast <prompt>`: Full cmdlet name

### Parameter Reference:
| Parameter | Aliases | Type | Description |
| :--- | :--- | :---: | :--- |
| `[Prompt]` | *(Positional 0)* | `string[]` | Natural language request, subcommand (`models`, `model <name>`, `lang <en\|uk>`, `status`, `config`, `help`), or `agent <task>`. |
| `-Execute` | `-x`, `-y` | `switch` | Execute generated command immediately without interactive menu (subject to security gate). |
| `-Copy` | `-c` | `switch` | Copy generated command directly to clipboard with secret sanitization. |
| `-Alias` | `-a`, `-Short`, `-UseAliases` | `switch` | Generate compact pipelines using standard short aliases (e.g. `gps`, `gci`, `select`, `?`). |
| `-Explain` | | `switch` | Produce a comprehensive structured technical breakdown of command syntax, flags, and safety. |
| `-Ask` | `-chat`, `-question` | `switch` | Ask a direct conceptual question and receive an educational text response instead of executable code. |
| `-Agent` | `-Autonomous` | `switch` | Delegate task to autonomous Claude Code agent mode backed by `Invoke-AiAgent`. |
| `-SavePath` | `-Save`, `-OutFile` | `string` | Save script to specified path with unified diff preview, overwrite prompt, and UTF-8 BOM encoding. |
| `-Force` | `-f` | `switch` | Bypass overwrite confirmation when saving to an existing script file. |
| `-Model` | | `string` | Override the active Ollama model for this specific invocation. |
| `-ConfirmInput` | | `string` | Pre-supplied gate response (`'y'` or `'n'`) for unattended automation and unit testing. |

### Command Examples:
```powershell
# 1. Quick command generation
aif "find files larger than 100MB"

# 2. Immediate execution (subject to security gate confirmation for high-risk operations)
aif "get listening TCP ports" -Execute
aif "restart spooler service" -x

# 3. Copy directly to clipboard
aif "get default gateway IP address" -Copy

# 4. Generate compact command with short aliases
aif "find processes consuming more than 500MB working set" -Alias

# 5. Save generated script with unified diff preview and overwrite protection
aif "script to backup event logs to zip" -SavePath "./backup.ps1"

# 6. Force overwrite of existing script
aif "updated script to backup event logs" -SavePath "./backup.ps1" -Force

# 7. Detailed educational breakdown of command
aif "tar -czvf archive.tar.gz ./src" -Explain

# 8. Direct conceptual question
aif "how do PowerShell pipelines handle streaming objects?" -Ask

# 9. Autonomous agent execution
aif agent "analyze git diff and execute unit tests"
aif "refactor module logging" -Agent

# 10. Subcommands & management
aif models                     # List installed Ollama models
aif model qwen2.5-coder:7b     # Switch active model
aif lang uk                    # Switch language to Ukrainian
aif lang en                    # Switch language to English
aif status                     # View active model, endpoint, language, and font
aif config                     # View raw JSON configuration
aif help                       # View quick reference card
```

### Interactive Menu Hotkeys (after generation):
| Hotkey | English Action | Українська дія | Description |
| :---: | :--- | :--- | :--- |
| **`[Enter]`** | Execute | Виконати | Executes command in current session (enforces security gate) |
| **`[C]`** | Copy | Скопіювати | Copies sanitized command to system clipboard via Win32 API |
| **`[I]`** | Insert | Вставити в рядок | Inserts command cleanly into next prompt line for manual editing |
| **`[S]`** | Toggle Aliases | Перемкнути аліаси | Toggles between short aliases (`gci`, `gps`) and full cmdlet names |
| **`[W]`** | Save | Зберегти у файл | Prompts for path and saves script with colorized Unified Diff preview |
| **`[X]`** | Explain | Пояснити код | Generates technical explanation of syntax, flags, and safety |
| **`[A]`** | Ask Text | Текстова відповідь | Switches to conversational text consultation |
| **`[Esc]`** | Cancel | Скасувати | Cancels menu and cleanly returns to prompt |

---

## 5. Architecture & Class Structure

```
AOT/
├── AiConfig.cs                  # Thread-safe JSON configuration loader (~/.terminal-ai/config.json)
├── AotCommandAstAnalyzer.cs     # AST visitor: 9 categories, 4 risk tiers, target extraction
├── AotExecutionGate.cs          # Fail-closed execution gate, WhatIf simulation, [y/N] confirmation
├── AotClipboard.cs              # Safe Win32 P/Invoke clipboard (OpenClipboard / SetClipboardData)
├── AotSecretSanitizer.cs        # Deterministic regex token redaction (OpenAI, GitHub, AWS, Slack, PEM)
├── AotDiffRenderer.cs           # Colorized unified diff generation (+ Added, - Removed, Unchanged)
├── AotScriptSafety.cs           # Safe script file writer: multi-line check, overwrite prompt, UTF-8 BOM
├── OllamaClient.cs              # High-performance HttpClient, keep-alive pooling, per-request cancellation
├── PowerShellAliasConverter.cs  # High-speed bidirectional short/full cmdlet transformation
├── Win32Console.cs              # Raw console I/O, virtual keypress capture, ANSI box drawing
└── InvokeAiCommandFastCmdlet.cs # Primary cmdlet implementation (Invoke-AiCommandFast / ai-fast / aif)
```
