# TerminalAI.Aot — High-Performance C# Binary Module for PowerShell

High-performance compiled C# binary module for [TerminalAI](https://github.com/TiredRebel/TerminalAI) on PowerShell 7+ (.NET 10 / `net10.0`).

---

## 1. Architectural Overview & Performance

`TerminalAI.Aot` is a compiled binary PowerShell module (`TerminalAI.Aot.dll`) providing sub-millisecond command dispatch and eliminating `.psm1` AST script parsing overhead:
- **Zero-Allocation HTTP/2 Client**: Persistent `SocketsHttpHandler` with keep-alive connection pooling, eliminating TCP handshake overhead on successive Ollama requests.
- **Direct AST Analysis**: Employs PowerShell 7 native `System.Management.Automation.Language.Parser` directly in C# for instant command structure and parameter verification.
- **Win32 Direct Interop**: Native P/Invoke for clipboard operations (`OpenClipboard`/`SetClipboardData`) and console scan codes, avoiding child process spawns or shell pipeline overhead.
- **Full Parity with Core Module**: Identical configuration store (`~/.terminal-ai/config.json`), model management, interactive hotkey menu, and bilingual localization (English default, Ukrainian on demand).

---

## 2. Security Architecture

### A. Fail-Closed AST Command Classification
Before any command is executed, `AotCommandAstAnalyzer` decomposes the pipeline into its AST components:
- **8 Command Categories**: `ReadOnly`, `SystemChange`, `Deletion`, `NetworkChange`, `ServiceOrProcess`, `Registry`, `DiskOrPartition`, `DynamicOrUnknown`.
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

---

## 3. Building & Deployment

### Build Command:
```powershell
dotnet build -c Release "E:\Windows Terminal Ai plugin\AOT\TerminalAI.Aot.csproj"
```

### Handling Process File Locks:
When `TerminalAI.Aot.dll` is actively loaded in a running PowerShell or Windows Terminal session, the Windows kernel prevents overwriting the file.
- The project file `TerminalAI.Aot.csproj` incorporates `ContinueOnError="true"` and automatic retries in its `PostBuild` copy target, allowing compilation to succeed even if an existing instance is running.
- To safely test new builds, reload the assembly in a fresh `pwsh -NoProfile` session or run:
  ```powershell
  Remove-Module TerminalAI.Aot -ErrorAction SilentlyContinue
  Import-Module ./AOT/bin/Release/net10.0/TerminalAI.Aot.dll
  ```

---

## 4. Usage Reference

### Primary Aliases:
- `aif <prompt>`: Fast compiled C# execution
- `ai-fast <prompt>`: Full cmdlet name (`Invoke-AiCommandFast`)

### Command Examples:
```powershell
# Quick command generation
aif "find files larger than 100MB"

# Immediate execution (subject to security gate)
aif "get listening TCP ports" -Execute

# Save generated script with unified diff preview and overwrite protection
aif "script to backup event logs to zip" -SavePath "./backup.ps1"

# Force overwrite of existing script
aif "updated script to backup event logs" -SavePath "./backup.ps1" -Force

# Detailed educational explanation of command
aif "tar -czvf archive.tar.gz ./src" -Explain

# Direct conceptual question
aif "how do PowerShell pipelines handle streaming objects?" -Ask

# List installed Ollama models
aif models

# Switch active model
aif model qwen2.5-coder:7b

# Switch language (en / uk)
aif lang uk
```

### Interactive Menu Hotkeys (after generation):
- `[Enter]`: Execute command in current session (enforces security gate)
- `[C]`: Copy sanitized command to system clipboard
- `[I]`: Insert command into prompt line for manual editing
- `[S]`: Toggle between short aliases and full cmdlet names
- `[X]`: Explain command syntax, flags, and safety considerations
- `[A]`: Provide full conceptual explanation
- `[W]`: Save script to file with safe unified diff preview
- `[Esc]`: Cancel and return to prompt
