# TerminalAI.psm1 - PowerShell AI extension backed by local Ollama
# Requires -Version 5.1

# Enable complete UTF-8 support in the console
try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# Load System.Net.Http for reliable Windows PowerShell 5.1 support
try {
    Add-Type -AssemblyName System.Net.Http -ErrorAction Ignore
} catch { }

# Load the configuration helper module
$configScriptPath = Join-Path $PSScriptRoot "TerminalAiConfig.ps1"
if (Test-Path $configScriptPath) {
    . $configScriptPath
}

# Load the optional Claude Code agent mode module
$agentScriptPath = Join-Path $PSScriptRoot "TerminalAiAgent.ps1"
if (Test-Path $agentScriptPath) {
    . $agentScriptPath
}

# Load the compiled C# helper module when available
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $aotCandidates = @(
        (Join-Path $PSScriptRoot "TerminalAI.Aot.dll"),
        (Join-Path $PSScriptRoot "AOT\bin\Release\net10.0\TerminalAI.Aot.dll")
    )
    foreach ($cand in $aotCandidates) {
        if (Test-Path $cand) {
            try {
                Import-Module $cand -Global -ErrorAction Ignore
                break
            } catch { }
        }
    }
}


# Helper for reliable deferred insertion through synthesized keys in Windows Terminal ConPTY
if (-not ([System.Management.Automation.PSTypeName]'TerminalAiPasteHelper').Type) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

public static class TerminalAiPasteHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern uint MapVirtualKey(uint uCode, uint uMapType);

    private const byte VK_CONTROL = 0x11;
    private const byte VK_V = 0x56;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    public static void DelayedPaste(int delayMs = 200) {
        Task.Run(() => {
            try {
                Thread.Sleep(delayMs);
                byte scanCtrl = (byte)MapVirtualKey(VK_CONTROL, 0);
                byte scanV = (byte)MapVirtualKey(VK_V, 0);

                keybd_event(VK_CONTROL, scanCtrl, 0, UIntPtr.Zero);
                keybd_event(VK_V, scanV, 0, UIntPtr.Zero);
                keybd_event(VK_V, scanV, KEYEVENTF_KEYUP, UIntPtr.Zero);
                keybd_event(VK_CONTROL, scanCtrl, KEYEVENTF_KEYUP, UIntPtr.Zero);
            } catch { }
        });
    }
}
'@ -ErrorAction SilentlyContinue
    } catch { }
}

# --- HELPERS ---

function Format-AiCodeOutput {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    $clean = $Text.Trim()

    # Remove reasoning-model output through the closing </think> tag
    if ($clean -match '(?si)</think>\s*(.*)') {
        $clean = $Matches[1].Trim()
    } elseif ($clean -match '(?si)<think>.*?</think>\s*(.*)') {
        $clean = $Matches[1].Trim()
    }

    # Remove Markdown code fences, including an unclosed fence
    if ($clean -match '(?si)```(?:powershell|pwsh)?\r?\n?(.*?)\r?\n?```') {
        $clean = $Matches[1].Trim()
    } elseif ($clean -match '(?si)```(?:powershell|pwsh)?\r?\n?(.*)') {
        $clean = ($Matches[1] -replace '(?s)```$', '').Trim()
    }
    # Remove a single pair of wrapping backticks
    if ($clean.StartsWith('`') -and $clean.EndsWith('`') -and $clean.Length -gt 2) {
        $clean = $clean.Substring(1, $clean.Length - 2).Trim()
    }

    return $clean
}
Set-Alias -Name Clean-AiCodeOutput -Value Format-AiCodeOutput

$script:TerminalAiAliasPairs = @(
    @{ Full = "Get-Process"; Short = "gps" },
    @{ Full = "Get-ChildItem"; Short = "gci" },
    @{ Full = "Where-Object"; Short = "?" },
    @{ Full = "ForEach-Object"; Short = "%" },
    @{ Full = "Select-Object"; Short = "select" },
    @{ Full = "Sort-Object"; Short = "sort" },
    @{ Full = "Measure-Object"; Short = "measure" },
    @{ Full = "Get-Content"; Short = "gc" },
    @{ Full = "Set-Content"; Short = "sc" },
    @{ Full = "Select-String"; Short = "sls" },
    @{ Full = "Get-Service"; Short = "gsv" },
    @{ Full = "Stop-Process"; Short = "kill" },
    @{ Full = "Format-Table"; Short = "ft" },
    @{ Full = "Format-List"; Short = "fl" },
    @{ Full = "Export-Csv"; Short = "epcsv" },
    @{ Full = "Import-Csv"; Short = "ipcsv" },
    @{ Full = "Get-Help"; Short = "help" },
    @{ Full = "Clear-Host"; Short = "cls" },
    @{ Full = "Copy-Item"; Short = "cpi" },
    @{ Full = "Move-Item"; Short = "mi" },
    @{ Full = "Remove-Item"; Short = "ri" },
    @{ Full = "New-Item"; Short = "ni" },
    @{ Full = "Get-Item"; Short = "gi" },
    @{ Full = "Set-Item"; Short = "si" },
    @{ Full = "Get-Location"; Short = "gl" },
    @{ Full = "Set-Location"; Short = "sl" }
)

function ConvertTo-AiShortAliases {
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return $Code }

    $Code = [regex]::Replace($Code, '\b(?:gci|Get-ChildItem)\s+tcpconn\b', 'Get-NetTCPConnection', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($p in $script:TerminalAiAliasPairs) {
        $pattern = "(?<![\w\-])\b" + [regex]::Escape($p.Full) + "\b(?![\w\-])"
        $Code = [regex]::Replace($Code, $pattern, $p.Short, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    $Code = [regex]::Replace($Code, "(?<![\w\-])-ErrorAction\s+(?:SilentlyContinue|0)\b", "-ea 0", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return $Code
}

function ConvertTo-AiFullCmdlets {
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return $Code }

    $Code = [regex]::Replace($Code, '\b(?:gci|Get-ChildItem)\s+tcpconn\b', 'Get-NetTCPConnection', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($p in $script:TerminalAiAliasPairs) {
        $sh = $p.Short
        $full = $p.Full
        if ($sh -in @("?", "%")) {
            $pattern = "(?<=[|\({;\s]|^)" + [regex]::Escape($sh) + "(?=\s|[{])"
            $Code = [regex]::Replace($Code, $pattern, $full)
        } else {
            $pattern = "(?<![\w\-])\b" + [regex]::Escape($sh) + "\b(?![\w\-])"
            $Code = [regex]::Replace($Code, $pattern, $full, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $Code = [regex]::Replace($Code, "(?<![\w\-])-ea\s+0\b", "-ErrorAction SilentlyContinue", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return $Code
}

function Get-TerminalAiText {
    param([string]$Key)
    $cfg = Get-TerminalAiConfig
    $lang = "en"

    $dict = @{
        "en" = @{
            "CardTitle"         = "AI Command"
            "CardTitleAnswer"   = "AI Answer"
            "CardTitleFixed"    = "Fixed Command"
            "CardTitleExplain"  = "Command Explanation"
            "Connecting"        = "Connecting to Ollama"
            "Answering"         = "Generating answer via"
            "Explaining"        = "Generating detailed command explanation..."
            "Fixing"            = "Analyzing last error"
            "Scripting"         = "Generating complex PowerShell script..."
            "MenuEnter"         = "Execute"
            "MenuCopy"          = "Copy"
            "MenuInsert"        = "Insert into line"
            "MenuAlias"         = "Alias"
            "MenuFull"          = "Full"
            "MenuExplain"       = "Explain code"
            "MenuAsk"           = "Text answer"
            "MenuWhatIf"        = "Preview (-WhatIf)"
            "MenuCancel"        = "Cancel"
            "Copied"            = "Copied to clipboard!"
            "Inserted"          = "Command inserted into input line!"
            "Executing"         = "Executing command:"
            "ExecutingFixed"    = "Executing fixed command:"
            "Canceled"          = "Canceled."
            "UnknownCmdlet"     = "Command not found in PowerShell session."
            "UnknownCmdletHint" = "(Likely your query was informational or model hallucinated a cmdlet)"
            "Warning"           = "Warning"
            "NoError"           = "No errors detected in current session! Everything runs smoothly."
            "Diagnosis"         = "Problem Diagnosis:"
            "FailedCommand"     = "Failed command:"
            "ErrorLabel"        = "Error:"
            "SaveScriptPrompt"  = "Save this script to a file? [Y/N]: "
            "EnterFileName"     = "Enter file name (default: {0}): "
            "SavedAt"           = "Script successfully saved to:"
            "Welcome"           = "✦ Terminal AI activated! Try: ai or F2"
        }
    }

    if ($dict[$lang] -and $dict[$lang][$Key]) {
        return $dict[$lang][$Key]
    } elseif ($dict["en"][$Key]) {
        return $dict["en"][$Key]
    } else {
        return $Key
    }
}

function Show-TerminalAiWelcome {
    <#
    .SYNOPSIS
        Displays the TerminalAI welcome message.
    #>
    [CmdletBinding()]
    param()

    Write-Host (Get-TerminalAiText "Welcome") -ForegroundColor Cyan
}

function Show-TerminalAiHelp {
    <#
    .SYNOPSIS
        Detailed interactive help for TerminalAI.
    .DESCRIPTION
        Displays structured help for daily use:
        - all: system overview and command map
        - shortcuts: aliases, flags, and keyboard shortcuts
        - models: Ollama models, RAM/VRAM requirements, and coding recommendations
        - examples: practical DevOps, administration, and automation examples
        - workflow: interactive Windows Terminal workflow
    .PARAMETER Topic
        Help topic: all, shortcuts, models, examples, workflow, or config.
    .EXAMPLE
        ai-help
    .EXAMPLE
        ai-help shortcuts
    .EXAMPLE
        ai help models
    .EXAMPLE
        aif help examples
    #>
    [CmdletBinding()]
    [Alias("ai-help")]
    param(
        [Parameter(Position = 0)]
        [ValidateSet("all", "shortcuts", "models", "examples", "workflow", "config")]
        [string]$Topic = "all"
    )

    $cfg = Get-TerminalAiConfig
    $isUk = ($cfg.Language -in @("uk", "ua"))
    $conWidth = 80
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 20) {
            $conWidth = $Host.UI.RawUI.WindowSize.Width
        } elseif ([Console]::WindowWidth -gt 20) {
            $conWidth = [Console]::WindowWidth
        }
    } catch { }

    $bw = [Math]::Min(68, [Math]::Max(40, $conWidth - 8))

    $renderLine = {
        param([string]$Text, [System.ConsoleColor]$Color = [System.ConsoleColor]::White)
        $maxLen = [Math]::Max(0, $bw - 2)
        if ($Text.Length -gt $maxLen) { $Text = $Text.Substring(0, $maxLen) }
        $pad = $bw - 2 - $Text.Length
        if ($pad -lt 0) { $pad = 0 }
        Write-Host "    │ " -NoNewline -ForegroundColor DarkCyan
        Write-Host $Text -NoNewline -ForegroundColor $Color
        Write-Host (" " * $pad + " │") -ForegroundColor DarkCyan
    }

    Write-Host ""
    switch ($Topic.ToLowerInvariant()) {
        "shortcuts" {
            $tTitle = "Shortcuts, Aliases & Keybindings Guide"
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            & {
                & $renderLine "1. PRIMARY ALIASES:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   aif <prompt>   Compiled managed .NET 10 helper module" ([System.ConsoleColor]::White)
                & $renderLine "   ai <prompt>    Standard PowerShell module" ([System.ConsoleColor]::White)
                & $renderLine "   ?? <prompt>    Short alias for command generation" ([System.ConsoleColor]::White)
                & $renderLine "   F2             Inline PSReadLine generation directly in prompt" ([System.ConsoleColor]::Yellow)
                & $renderLine "   ai-fix         Diagnose and fix the last failed command in session" ([System.ConsoleColor]::White)
                & $renderLine "   ai-script      Generate complex multi-step .ps1 automation scripts" ([System.ConsoleColor]::White)
                & $renderLine "   ai-chat        Interactive terminal assistant with Tab completion" ([System.ConsoleColor]::White)
                & $renderLine "   ai-agent       Autonomous Claude Code agent mode backed by Ollama" ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "2. SHORT EXECUTION FLAGS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   -x, -y         Execute command immediately without confirmation" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -c             Copy generated command directly to clipboard" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -a, -Alias     Generate using standard short PowerShell aliases (gps, gci, ?)" ([System.ConsoleColor]::Yellow)
                & $renderLine "   -Explain       Generate comprehensive educational breakdown of code" ([System.ConsoleColor]::Magenta)
                & $renderLine "   -Ask, -chat    Get educational text response instead of script" ([System.ConsoleColor]::Blue)
                & $renderLine ""
                & $renderLine "3. INTERACTIVE MENU KEYPRESSES (after generation):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   [Enter]        Execute command in current session" ([System.ConsoleColor]::Green)
                & $renderLine "   [C] / [c]      Copy command to system clipboard" ([System.ConsoleColor]::Yellow)
                & $renderLine "   [I] / [i]      Insert command into prompt line for manual editing" ([System.ConsoleColor]::Cyan)
                & $renderLine "   [S] / [s]      Toggle between short aliases and full cmdlet names (Alias/Full)" ([System.ConsoleColor]::DarkYellow)
                & $renderLine "   [X] / [x]      Explain command syntax, flags, and safety" ([System.ConsoleColor]::Magenta)
                & $renderLine "   [A] / [a]      Provide full conceptual explanation" ([System.ConsoleColor]::Blue)
                & $renderLine "   [Esc]          Cancel and return to prompt" ([System.ConsoleColor]::DarkGray)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        "models" {
            $tTitle = "Ollama Coding Models Guide"
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            & {
                & $renderLine "RECOMMENDED LOCAL CODING MODELS FOR POWERSHELL:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  • qwen2.5-coder:7b   [~4.4GB VRAM] Top choice for PowerShell 7 pipelines & CLI" ([System.ConsoleColor]::Green)
                & $renderLine "  • granite4.2:8b      [~5.0GB VRAM] Enterprise IBM model, great for sysadmin tasks" ([System.ConsoleColor]::White)
                & $renderLine "  • deepseek-coder:6.7b[~4.0GB VRAM] Fast, precise code generation" ([System.ConsoleColor]::White)
                & $renderLine "  • qwen2.5-coder:1.5b [~1.2GB VRAM] Ultra-lightweight for CPU laptops" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "MODEL MANAGEMENT COMMANDS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif models              View list of installed models & active marker" ([System.ConsoleColor]::White)
                & $renderLine "  aif model <name>        Switch active model" ([System.ConsoleColor]::White)
                & $renderLine "  ollama pull <name>      Download model (e.g. ollama pull qwen2.5-coder:7b)" ([System.ConsoleColor]::DarkGray)
                & $renderLine "  ollama list             List all models downloaded locally" ([System.ConsoleColor]::DarkGray)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        "examples" {
            $tTitle = "Practical DevOps & Admin Examples"
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            & {
                & $renderLine "FILES & DIRECTORIES:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'find all .log files larger than 50MB modified in last 2 days'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'calculate total size of C:\Temp directory in gigabytes'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'delete empty folders recursively' -Explain" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "PROCESSES & DIAGNOSTICS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'show top 5 processes by working set memory in MB'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'find process listening on port 8080'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'terminate all hung node processes' -x" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "NETWORKING & SYSTEMS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif 'test TCP connection to 8.8.8.8 on port 53'" ([System.ConsoleColor]::Green)
                & $renderLine "  aif 'display default gateway and active DNS servers'" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-fix  (auto-diagnose and fix the last error)" ([System.ConsoleColor]::Yellow)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        "workflow" {
            $tTitle = "Interactive Workflow Guide"
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            & {
                & $renderLine "1. INLINE GENERATION (Fastest method):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Type any goal in plain English directly at the terminal prompt" ([System.ConsoleColor]::White)
                & $renderLine "   • Press F2 (or Ctrl+Space) -> prompt is replaced with valid code" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "2. INTERACTIVE ACTION MENU (Safe verification):" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Run: aif 'your task description'" ([System.ConsoleColor]::White)
                & $renderLine "   • Press [Enter] to run, [C] to copy to clipboard," ([System.ConsoleColor]::White)
                & $renderLine "     [I] to insert into line for editing, [X] to explain syntax," ([System.ConsoleColor]::White)
                & $renderLine "     [A] for conceptual answer, or [Esc] to dismiss." ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "3. AUTOMATED ERROR RECOVERY:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • When any terminal command fails, immediately run: ai-fix" ([System.ConsoleColor]::Yellow)
                & $renderLine "   • AI analyzes the error stream and suggests a fix." ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "4. PRODUCTION SCRIPTS & CHAT ASSISTANT:" ([System.ConsoleColor]::Cyan)
                & $renderLine "   • Multi-step scripts: ai-script 'backup IIS logs with compression'" ([System.ConsoleColor]::White)
                & $renderLine "   • Multi-turn assistant: ai-chat (supports /help, /model, /clear)" ([System.ConsoleColor]::White)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        "config" {
            $tTitle = "Configuration Settings Guide"
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            & {
                & $renderLine "CONFIGURATION FILE:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  Location: ~/.terminal-ai/config.json" ([System.ConsoleColor]::White)
                & $renderLine "  View:     aif config   or   ai config" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "KEY SETTINGS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  • Model        Active coding model (default: qwen2.5-coder:7b)" ([System.ConsoleColor]::White)
                & $renderLine "  • OllamaUrl    Ollama server endpoint (http://localhost:11434)" ([System.ConsoleColor]::White)
                & $renderLine "  • Language     Model response language (en or uk)" ([System.ConsoleColor]::White)
                & $renderLine "  • Temperature  Generation determinism (0.2 for strict code)" ([System.ConsoleColor]::White)
                & $renderLine "  • AutoCopy     Auto-copy generated command to clipboard" ([System.ConsoleColor]::White)
                & $renderLine "  • Font         Windows Terminal font (e.g. Cascadia Code NF)" ([System.ConsoleColor]::White)
                & $renderLine "  • HotkeyChord  Inline shortcut chord (F2 or Ctrl+Space)" ([System.ConsoleColor]::White)
                & $renderLine ""
                & $renderLine "QUICK CONFIGURATION COMMANDS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif model <name>        Switch active Ollama model" ([System.ConsoleColor]::Yellow)
                & $renderLine "  aif lang en | uk        Switch model response language" ([System.ConsoleColor]::Yellow)
                & $renderLine "  ai font <name> [size]   Configure Windows Terminal font" ([System.ConsoleColor]::Yellow)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }

        default {
            # Complete help
            $tTitle = "Complete Reference & Commands Map"
            Write-Host "    ✦ Terminal AI • $tTitle" -ForegroundColor Cyan
            Write-Host ("    ╭" + ("─" * $bw) + "╮") -ForegroundColor DarkCyan
            & $renderLine ""
            & {
                & $renderLine "AVAILABLE COMMANDS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  aif, ai-fast      Fast native C# binary module (recommended)" ([System.ConsoleColor]::White)
                & $renderLine "  ai, ??            Classic PowerShell module with latency timing" ([System.ConsoleColor]::White)
                & $renderLine "  ai-fix            Diagnose and fix the last failed command in session" ([System.ConsoleColor]::White)
                & $renderLine "  ai-script         Generate production-ready multi-line .ps1 scripts" ([System.ConsoleColor]::White)
                & $renderLine "  ai-chat           Interactive terminal assistant with history" ([System.ConsoleColor]::White)
                & $renderLine "  ai-agent          Autonomous Claude Code agent mode (backed by Ollama)" ([System.ConsoleColor]::White)
                & $renderLine "  F2                Inline generation directly in PSReadLine prompt" ([System.ConsoleColor]::Yellow)
                & $renderLine ""
                & $renderLine "DETAILED TOPICS:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  ai-help shortcuts Full cheat-sheet of keybindings, flags, and aliases" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help models    VRAM requirements & coding LLM recommendations" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help examples  Practical sysadmin & automation pipeline examples" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help workflow  Workflow guide for menus, inline, and error fixing" ([System.ConsoleColor]::Green)
                & $renderLine "  ai-help config    Configuration guide (~/.terminal-ai/config.json)" ([System.ConsoleColor]::Green)
                & $renderLine ""
                & $renderLine "NATIVE POWERSHELL HELP:" ([System.ConsoleColor]::Cyan)
                & $renderLine "  Get-Help aif -Full        Full MAML manual with parameters and types" ([System.ConsoleColor]::DarkGray)
                & $renderLine "  Get-Help aif -Examples    Real-world usage examples" ([System.ConsoleColor]::DarkGray)
            }
            & $renderLine ""
            Write-Host ("    ╰" + ("─" * $bw) + "╯`n") -ForegroundColor DarkCyan
        }
    }
}


function Show-AiCodeCard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,
        [string]$Title = "",
        [string]$Model = "",
        [System.ConsoleColor]$BorderColor = [System.ConsoleColor]::DarkCyan,
        [System.ConsoleColor]$CodeColor = [System.ConsoleColor]::Green
    )

    if (-not $Title) { $Title = Get-TerminalAiText "CardTitle" }

    $conWidth = 80
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 20) {
            $conWidth = $Host.UI.RawUI.WindowSize.Width
        } elseif ([Console]::WindowWidth -gt 20) {
            $conWidth = [Console]::WindowWidth
        }
    } catch { }

    $maxAllowedInner = [Math]::Max(30, $conWidth - 8)
    $maxLineLen = $maxAllowedInner - 4

    $lines = $Code -split "\r?\n"
    $wrappedLines = @()
    foreach ($l in $lines) {
        if ($l.Length -le $maxLineLen) {
            $wrappedLines += $l
        } else {
            $rem = $l
            while ($rem.Length -gt $maxLineLen) {
                $breakIdx = -1
                $searchStart = [Math]::Max(0, $maxLineLen - 24)
                for ($i = $maxLineLen; $i -ge $searchStart; $i--) {
                    $ch = $rem[$i]
                    if ($ch -eq ' ' -or $ch -eq '|') {
                        $breakIdx = if ($ch -eq '|') { $i } else { $i + 1 }
                        break
                    }
                }
                if ($breakIdx -le 0 -or $breakIdx -gt $maxLineLen) {
                    $breakIdx = $maxLineLen
                }
                $wrappedLines += $rem.Substring(0, $breakIdx).TrimEnd()
                $rem = $rem.Substring($breakIdx).TrimStart()
            }
            if ($rem.Length -gt 0) { $wrappedLines += $rem }
        }
    }

    $maxCodeLen = 0
    foreach ($wl in $wrappedLines) {
        if ($wl.Length -gt $maxCodeLen) { $maxCodeLen = $wl.Length }
    }

    $minBoxInner = [Math]::Min(54, $maxAllowedInner)
    $boxInnerWidth = [Math]::Min($maxAllowedInner, [Math]::Max($minBoxInner, $maxCodeLen + 4))

    $headerLabel = " ✦ $Title"
    if ($Model) { $headerLabel += " • $Model" }

    Write-Host ""
    Write-Host ("    $headerLabel") -ForegroundColor Cyan
    Write-Host ("    ╭" + ("─" * $boxInnerWidth) + "╮") -ForegroundColor $BorderColor
    Write-Host ("    │" + (" " * $boxInnerWidth) + "│") -ForegroundColor $BorderColor

    foreach ($chunk in $wrappedLines) {
        $padRight = $boxInnerWidth - 4 - $chunk.Length
        if ($padRight -lt 0) { $padRight = 0 }
        Write-Host "    │  " -NoNewline -ForegroundColor $BorderColor
        Write-Host $chunk -NoNewline -ForegroundColor $CodeColor
        Write-Host ((" " * $padRight) + "  │") -ForegroundColor $BorderColor
    }

    Write-Host ("    │" + (" " * $boxInnerWidth) + "│") -ForegroundColor $BorderColor
    Write-Host ("    ╰" + ("─" * $boxInnerWidth) + "╯") -ForegroundColor $BorderColor
    Write-Host ""
}

function Show-AiActionMenu {
    param(
        [bool]$UseAliases = $false,
        [bool]$CanPreview = $false
    )

    $tEnter = Get-TerminalAiText "MenuEnter"
    $tCopy = Get-TerminalAiText "MenuCopy"
    $tInsert = Get-TerminalAiText "MenuInsert"
    $tAlias = if ($UseAliases) { Get-TerminalAiText "MenuFull" } else { Get-TerminalAiText "MenuAlias" }
    $tExplain = Get-TerminalAiText "MenuExplain"
    $tAsk = Get-TerminalAiText "MenuAsk"
    $tWhatIf = Get-TerminalAiText "MenuWhatIf"
    $tCancel = Get-TerminalAiText "MenuCancel"

    $conWidth = 80
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 20) {
            $conWidth = $Host.UI.RawUI.WindowSize.Width
        } elseif ([Console]::WindowWidth -gt 20) {
            $conWidth = [Console]::WindowWidth
        }
    } catch { }

    if ($conWidth -ge 120) {
        Write-Host "    [Enter] " -NoNewline -ForegroundColor Green
        Write-Host "$tEnter   " -NoNewline -ForegroundColor White
        Write-Host "[C] " -NoNewline -ForegroundColor Yellow
        Write-Host "$tCopy   " -NoNewline -ForegroundColor White
        Write-Host "[I] " -NoNewline -ForegroundColor Cyan
        Write-Host "$tInsert   " -NoNewline -ForegroundColor White
        Write-Host "[S] " -NoNewline -ForegroundColor DarkYellow
        Write-Host "$tAlias   " -NoNewline -ForegroundColor White
        if ($CanPreview) {
            Write-Host "[W] " -NoNewline -ForegroundColor DarkCyan
            Write-Host "$tWhatIf   " -NoNewline -ForegroundColor White
        }
        Write-Host "[X] " -NoNewline -ForegroundColor Magenta
        Write-Host "$tExplain   " -NoNewline -ForegroundColor White
        Write-Host "[A] " -NoNewline -ForegroundColor Blue
        Write-Host "$tAsk   " -NoNewline -ForegroundColor White
        Write-Host "[Esc] " -NoNewline -ForegroundColor Gray
        Write-Host "$tCancel`n" -ForegroundColor White
    } else {
        Write-Host "    [Enter] " -NoNewline -ForegroundColor Green
        Write-Host ("{0,-14} " -f $tEnter) -NoNewline -ForegroundColor White
        Write-Host "[C] " -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,-14} " -f $tCopy) -NoNewline -ForegroundColor White
        Write-Host "[I] " -NoNewline -ForegroundColor Cyan
        Write-Host $tInsert -ForegroundColor White

        Write-Host "    [S]     " -NoNewline -ForegroundColor DarkYellow
        Write-Host ("{0,-14} " -f $tAlias) -NoNewline -ForegroundColor White
        if ($CanPreview) {
            Write-Host "[W] " -NoNewline -ForegroundColor DarkCyan
            Write-Host ("{0,-14} " -f $tWhatIf) -NoNewline -ForegroundColor White
        }
        Write-Host "[X] " -NoNewline -ForegroundColor Magenta
        Write-Host ("{0,-14} " -f $tExplain) -NoNewline -ForegroundColor White
        Write-Host "[A] " -NoNewline -ForegroundColor Blue
        Write-Host ("{0,-8} " -f $tAsk) -NoNewline -ForegroundColor White
        Write-Host "[Esc] " -NoNewline -ForegroundColor Gray
        Write-Host "$tCancel`n" -ForegroundColor White
    }
}

function Clear-AiInputBuffer {
    <#
    .SYNOPSIS
        Clears accidental keypresses from the console input buffer while waiting for an API response.
    #>
    try {
        if (-not [Console]::IsInputRedirected) {
            while ([Console]::KeyAvailable) {
                [void][Console]::ReadKey($true)
            }
        }
    } catch { }

    try {
        while ($Host.UI.RawUI.KeyAvailable) {
            [void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    } catch { }
}

function Get-AiMenuKeyPress {
    <#
    .SYNOPSIS
        Reads the first valid menu keypress without delay or duplicate input in Windows Terminal ConPTY.
    #>
    [CmdletBinding()]
    param(
        [string[]]$AllowedActions = @('Execute', 'Copy', 'Insert', 'ShortAlias', 'Ask', 'Explain', 'WhatIf', 'Cancel')
    )

    while ($true) {
        $keyChar = $null
        $keyEnum = $null
        $vk = 0
        $hasCtrlOrAlt = $false

        # Prefer Console.ReadKey in Windows Terminal and ConPTY
        $readSuccess = $false
        try {
            if (-not [Console]::IsInputRedirected) {
                $keyInfo = [Console]::ReadKey($true)
                $keyEnum = $keyInfo.Key
                $keyChar = $keyInfo.KeyChar
                $vk = [int]$keyInfo.Key
                if (($keyInfo.Modifiers -band [System.ConsoleModifiers]::Control) -or ($keyInfo.Modifiers -band [System.ConsoleModifiers]::Alt)) {
                    $hasCtrlOrAlt = $true
                }
                $readSuccess = $true
            }
        } catch { }

        # Fall back to RawUI.ReadKey when input is redirected or Console.ReadKey is unavailable
        if (-not $readSuccess) {
            try {
                $rawKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $vk = $rawKey.VirtualKeyCode
                $keyChar = $rawKey.Character
                if ($rawKey.ControlKeyState -match "LeftCtrl|RightCtrl|LeftAlt|RightAlt") {
                    $hasCtrlOrAlt = $true
                }
            } catch {
                return 'Cancel'
            }
        }

        $chCode = if ($keyChar) { [int][char]$keyChar } else { 0 }

        # Ctrl+C interrupts or cancels
        if (($hasCtrlOrAlt -and $keyEnum -eq [System.ConsoleKey]::C) -or $chCode -eq 3) {
            return 'Cancel'
        }

        # Ignore modifier-only keys and empty ConPTY events
        if (($vk -eq 0 -and $chCode -eq 0) -or ($vk -in @(16, 17, 18, 19, 20, 91, 92, 93) -and $chCode -eq 0)) {
            continue
        }

        # Enter executes on the first keypress
        if ('Execute' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::Enter -or $vk -eq 13 -or $chCode -eq 13 -or $chCode -eq 10) {
                return 'Execute'
            }
        }

        # 2. Escape (Cancel)
        if ('Cancel' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::Escape -or $vk -eq 27 -or $chCode -eq 27) {
                return 'Cancel'
            }
        }

        # Ignore Ctrl or Alt combinations for letter keys
        if ($hasCtrlOrAlt) {
            continue
        }

        # C copies
        if ('Copy' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::C -or $vk -eq 67 -or $keyChar -in @('c', 'C')) {
                return 'Copy'
            }
        }

        # I inserts
        if ('Insert' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::I -or $vk -eq 73 -or $keyChar -in @('i', 'I')) {
                return 'Insert'
            }
        }

        # S toggles short aliases
        if ('ShortAlias' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::S -or $vk -eq 83 -or $keyChar -in @('s', 'S')) {
                return 'ShortAlias'
            }
        }

        # A asks for a text response
        if ('Ask' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::A -or $vk -eq 65 -or $keyChar -in @('a', 'A')) {
                return 'Ask'
            }
        }

        # X explains
        if ('Explain' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::X -or $vk -eq 88 -or $keyChar -in @('x', 'X')) {
                return 'Explain'
            }
        }

        # W requests a WhatIf preview
        if ('WhatIf' -in $AllowedActions) {
            if ($keyEnum -eq [System.ConsoleKey]::W -or $vk -eq 87 -or $keyChar -in @('w', 'W')) {
                return 'WhatIf'
            }
        }
    }
}

function Invoke-OllamaApi {
    [CmdletBinding(DefaultParameterSetName = 'Prompt')]
    param(
        [Parameter(ParameterSetName = 'Prompt', Position = 0)]
        [string]$Prompt,

        [Parameter(ParameterSetName = 'Chat', Mandatory = $true)]
        [object[]]$Messages,

        [string]$SystemPrompt = "",
        [string]$Model,
        [double]$Temperature,
        [switch]$Stream
    )

    $cfg = Get-TerminalAiConfig
    $targetModel = if ($Model) { $Model } else { $cfg.Model }
    $targetTemp = if ($PSBoundParameters.ContainsKey('Temperature')) { $Temperature } else { $cfg.Temperature }

    # Select chat or generate mode
    $isChat = ($PSCmdlet.ParameterSetName -eq 'Chat' -or ($Messages -and $Messages.Count -gt 0))

    if ($isChat) {
        $targetUrl = "$($cfg.OllamaUrl.TrimEnd('/'))/api/chat"
        $chatList = [System.Collections.Generic.List[object]]::new()

        if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
            $hasSystem = $false
            if ($Messages.Count -gt 0 -and $Messages[0] -is [hashtable] -and $Messages[0].role -eq 'system') {
                $hasSystem = $true
            }
            if (-not $hasSystem) {
                $chatList.Add(@{ role = "system"; content = $SystemPrompt })
            }
        }

        foreach ($m in $Messages) {
            $chatList.Add($m)
        }

        $payload = @{
            model      = $targetModel
            messages   = $chatList
            stream     = [bool]$Stream
            keep_alive = "1h"
            options    = @{
                temperature = $targetTemp
                num_ctx     = 4096
            }
        }

        $bodyJson = $payload | ConvertTo-Json -Depth 6

        try {
            $response = Invoke-RestMethod -Uri $targetUrl `
                -Method Post `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
                -ContentType "application/json; charset=utf-8" `
                -TimeoutSec $cfg.TimeoutSeconds `
                -ErrorAction Stop

            return $response.message.content
        }
        catch {
            $msg = $_.Exception.Message
            Write-Error " [TerminalAI] Failed to connect to Ollama at '$targetUrl'. Make sure Ollama is running ('ollama serve'). Error: $msg"
            return $null
        }
    }
    else {
        $targetUrl = "$($cfg.OllamaUrl.TrimEnd('/'))/api/generate"

        $payload = @{
            model      = $targetModel
            prompt     = $Prompt
            stream     = [bool]$Stream
            keep_alive = "1h"
            options    = @{
                temperature = $targetTemp
                num_ctx     = 2048
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
            $payload["system"] = $SystemPrompt
        }

        $bodyJson = $payload | ConvertTo-Json -Depth 6

        try {
            $response = Invoke-RestMethod -Uri $targetUrl `
                -Method Post `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
                -ContentType "application/json; charset=utf-8" `
                -TimeoutSec $cfg.TimeoutSeconds `
                -ErrorAction Stop

            return $response.response
        }
        catch {
            $msg = $_.Exception.Message
            $errPrefix = "Failed to connect to Ollama at '$targetUrl'. Make sure Ollama is running ('ollama serve'). Error:"
            Write-Error " [TerminalAI] $errPrefix $msg"
            return $null
        }
    }
}

function Get-TerminalAiModels {
    [CmdletBinding()]
    param()

    $cfg = Get-TerminalAiConfig
    $url = "$($cfg.OllamaUrl.TrimEnd('/'))/api/tags"

    try {
        $res = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 5 -ErrorAction Stop
        return $res.models
    }
    catch {
        $errPrefix = "Failed to retrieve models list from Ollama ($url):"
        Write-Error " [TerminalAI] $errPrefix $($_.Exception.Message)"
        return @()
    }
}

function Show-TerminalAiModels {
    [CmdletBinding()]
    param()

    $models = Get-TerminalAiModels
    $cfg = Get-TerminalAiConfig
    $isUk = ($cfg.Language -in @("uk", "ua"))

    if ($models.Count -eq 0) {
        $noModelsMsg = " [TerminalAI] No models found or Ollama is not running."
        Write-Host $noModelsMsg -ForegroundColor Yellow
        return
    }

    $title = "Installed Ollama models (active: $($cfg.Model)):"
    $colCurrent = "Active"
    $colName = "Name"
    $colSize = "Size (GB)"
    $colUpdated = "Updated"

    Write-Host "`n  $title" -ForegroundColor Cyan
    $models | Select-Object @{Name=$colCurrent; Expression={ if ($_.name -eq $cfg.Model) { "--> *" } else { "   " } }},
                            @{Name=$colName; Expression={$_.name}},
                            @{Name=$colSize; Expression={[Math]::Round($_.size / 1GB, 2)}},
                            @{Name=$colUpdated; Expression={$_.modified_at}} | Format-Table -AutoSize
}

# --- MAIN COMMANDS ---

function Show-AiAnswer {
    param(
        [string]$Question,
        [string]$Model
    )

    $cfg = Get-TerminalAiConfig
    $activeModel = if ($Model) { $Model } else { $cfg.Model }
    $langInstruction = if ($cfg.Language -in @("uk", "ua")) { "Respond strictly in Ukrainian language." } else { "Respond in English." }

    $statusMsg = "$(Get-TerminalAiText 'Answering') $activeModel..."
    Write-Host "`n  ✦ $statusMsg" -ForegroundColor Cyan

    $askSystemPrompt = @"
You are Terminal AI, an expert engineering assistant built for PowerShell and Windows Terminal.
Current Environment: PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) on Windows.
Current AI Extension Settings:
- Active Model: $($cfg.Model)
- Autocomplete Hotkey: $($cfg.HotkeyChord) (replaces line buffer in PSReadLine)
- Ollama URL: $($cfg.OllamaUrl)
- Available cmdlets: Get-TerminalAiConfig, Set-TerminalAiConfig, Show-TerminalAiModels, Show-TerminalAiFonts, Set-TerminalAiFont, Set-TerminalAiLanguage, ai, ai-fix, ai-script.
$langInstruction
Provide a concise, direct, helpful explanation to the user's question.
"@

    $answer = Invoke-OllamaApi -Prompt $Question -SystemPrompt $askSystemPrompt -Model $activeModel -Temperature 0.3
    if ($answer) {
        $cardTitle = Get-TerminalAiText "CardTitleAnswer"
        Write-Host ""
        Write-Host "    ✦ $cardTitle • $activeModel" -ForegroundColor Cyan
        Write-Host ("    " + ("─" * 66)) -ForegroundColor DarkCyan
        foreach ($line in ($answer -split "`r?`n")) {
            Write-Host "    $line" -ForegroundColor White
        }
        Write-Host ("    " + ("─" * 66)) -ForegroundColor DarkCyan
        Write-Host ""
    }
}

function Get-AiSystemPrompt {
    param([bool]$UseAliases = $false)

    $aliasGuide = if ($UseAliases) {
@"
3. Standard Cmdlet Aliases:
   - Use standard short aliases: Get-Process->gps, Where-Object->?, ForEach-Object->%, Select-Object->select, Sort-Object->sort, Measure-Object->measure, Get-ChildItem->gci, Get-Content->gc, Set-Content->sc, Select-String->sls, Get-Service->gsv, Stop-Process->kill, Get-Help->help.
   - NEVER invent aliases for specialized cmdlets: Get-NetTCPConnection, Test-NetConnection, Get-CimInstance, Get-ItemProperty have NO aliases and MUST be written in full.
"@
    } else {
@"
3. Cmdlet Integrity:
   - NEVER hallucinate or invent fake cmdlets.
   - Specialized cmdlets like Get-NetTCPConnection, Test-NetConnection, Get-CimInstance, Get-ItemProperty MUST be written in full.
"@
    }

    return @"
You are an elite PowerShell 7 and Windows Systems engineer.
Target Environment: PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) on Windows.
Goal: Translate the user's natural language request into a single, efficient, idiomatic, robust PowerShell command or pipeline.

Rules:
1. Output ONLY the raw executable PowerShell code without markdown, backticks, or explanations.
2. Robustness & Safety: Never write commands that fail or throw errors when target objects are not present:
   - To find processes listening on ports or active connections, ALWAYS use safe pipeline filtering:
     Get-NetTCPConnection -LocalPort <Port> -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Get-Process -Id `$_.OwningProcess -ErrorAction SilentlyContinue }
     (or with aliases: Get-NetTCPConnection -LocalPort <Port> -State Listen -ea 0 | % { gps -Id `$_.OwningProcess -ea 0 })
   - NEVER write 'Get-Process -Id (Get-NetTCPConnection ...).OwningProcess' because if no process listens on that port, -Id receives null and crashes with 'Cannot bind argument to parameter Id because it is null'!
$aliasGuide
4. Error Handling: Always use -ErrorAction SilentlyContinue (-ea 0) when inspecting dynamic resources like network ports, services, or files that might not exist.
5. If the user asks about the active model, settings, or configuration, return: Get-TerminalAiConfig
6. If the user asks to list installed models, return: Show-TerminalAiModels
"@
}

# --- P0: DETERMINISTIC AST ANALYZER AND RISK ASSESSMENT ---

function Test-AiCommandAst {
    <#
    .SYNOPSIS
        Deterministic PowerShell command AST analyzer for the P0 security phase.
    .DESCRIPTION
        Recursively analyzes PowerShell code without executing it. Finds CommandAst nodes,
        identifies cmdlets, functions, aliases, and external binaries; validates parameters;
        detects dynamic invocation and splatting; extracts targets; and calculates risk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        return [PSCustomObject]@{
            IsValid                  = $false
            ParseErrors              = $parseErrors
            Commands                 = @()
            OverallCategory          = "DynamicOrUnknown"
            OverallRisk              = "High"
            RequiresConfirmation     = $true
            CanPreview               = $false
            PreviewUnavailableReason = "Command syntax error: $($parseErrors[0].Message)"
            Targets                  = @("Unknown target")
            HasDynamicInvocation     = $false
            HasSplatting             = $false
            HasDynamicTarget         = $false
        }
    }

    # Find CommandAst nodes recursively
    $commandAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)

    # Find dynamic invocation through & or Invoke-Expression
    $dynamicInvocations = $ast.FindAll({
        $node = $args[0]
        ($node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq 'Ampersand') -or
        ($node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @('Invoke-Expression', 'iex')) -or
        ($node -is [System.Management.Automation.Language.CommandAst] -and $node.CommandElements.Count -gt 0 -and $node.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst])
    }, $true)
    $hasDynamicInvocation = ($dynamicInvocations.Count -gt 0)

    # Find splatting
    $splattedVars = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and $args[0].Splatted
    }, $true)
    $hasSplatting = ($splattedVars.Count -gt 0)

    $analyzedCommands = [System.Collections.Generic.List[object]]::new()
    $allTargets = [System.Collections.Generic.List[string]]::new()
    $hasDynamicTarget = $false

    foreach ($cAst in $commandAsts) {
        $rawName = $cAst.GetCommandName()
        $originalName = if ($rawName) { $rawName } else { $cAst.CommandElements[0].Extent.Text }

        $resolvedTarget = $null
        $cmdInfo = $null
        $commandType = "Unknown"
        $category = "DynamicOrUnknown"
        $risk = "Medium"
        $supportsWhatIf = $false
        $invalidParams = [System.Collections.Generic.List[string]]::new()
        $paramsFound = [System.Collections.Generic.List[string]]::new()
        $cmdTargets = [System.Collections.Generic.List[string]]::new()

        if ([string]::IsNullOrWhiteSpace($rawName)) {
            $commandType = "DynamicInvocation"
            $category = "DynamicOrUnknown"
            $risk = "High"
            $hasDynamicInvocation = $true
        } else {
            # Resolve aliases
            $alias = Get-Alias -Name $rawName -ErrorAction Ignore
            if ($alias) {
                $commandType = "Alias"
                $resolvedTarget = $alias.Definition
                $effectiveName = $resolvedTarget
                $cmdInfo = Get-Command -Name $resolvedTarget -ErrorAction Ignore
            } else {
                $effectiveName = $rawName
                $cmdInfo = Get-Command -Name $rawName -ErrorAction Ignore
            }

            if ($cmdInfo) {
                if ($cmdInfo.CommandType -in @('Cmdlet', 'Function', 'Filter', 'Script')) {
                    if ($commandType -ne "Alias") { $commandType = $cmdInfo.CommandType.ToString() }
                    $resolvedTarget = $cmdInfo.Name

                    # Check WhatIf support
                    if ($cmdInfo.Parameters.ContainsKey('WhatIf')) {
                        $supportsWhatIf = $true
                    } elseif ($cmdInfo.ImplementingType) {
                        try {
                            $cmdAttr = [System.Management.Automation.CmdletAttribute][Attribute]::GetCustomAttribute(
                                $cmdInfo.ImplementingType, [System.Management.Automation.CmdletAttribute]
                            )
                            if ($cmdAttr -and $cmdAttr.SupportsShouldProcess) {
                                $supportsWhatIf = $true
                            }
                        } catch { }
                    }
                } elseif ($cmdInfo.CommandType -eq 'Application') {
                    $commandType = "ExternalProgram"
                    $resolvedTarget = $cmdInfo.Source
                    $category = "ExternalProgram"
                    $risk = "Medium"
                    $supportsWhatIf = $false
                }
            } else {
                $commandType = "Unknown"
                $category = "DynamicOrUnknown"
                $risk = "High"
            }
        }

        # Analyze parameters
        $paramAsts = $cAst.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandParameterAst] }, $false)
        foreach ($p in $paramAsts) {
            $pName = $p.ParameterName
            $paramsFound.Add($pName)
            if ($cmdInfo -and $cmdInfo.Parameters) {
                $commonParams = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm')
                $known = $cmdInfo.Parameters.ContainsKey($pName) -or ($commonParams -contains $pName)
                if (-not $known) {
                    $matchedPrefix = $cmdInfo.Parameters.Keys | Where-Object { $_.StartsWith($pName, [System.StringComparison]::OrdinalIgnoreCase) }
                    if (-not $matchedPrefix) {
                        $matchedPrefix = $commonParams | Where-Object { $_.StartsWith($pName, [System.StringComparison]::OrdinalIgnoreCase) }
                    }
                    if ($matchedPrefix) { $known = $true }
                }
                if (-not $known) {
                    $invalidParams.Add($pName)
                }
            }
        }

        # Extract arguments and targets
        for ($i = 1; $i -lt $cAst.CommandElements.Count; $i++) {
            $elem = $cAst.CommandElements[$i]
            if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                continue
            }
            if ($elem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $val = $elem.Value
                if (-not [string]::IsNullOrWhiteSpace($val) -and $val -notmatch '^-') {
                    $cmdTargets.Add($val)
                    if (-not $allTargets.Contains($val)) { $allTargets.Add($val) }
                }
            } elseif ($elem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                $val = $elem.Extent.Text.Trim('"', "'")
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $cmdTargets.Add($val)
                    if (-not $allTargets.Contains($val)) { $allTargets.Add($val) }
                }
            } elseif ($elem -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $cmdTargets.Add("Unknown target")
                $hasDynamicTarget = $true
                if (-not $allTargets.Contains("Unknown target")) { $allTargets.Add("Unknown target") }
            } elseif ($elem -is [System.Management.Automation.Language.SubExpressionAst] -or $elem -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $cmdTargets.Add("Unknown target")
                $hasDynamicTarget = $true
                if (-not $allTargets.Contains("Unknown target")) { $allTargets.Add("Unknown target") }
            }
        }

        # Classify category and risk for cmdlets, functions, and unknown commands
        $eff = if ($resolvedTarget) { $resolvedTarget } else { $originalName }

        if ($commandType -eq "ExternalProgram") {
            $category = "ExternalProgram"
            if ($eff -match '^(?:rm|del|erase|format|fdisk|dd|diskpart|mkfs)$') {
                $risk = "High"
                $category = "Deletion"
            } else {
                $risk = "Medium"
            }
        } elseif ($commandType -eq "Unknown") {
            $category = "DynamicOrUnknown"
            $risk = "High"
        } else {
            # Analyze command verbs and names
            if ($eff -match '^(?:Remove-|Clear-|Reset-)') {
                $category = "Deletion"
                $risk = "High"
            } elseif ($eff -match '^(?:Stop-Process|kill|Stop-Service|Restart-Service|Suspend-Service|Set-Service)') {
                $category = "ServiceOrProcess"
                $risk = "High"
            } elseif ($eff -match '^(?:Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|Clear-ItemProperty)' -or
                      ($eff -match '^(?:Get-ItemProperty|New-Item|Remove-Item|Set-Item)' -and ($Command -match '(?i)\b(?:HKCU:|HKLM:|HKCR:|HKU:|HKCC:|Registry::)'))) {
                $category = "Registry"
                $risk = "High"
            } elseif ($eff -match '(?i)(?:-Disk\b|-Partition\b|-Volume\b|Format-Volume|Initialize-Disk|Clear-Disk)') {
                $category = "DiskOrPartition"
                $risk = "Critical"
            } elseif ($eff -match '(?i)^(?:Set-Net|New-Net|Remove-Net|Disable-Net|Enable-Net|Rename-Net)') {
                $category = "NetworkChange"
                $risk = "High"
            } elseif ($eff -match '(?i)^(?:Set-|New-|Add-|Register-|Unregister-|Install-|Uninstall-|Enable-|Disable-|Grant-|Revoke-)') {
                $category = "SystemChange"
                $risk = "Medium"
            } elseif ($eff -match '(?i)^(?:Get-|Select-|Where-|ForEach-|Measure-|Sort-|Out-|Format-|Export-|Test-|Show-|Find-|Read-|Compare-|Group-)') {
                $category = "ReadOnly"
                $risk = "Low"
            } else {
                $category = "DynamicOrUnknown"
                $risk = "Medium"
            }
        }

        if ($invalidParams.Count -gt 0 -and $risk -eq "Low") {
            $risk = "Medium"
        }

        $analyzedCommands.Add([PSCustomObject]@{
            OriginalName      = $originalName
            CommandName       = $eff
            ResolvedTarget    = $resolvedTarget
            CommandType       = $commandType
            Category          = $category
            Risk              = $risk
            SupportsWhatIf    = $supportsWhatIf
            Parameters        = @($paramsFound)
            InvalidParameters = @($invalidParams)
            Targets           = @($cmdTargets)
        })
    }

    $categoryOrder = @("DiskOrPartition", "Deletion", "Registry", "ServiceOrProcess", "NetworkChange", "DynamicOrUnknown", "ExternalProgram", "SystemChange", "ReadOnly")
    $overallCat = "ReadOnly"
    foreach ($cat in $categoryOrder) {
        if ($analyzedCommands | Where-Object { $_.Category -eq $cat }) {
            $overallCat = $cat
            break
        }
    }

    $riskOrder = @("Critical", "High", "Medium", "Low")
    $overallRisk = "Low"
    foreach ($r in $riskOrder) {
        if ($analyzedCommands | Where-Object { $_.Risk -eq $r }) {
            $overallRisk = $r
            break
        }
    }
    if ($hasDynamicInvocation -and $overallRisk -in @("Low", "Medium")) {
        $overallRisk = "High"
        $overallCat = "DynamicOrUnknown"
    }

    $requiresConfirm = ($overallRisk -in @("High", "Critical", "Unknown"))
    if ($hasDynamicInvocation) { $requiresConfirm = $true }

    $allWhatIf = $true
    foreach ($c in $analyzedCommands) {
        if ($c.Category -ne "ReadOnly" -and -not $c.SupportsWhatIf) {
            $allWhatIf = $false
            break
        }
    }

    $canPreview = $allWhatIf
    $previewReason = if ($canPreview) {
        $null
    } else {
        $cfg = try { Get-TerminalAiConfig } catch { $null }
        $isUk = ($cfg -and $cfg.Language -in @("uk", "ua"))
        if ($analyzedCommands | Where-Object { $_.CommandType -eq "ExternalProgram" }) {
            "Safe preview (-WhatIf) is unavailable for external binary programs"
        } else {
            "Safe preview (-WhatIf) is not supported by one or more commands"
        }
    }

    if ($allTargets.Count -eq 0) {
        $allTargets.Add("Unknown target")
    }

    return [PSCustomObject]@{
        IsValid                  = $true
        ParseErrors              = @()
        Commands                 = @($analyzedCommands)
        OverallCategory          = $overallCat
        OverallRisk              = $overallRisk
        RequiresConfirmation     = $requiresConfirm
        CanPreview               = $canPreview
        PreviewUnavailableReason = $previewReason
        Targets                  = @($allTargets)
        HasDynamicInvocation     = $hasDynamicInvocation
        HasSplatting             = $hasSplatting
        HasDynamicTarget         = $hasDynamicTarget
    }
}

function Invoke-AiExecutionGate {
    <#
    .SYNOPSIS
        Single security entry point for executing PowerShell commands in TerminalAI.
    .DESCRIPTION
        Analyzes a command through Test-AiCommandAst, blocks syntax errors, displays security
        details for risky or unresolved operations, requires explicit confirmation for dangerous
        commands, and permits automatic execution only for verified low-risk commands.
    .PARAMETER Command
        PowerShell command to validate and execute.
    .PARAMETER AutoConfirm
        Automatically confirms low-risk operations. High, critical, and unknown operations still require interactive confirmation.
    .PARAMETER ReturnOutput
        Returns command output instead of sending it to Out-Default.
    .PARAMETER ConfirmInput
        Optional confirmation response used by tests and automation.
    .PARAMETER PassThru
        Returns a detailed execution report with analysis results and status.
    .PARAMETER SkipAstAnalysis
        Skips AST analysis for exceptional internal calls only.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command,

        [Parameter()]
        [switch]$AutoConfirm,

        [Parameter()]
        [switch]$ReturnOutput,

        [Parameter()]
        [string]$ConfirmInput,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [switch]$Preview,

        [Parameter()]
        [switch]$SkipAstAnalysis
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        if ($PassThru) {
            return [PSCustomObject]@{
                Executed = $false
                Status   = "EmptyCommand"
                Command  = $Command
                Analysis = $null
                Output   = $null
            }
        }
        return $null
    }

    $analysis = $null
    if (-not $SkipAstAnalysis) {
        $analysis = Test-AiCommandAst -Command $Command

        # Block commands with parser errors
        if (-not $analysis.IsValid -or ($analysis.ParseErrors -and $analysis.ParseErrors.Count -gt 0)) {
            Write-Host ""
            Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
            Write-Host "    │          ✖  TERMINAL AI SECURITY GATE: SYNTAX ERROR         │" -ForegroundColor Red
            Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
            Write-Host "    Command execution BLOCKED due to syntax errors:" -ForegroundColor DarkYellow
            foreach ($err in $analysis.ParseErrors) {
                $lineNum = if ($err.Extent) { $err.Extent.StartLineNumber } else { 1 }
                $colNum = if ($err.Extent) { $err.Extent.StartColumnNumber } else { 1 }
                Write-Host "      • Line $lineNum, Col $($colNum): $($err.Message)" -ForegroundColor Red
            }
            Write-Host ""

            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $false
                    Status   = "SyntaxError"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $null
                }
            }
            return $null
        }
    }

    # WhatIf preview mode
    $isWhatIf = $Preview -or ($PSBoundParameters.ContainsKey('WhatIf') -and $PSBoundParameters['WhatIf'])
    if ($isWhatIf) {
        if (-not $analysis.CanPreview) {
            $reason = if ($analysis.PreviewUnavailableReason) { $analysis.PreviewUnavailableReason } else { "WhatIf preview is not supported for this command." }
            Write-Host ""
            Write-Host "    ⚠ [Preview Unavailable] $reason" -ForegroundColor DarkYellow
            Write-Host "      Command contains external binaries or operations without SupportsShouldProcess." -ForegroundColor DarkGray
            Write-Host ""
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $false
                    Status   = "PreviewUnavailable"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $null
                }
            }
            return $null
        }

        Write-Host "    🔍 [WhatIf Preview] Running command in safe simulation mode..." -ForegroundColor Cyan
        try {
            $sb = [ScriptBlock]::Create($Command)
            if ($ReturnOutput) {
                $output = & {
                    $WhatIfPreference = $true
                    . $sb
                } 2>&1
                if ($PassThru) {
                    return [PSCustomObject]@{
                        Executed = $true
                        Status   = "Previewed"
                        Command  = $Command
                        Analysis = $analysis
                        Output   = $output
                    }
                }
                return $output
            } else {
                & {
                    $WhatIfPreference = $true
                    . $sb
                } | Out-Default
                if ($PassThru) {
                    return [PSCustomObject]@{
                        Executed = $true
                        Status   = "Previewed"
                        Command  = $Command
                        Analysis = $analysis
                        Output   = $null
                    }
                }
            }
            return $null
        } catch {
            Write-Error $_
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $false
                    Status   = "ExecutionError"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $_
                }
            }
            if ($ReturnOutput) { return $_ }
            return $null
        }
    }

    # Risk check
    $isDangerous = $false
    if ($analysis) {
        $isDangerous = $analysis.RequiresConfirmation -or ($analysis.OverallRisk -in @("High", "Critical", "Unknown"))
    }

    # Determine whether confirmation is required
    $needsPrompt = $true
    if (-not $isDangerous -and $AutoConfirm) {
        # Execute low-risk commands directly with AutoConfirm
        $needsPrompt = $false
    }

    if ($needsPrompt) {
        # Render the security card
        $risk = if ($analysis) { $analysis.OverallRisk } else { "Unknown" }
        $category = if ($analysis) { $analysis.OverallCategory } else { "Unknown" }
        $targets = if ($analysis -and $analysis.Targets) { $analysis.Targets } else { @() }

        $headerColor = switch ($risk) {
            'Critical' { 'Red' }
            'High'     { 'Red' }
            'Medium'   { 'Yellow' }
            default    { 'Cyan' }
        }

        Write-Host ""
        Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor $headerColor
        Write-Host "    │               ⚠  TERMINAL AI SECURITY GATE  ⚠               │" -ForegroundColor $headerColor
        Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor $headerColor
        Write-Host "    Command:  " -NoNewline -ForegroundColor White
        Write-Host $Command -ForegroundColor Cyan
        Write-Host "    Category: " -NoNewline -ForegroundColor White
        Write-Host $category -ForegroundColor Yellow
        Write-Host "    Risk:     " -NoNewline -ForegroundColor White
        Write-Host $risk -ForegroundColor $headerColor

        if ($targets.Count -gt 0) {
            Write-Host "    Targets:  " -NoNewline -ForegroundColor White
            Write-Host ($targets -join ", ") -ForegroundColor Magenta
        }

        # Collect risk reasons
        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($analysis) {
            if ($analysis.HasDynamicInvocation) {
                $reasons.Add("Dynamic command invocation detected (& `$var, Invoke-Expression, iex)")
            }
            if ($analysis.HasDynamicTarget) {
                $reasons.Add("Dynamic or unresolved target (variable/expression in arguments)")
            }
            if ($analysis.HasSplatting) {
                $reasons.Add("Parameter splatting detected (@params)")
            }
            foreach ($cmd in $analysis.Commands) {
                if ($cmd.InvalidParameters -and $cmd.InvalidParameters.Count -gt 0) {
                    $reasons.Add("Unknown parameter(s) for $($cmd.CommandName): $($cmd.InvalidParameters -join ', ')")
                }
                if ($cmd.Category -in @("Deletion", "DiskOrPartition", "Registry", "NetworkChange", "ServiceOrProcess")) {
                    $reasons.Add("Operation category '$($cmd.Category)' modifies system state ($($cmd.CommandName))")
                }
            }
        }
        if ($reasons.Count -gt 0) {
            Write-Host "    Reasons:" -ForegroundColor White
            foreach ($r in $reasons) {
                Write-Host "      • $r" -ForegroundColor DarkYellow
            }
        }

        # Request confirmation
        $promptDefault = if ($risk -in @("High", "Critical", "Unknown")) { "y/N" } else { "Y/n" }
        $promptText = "    Execute this command? [$promptDefault]: "

        $confirmed = $false
        if ($PSBoundParameters.ContainsKey('ConfirmInput')) {
            $response = $ConfirmInput
        } else {
            try {
                $isInteractive = [Environment]::UserInteractive
                if ([Console]::IsInputRedirected) { $isInteractive = $false }
            } catch {
                $isInteractive = $true
            }

            if (-not $isInteractive) {
                Write-Host "    ✖ Non-interactive host detected. Unconfirmed command blocked." -ForegroundColor Red
                if ($PassThru) {
                    return [PSCustomObject]@{
                        Executed = $false
                        Status   = "BlockedNonInteractive"
                        Command  = $Command
                        Analysis = $analysis
                        Output   = $null
                    }
                }
                return $null
            }

            $response = Read-Host -Prompt $promptText
        }

        if ($risk -in @("High", "Critical", "Unknown")) {
            if ($response -match '^(y|yes)$') {
                $confirmed = $true
            }
        } else {
            if ([string]::IsNullOrWhiteSpace($response) -or $response -match '^(y|yes)$') {
                $confirmed = $true
            }
        }

        if (-not $confirmed) {
            Write-Host "    ✖ Execution canceled by user." -ForegroundColor DarkGray
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $false
                    Status   = "Denied"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $null
                }
            }
            return $null
        }
    }

    # Execute the command
    try {
        $sb = [ScriptBlock]::Create($Command)
        if ($ReturnOutput) {
            $output = . $sb 2>&1
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $true
                    Status   = "Executed"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $output
                }
            }
            return $output
        } else {
            . $sb | Out-Default
            if ($PassThru) {
                return [PSCustomObject]@{
                    Executed = $true
                    Status   = "Executed"
                    Command  = $Command
                    Analysis = $analysis
                    Output   = $null
                }
            }
        }
    } catch {
        Write-Error $_
        if ($PassThru) {
            return [PSCustomObject]@{
                Executed = $false
                Status   = "ExecutionError"
                Command  = $Command
                Analysis = $analysis
                Output   = $_
            }
        }
        if ($ReturnOutput) {
            return $_
        }
    }
}

function Invoke-AiCommand {
    <#
    .SYNOPSIS
        Generates a PowerShell command from a natural-language prompt through local Ollama.
    .DESCRIPTION
        Generates a PowerShell command and offers actions to execute, copy, insert, explain, or cancel it.
        Supports help subcommands: ai help, ai help shortcuts, ai help models,
        ai help examples, ai help workflow, ai help config, ai status, ai models.
    .PARAMETER Prompt
        Natural-language prompt or subcommand such as help, status, models, model, lang, or config.
    .PARAMETER Execute
        Executes the generated command immediately without the interactive menu.
    .PARAMETER Copy
        Copies the generated command to the system clipboard.
    .PARAMETER Alias
        Uses standard short PowerShell aliases instead of full cmdlet names.
    .PARAMETER Explain
        Generates a structured explanation of syntax, parameters, and safety.
    .PARAMETER Ask
        Returns a direct text response instead of code.
    .PARAMETER Model
        Overrides the active Ollama model for this invocation.
    .EXAMPLE
        ai find all files larger than 100MB in the current directory
    .EXAMPLE
        ai "find the process listening on port 8080" -a
    .EXAMPLE
        ai help shortcuts
    .EXAMPLE
        ai "find the process listening on port 8080" -Explain
    .EXAMPLE
        ai "check DNS resolution for google.com" -x
    .EXAMPLE
        ?? count the lines in all ps1 files
    #>
    [CmdletBinding()]
    [Alias("ai", "??")]
    param(
        [Parameter(Position = 0, Mandatory = $false, ValueFromRemainingArguments = $true)]
        [string[]]$Prompt,

        [Alias("x", "y")]
        [switch]$Execute,

        [Alias("c")]
        [switch]$Copy,

        [Alias("a", "Short", "UseAliases")]
        [switch]$Alias,

        [switch]$Explain,

        [Alias("chat", "question")]
        [switch]$Ask,

        [Alias("w", "WhatIf")]
        [switch]$Preview,

        [string]$Model
    )

    $cfg = Get-TerminalAiConfig
    $fullPrompt = if ($Prompt) { ($Prompt -join " ").Trim() } else { "" }
    $isUk = ($cfg.Language -in @("uk", "ua"))

    if ([string]::IsNullOrWhiteSpace($fullPrompt)) {
        Write-Host ""
        & {
            Write-Host "    ✦ Terminal AI • Quick Reference & Shortcuts" -ForegroundColor Cyan
            Write-Host "    ╭────────────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Primary Commands & Aliases:                                          │" -ForegroundColor Cyan
            Write-Host "    │     aif <prompt>  or  ai-fast <prompt>    (managed .NET 10 helper)     │" -ForegroundColor White
            Write-Host "    │     ?? <prompt>   or  ai <prompt>         (standard PowerShell module) │" -ForegroundColor White
            Write-Host "    │     F2                                    (inline generation in term)  │" -ForegroundColor Yellow
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Short Commands & Subcommands:                                        │" -ForegroundColor Cyan
            Write-Host "    │     ai help [top] or  aif help [topic]    (learning guide & cheatsheet)│" -ForegroundColor Green
            Write-Host "    │     ai status     or  aif status          (system information & model) │" -ForegroundColor Green
            Write-Host "    │     ai alias [on] or  aif alias [on|off]  (short command aliases mode) │" -ForegroundColor Green
            Write-Host "    │     ai models     |  aif -m               (list installed models)      │" -ForegroundColor Green
            Write-Host "    │     ai model <name>                       (switch active Ollama model) │" -ForegroundColor Green
            Write-Host "    │     ai lang en | uk                  (switch model response language) │" -ForegroundColor Green
            Write-Host "    │     ai config     |  aif -c               (view configuration JSON)    │" -ForegroundColor Green
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    │   Short Flags & Execution:                                             │" -ForegroundColor Cyan
            Write-Host "    │     ai `"cmd`" -x   or  aif `"cmd`" -x        (execute immediately)        │" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -c   or  aif `"cmd`" -c        (copy to clipboard)          │" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -a   or  aif `"cmd`" -a        (short aliases: gps, gci, ?) │" -ForegroundColor Yellow
            Write-Host "    │     ai `"cmd`" -Explain                   (generate with explanation)  │" -ForegroundColor Magenta
            Write-Host "    │     ai `"cmd`" -Ask                       (direct educational answer)  │" -ForegroundColor Blue
            Write-Host "    │                                                                        │" -ForegroundColor DarkCyan
            Write-Host "    ╰────────────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        }

        Write-Host ""
        return
    }

    $activeModel = if ($Model) { $Model } else { $cfg.Model }

    # Help topics
    if ($fullPrompt -match '^(?:help)(?:\s+(all|shortcuts|models|examples|workflow|config))?\s*$') {
        $topic = if ($Matches[1]) { $Matches[1].Trim().ToLowerInvariant() } else { "all" }
        Show-TerminalAiHelp -Topic $topic
        return
    }

    if ($fullPrompt -eq "shortcuts") {
        Show-TerminalAiHelp -Topic "shortcuts"
        return
    }

    if ($fullPrompt -eq "examples") {
        Show-TerminalAiHelp -Topic "examples"
        return
    }

    if ($fullPrompt -eq "workflow") {
        Show-TerminalAiHelp -Topic "workflow"
        return
    }

    # Font listing and changes
    if ($fullPrompt -in @("fonts", "font", "--fonts", "--font", "-f")) {
        Show-TerminalAiFonts
        return
    }

    if ($fullPrompt -match '^(?:set-font|use-font|font)\s+(.+)$') {
        $fontArg = $Matches[1].Trim().Trim('"').Trim("'")
        $fontSize = 0
        if ($fontArg -match '^(?<font>.+?)\s+(?<size>\d{1,2})$') {
            $fontName = $Matches['font'].Trim().Trim('"').Trim("'")
            $fontSize = [int]$Matches['size']
            Set-TerminalAiFont -Font $fontName -Size $fontSize
        } else {
            Set-TerminalAiFont -Font $fontArg
        }
        return
    }

    # Language status and switching
    if ($fullPrompt -in @("lang", "language", "--lang", "-l")) {
        Write-Host ""
        & {
            Write-Host "    ✦ Current model response language: en (English)" -ForegroundColor Cyan
            Write-Host "    💡 Switch model response language:  ai lang uk  |  ai lang en" -ForegroundColor DarkGray
            Write-Host "    💡 Set permanent:    ai lang permanent uk  |  ai lang permanent en`n" -ForegroundColor DarkGray
        }
        return
    }

    # Permanent language selection
    if ($fullPrompt -match '^(?:set-lang|lang|language)\s+(?:permanent|save|default|--permanent|-p)\s+(uk|ua|en)$' -or
        $fullPrompt -match '^(?:set-lang|lang|language)\s+(uk|ua|en)\s+(?:permanent|save|default|--permanent|-p)$' -or
        $fullPrompt -match '^(?:lang-permanent|default-lang|set-default-lang)\s+(uk|ua|en)$') {
        $newLang = $Matches[1].ToLower()
        Set-TerminalAiLanguage -Language $newLang -Permanent
        return
    }

    if ($fullPrompt -match '^(?:set-lang|lang|language)\s+(uk|ua|en)$') {
        $newLang = $Matches[1].ToLower()
        Set-TerminalAiLanguage -Language $newLang -Permanent
        return
    }

    # System, model, and font information
    if ($fullPrompt -match '^(?:which|what)\s+model|current\s+model|status|info|which\s+font') {
        $fontInfo = Get-TerminalAiFonts
        $activeFontDisplay = if ($fontInfo.ActiveFont) { $fontInfo.ActiveFont } else { "Default" }

        $title = "System Information"
        $lblModel = "Active Model:"
        $lblFont = "Terminal Font:"
        $lblServer = "Local Server:"
        $lblHotkey = "Quick Inline:"
        $lblLang = "Model Response Language:"
        $hintModel = "Change model:  ai model <name>"
        $hintFont = "Change font:   ai font <name>"
        $hintLang = "Change lang:   ai lang en | uk"

        Write-Host ""
        Write-Host "    ✦ Terminal AI • $title" -ForegroundColor Cyan
        Write-Host "    ╭──────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
        Write-Host "    │                                                                  │" -ForegroundColor DarkCyan

        $renderRow = {
            param([string]$Label, [string]$Value, [System.ConsoleColor]$ValueColor)
            if ($Label.Length -gt 22) { $Label = $Label.Substring(0, 22) }
            if ($Value.Length -gt 38) { $Value = $Value.Substring(0, 35) + "..." }
            Write-Host "    │   " -NoNewline -ForegroundColor DarkCyan
            Write-Host ("{0,-22}" -f $Label) -NoNewline -ForegroundColor DarkCyan
            Write-Host ("{0,-38}" -f $Value) -NoNewline -ForegroundColor $ValueColor
            Write-Host "   │" -ForegroundColor DarkCyan
        }

        & $renderRow $lblModel $cfg.Model ([System.ConsoleColor]::Green)
        & $renderRow $lblFont $activeFontDisplay ([System.ConsoleColor]::Cyan)
        & $renderRow $lblServer $cfg.OllamaUrl ([System.ConsoleColor]::White)
        $hkText = "$($cfg.HotkeyChord) / F2 (inline)"
        & $renderRow $lblHotkey $hkText ([System.ConsoleColor]::Yellow)
        $langDisplay = if ($cfg.Language -in @("uk", "ua")) { "uk (Ukrainian)" } else { "en (English)" }
        & $renderRow $lblLang $langDisplay ([System.ConsoleColor]::White)
        $lblAlias = "Command Aliases:"
        $aliasDisplay = if ($cfg.UseAliases) {
            "Enabled (gps, gci, ?)"
        } else {
            "Disabled (full cmdlets)"
        }
        $aliasColor = if ($cfg.UseAliases) { [System.ConsoleColor]::Green } else { [System.ConsoleColor]::DarkGray }
        & $renderRow $lblAlias $aliasDisplay $aliasColor

        Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
        Write-Host "    ╰──────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "    💡 $hintModel" -ForegroundColor DarkGray
        Write-Host "    💡 $hintFont" -ForegroundColor DarkGray
        $hintAlias = "Command aliases: ai alias on | off"
        Write-Host "    💡 $hintAlias" -ForegroundColor DarkGray
        Write-Host "    💡 $hintLang`n" -ForegroundColor DarkGray
        return
    }

    if ($fullPrompt -match '^(?:set-model|use-model|use|model)\s+([A-Za-z0-9.:_\-\/]+)$') {
        $newModel = $Matches[1].Trim()
        Set-TerminalAiConfig -Model $newModel | Out-Null
        $msg = "Active model successfully changed to '$newModel'!"
        Write-Host "`n    ✔ $msg`n" -ForegroundColor Green
        return
    }

    if ($fullPrompt -in @("models", "--models", "-m")) {
        Show-TerminalAiModels
        return
    }

    if ($fullPrompt -in @("config", "--config", "-c")) {
        Get-TerminalAiConfig
        return
    }

    # Manage short aliases
    if ($fullPrompt -match '^(?:alias|aliases)\s+(?:on|1|true|enable)$' -or
        $fullPrompt -in @("use-aliases", "use aliases")) {
        Set-TerminalAiConfig -UseAliases $true | Out-Null
        $msg = "PowerShell short aliases mode successfully ENABLED (defaulting to: gps, gci, select, ?, %)"
        Write-Host "`n    ✔ $msg`n" -ForegroundColor Green
        return
    }

    if ($fullPrompt -match '^(?:alias|aliases)\s+(?:off|0|false|disable)$' -or
        $fullPrompt -in @("no-aliases", "no aliases")) {
        Set-TerminalAiConfig -UseAliases $false | Out-Null
        $msg = "PowerShell short aliases mode DISABLED (using full cmdlet names)"
        Write-Host "`n    ✔ $msg`n" -ForegroundColor Green
        return
    }

    if ($fullPrompt -in @("alias", "aliases")) {
        Write-Host ""
        if ($cfg.UseAliases) {
            $aliasStatus = "ENABLED"
            $aliasColor = [System.ConsoleColor]::Green
        } else {
            $aliasStatus = "DISABLED"
            $aliasColor = [System.ConsoleColor]::DarkGray
        }
        & {
            Write-Host "    ✦ PowerShell short aliases mode: " -NoNewline -ForegroundColor Cyan
            Write-Host $aliasStatus -ForegroundColor $aliasColor
            Write-Host "    💡 Enable:     ai alias on   |  aif alias on" -ForegroundColor DarkGray
            Write-Host "    💡 Disable:    ai alias off  |  aif alias off`n" -ForegroundColor DarkGray
        }
        return
    }

    # Handle an explicit text response request
    if ($Ask) {
        Show-AiAnswer -Question $fullPrompt -Model $activeModel
        return
    }

    # Prepare parameters and aliases
    $preferAliases = [bool]($Alias.IsPresent -or $cfg.UseAliases)
    if ($fullPrompt -match '(?:\s*[\(\[]?\s*(?:use|with)\s+alias(?:es)?\s*[\)\]]?)$') {
        $preferAliases = $true
        $fullPrompt = ($fullPrompt -replace '(?:\s*[\(\[]?\s*(?:use|with)\s+alias(?:es)?\s*[\)\]]?)$', '').Trim()
    }

    Write-Host "`n  ✦ $(Get-TerminalAiText 'Connecting') ($activeModel)..." -ForegroundColor Cyan

    $systemPrompt = Get-AiSystemPrompt -UseAliases $preferAliases
    $rawResponse = Invoke-OllamaApi -Prompt $fullPrompt -SystemPrompt $systemPrompt -Model $activeModel -Temperature 0.0
    if ([string]::IsNullOrWhiteSpace($rawResponse)) {
        return
    }

    # Clear buffered input before showing the result and action menu
    Clear-AiInputBuffer

    $command = Format-AiCodeOutput -Text $rawResponse
    $command = [regex]::Replace($command, '\b(?:gci|Get-ChildItem)\s+tcpconn\b', 'Get-NetTCPConnection', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if ($preferAliases) {
        $command = ConvertTo-AiShortAliases $command
    }

    # Check syntax and unknown cmdlets
    $ast = $null
    $parseErrors = $null
    $tokens = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Write-Host "    ⚠ [$(Get-TerminalAiText 'Warning')] $($parseErrors[0].Message)" -ForegroundColor DarkYellow
        }
    } catch { }

    $isUnknownCmdlet = $false
    $firstWord = ($command.Trim() -split '[\s|\(]')[0].TrimStart('(').Trim()
    if ($firstWord -match '^[A-Za-z]+-[A-Za-z0-9]+$') {
        if (-not (Get-Command -Name $firstWord -ErrorAction Ignore)) {
            $isUnknownCmdlet = $true
        }
    }

    # Render the result card
    Show-AiCodeCard -Code $command -Title (Get-TerminalAiText "CardTitle") -Model $activeModel -CodeColor Green

    if ($isUnknownCmdlet) {
        Write-Host "    ⚠ [$(Get-TerminalAiText 'Warning')] $(Get-TerminalAiText 'UnknownCmdlet') '$firstWord'" -ForegroundColor DarkYellow
        Write-Host "      $(Get-TerminalAiText 'UnknownCmdletHint')`n" -ForegroundColor DarkGray
    }

    # Honor automatic copy or -Copy
    if ($Copy -or $cfg.AutoCopy) {
        Set-Clipboard -Value $command
        Write-Host "    ✔ $(Get-TerminalAiText 'Copied')`n" -ForegroundColor DarkGreen
    }

    # Honor -Execute
    if ($Execute) {
        Write-Host "    ▶ $(Get-TerminalAiText 'Executing') $command" -ForegroundColor Yellow
        Invoke-AiExecutionGate -Command $command -AutoConfirm
        return
    }

    # Honor -Preview or -WhatIf
    if ($Preview) {
        Invoke-AiExecutionGate -Command $command -WhatIf
        return
    }

    # Honor -Explain
    if ($Explain) {
        Show-AiExplanation -Command $command -Model $activeModel
        return
    }

    # Show the action menu with alias toggling
    while ($true) {
        $cmdAst = Test-AiCommandAst -Command $command
        Show-AiActionMenu -UseAliases $preferAliases -CanPreview $cmdAst.CanPreview

        $allowedActions = if ($cmdAst.CanPreview) {
            @('Execute', 'Copy', 'Insert', 'ShortAlias', 'Ask', 'Explain', 'WhatIf', 'Cancel')
        } else {
            @('Execute', 'Copy', 'Insert', 'ShortAlias', 'Ask', 'Explain', 'Cancel')
        }

        $action = Get-AiMenuKeyPress -AllowedActions $allowedActions
        switch ($action) {
            'WhatIf' {
                Invoke-AiExecutionGate -Command $command -WhatIf
                continue
            }
            'Execute' {
                Write-Host "    ▶ $(Get-TerminalAiText 'Executing')`n" -ForegroundColor Yellow
                Invoke-AiExecutionGate -Command $command -AutoConfirm
                return
            }
            'Cancel' {
                Write-Host "    $(Get-TerminalAiText 'Canceled')`n" -ForegroundColor DarkGray
                return
            }
            'Copy' {
                Set-Clipboard -Value $command
                Write-Host "    ✔ $(Get-TerminalAiText 'Copied')`n" -ForegroundColor Green
                return
            }
            'Insert' {
                Set-Clipboard -Value $command
                $pasted = $false
                try {
                    if (([System.Management.Automation.PSTypeName]'TerminalAiPasteHelper').Type) {
                        [TerminalAiPasteHelper]::DelayedPaste(200)
                        $pasted = $true
                    }
                } catch { }

                if (-not $pasted) {
                    try {
                        $ws = New-Object -ComObject WScript.Shell
                        $ws.SendKeys("^v")
                    } catch { }
                }
                Write-Host "    ✔ $(Get-TerminalAiText 'Inserted')`n" -ForegroundColor Green
                return
            }
            'Ask' {
                Show-AiAnswer -Question $fullPrompt -Model $activeModel
                return
            }
            'Explain' {
                Write-Host ""
                Show-AiExplanation -Command $command -Model $activeModel
                return
            }
            'ShortAlias' {
                $preferAliases = -not $preferAliases
                $command = if ($preferAliases) {
                    ConvertTo-AiShortAliases $command
                } else {
                    ConvertTo-AiFullCmdlets $command
                }
                Show-AiCodeCard -Code $command -Title (Get-TerminalAiText "CardTitle") -Model $activeModel -CodeColor Green
                continue
            }
        }
    }
}

function Show-AiExplanation {
    param(
        [string]$Command,
        [string]$Model
    )

    $cfg = Get-TerminalAiConfig
    $langInstruction = if ($cfg.Language -in @("uk", "ua")) { "Respond strictly in Ukrainian language." } else { "Respond in English." }

    Write-Host "`n  ✦ $(Get-TerminalAiText 'Explaining')" -ForegroundColor Cyan

    $explainSystemPrompt = @"
You are an expert technical educator explaining PowerShell commands to engineers.
$langInstruction
Explain concisely:
1. What the command does overall.
2. Breakdown of key parameters and pipeline operators.
3. Any potential performance or security considerations.
Format with clean bullet points.
"@

    $explanation = Invoke-OllamaApi -Prompt "Explain this PowerShell command: `n`n$Command" -SystemPrompt $explainSystemPrompt -Model $Model -Temperature 0.3
    if ($explanation) {
        Write-Host "`n    ✦ $(Get-TerminalAiText 'CardTitleExplain'):" -ForegroundColor Cyan
        Write-Host ("    " + ("─" * 66)) -ForegroundColor DarkCyan
        foreach ($line in ($explanation -split "`r?`n")) {
            Write-Host "    $line" -ForegroundColor Gray
        }
        Write-Host ("    " + ("─" * 66)) + "`n" -ForegroundColor DarkCyan
    }
}

function Invoke-AiFix {
    <#
    .SYNOPSIS
        Analyzes the last terminal error and proposes a corrected command through Ollama.
    .EXAMPLE
        ai-fix
    #>
    [CmdletBinding()]
    [Alias("ai-fix", "fix-error")]
    param(
        [string]$Model
    )

    $cfg = Get-TerminalAiConfig

    if ($global:Error.Count -eq 0) {
        Write-Host "    ✔ $(Get-TerminalAiText 'NoError')" -ForegroundColor Green
        return
    }

    $lastErr = $global:Error[0]
    $errMessage = $lastErr.Exception.Message
    $failedCommand = $lastErr.InvocationInfo.Line
    $failedScript = $lastErr.InvocationInfo.ScriptName

    $activeModel = if ($Model) { $Model } else { $cfg.Model }
    $langInstruction = if ($cfg.Language -in @("uk", "ua")) { "Respond in Ukrainian for the diagnosis, but output the fixed PowerShell command clearly." } else { "Respond in English." }

    Write-Host "`n  ✦ [AI-Fix] $(Get-TerminalAiText 'Fixing') ($activeModel)..." -ForegroundColor Cyan
    Write-Host "    $(Get-TerminalAiText 'ErrorLabel') " -NoNewline -ForegroundColor DarkYellow
    Write-Host "$errMessage" -ForegroundColor Red
    if ($failedCommand) {
        Write-Host "    $(Get-TerminalAiText 'FailedCommand') $failedCommand" -ForegroundColor DarkGray
    }

    $fixPrompt = @'
The user executed a command in PowerShell and encountered an error.
Failed command: {0}
Error message: {1}
Script/Location: {2}

Please provide:
1. DIAGNOSIS: A concise 1-2 sentence explanation of why this error happened.
2. FIXED_COMMAND: The exact corrected PowerShell command to solve the problem.

{3}
Format your response exactly as:
DIAGNOSIS: <brief explanation>
FIXED_COMMAND:
```powershell
<corrected command>
```
'@ -f $failedCommand, $errMessage, $failedScript, $langInstruction

    $fixSystemPrompt = @"
You are an elite PowerShell 7 debugging engineer.
Rules:
1. Provide a precise 1-2 sentence diagnosis.
2. Provide a 100% correct, runnable PowerShell fix.
3. If the command failed because of hallucinated or invalid cmdlets (such as 'gci tcpconn' or 'Get-ChildItem tcpconn'), replace them with standard cmdlets:
   - For ports/connections, use:
     Get-NetTCPConnection -LocalPort <port> -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Get-Process -Id `$_.OwningProcess -ErrorAction SilentlyContinue }
4. Never bind null to mandatory parameters like -Id.
5. Output code ONLY in the FIXED_COMMAND block.
"@

    $response = Invoke-OllamaApi -Prompt $fixPrompt -SystemPrompt $fixSystemPrompt -Model $activeModel -Temperature 0.1
    if (-not $response) { return }

    # Clear buffered input before showing the result and action menu
    Clear-AiInputBuffer

    # Parse the response
    $diagnosis = ""
    $fixedCode = ""

    if ($response -match '(?si)DIAGNOSIS:\s*(.*?)(?:FIXED_COMMAND:|$)') {
        $diagnosis = $Matches[1].Trim()
    }

    if ($response -match '(?si)```(?:powershell|pwsh)?\r?\n?(.*?)\r?\n?```') {
        $fixedCode = $Matches[1].Trim()
    } elseif ($response -match '(?si)FIXED_COMMAND:\s*(.*)') {
        $fixedCode = $Matches[1].Trim()
    }

    if ($diagnosis) {
        Write-Host "`n    ✦ $(Get-TerminalAiText 'Diagnosis')" -ForegroundColor Cyan
        Write-Host "    $diagnosis" -ForegroundColor White
    }

    if ($fixedCode) {
        $fixedCode = [regex]::Replace($fixedCode, '\b(?:gci|Get-ChildItem)\s+tcpconn\b', 'Get-NetTCPConnection', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        Show-AiCodeCard -Code $fixedCode -Title (Get-TerminalAiText "CardTitleFixed") -Model $activeModel -CodeColor Green

        Write-Host "    [Enter] " -NoNewline -ForegroundColor Green
        Write-Host ("{0,-18}" -f (Get-TerminalAiText "MenuEnter")) -NoNewline -ForegroundColor White
        Write-Host "[C] " -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,-18}" -f (Get-TerminalAiText "MenuCopy")) -NoNewline -ForegroundColor White
        Write-Host "[I] " -NoNewline -ForegroundColor Cyan
        Write-Host (Get-TerminalAiText "MenuInsert") -ForegroundColor White
        Write-Host "    [Esc]   " -NoNewline -ForegroundColor Gray
        Write-Host (Get-TerminalAiText "MenuCancel") -ForegroundColor White
        Write-Host ""

        $fixAction = Get-AiMenuKeyPress -AllowedActions @('Execute', 'Copy', 'Insert', 'Cancel')
        switch ($fixAction) {
            'Execute' {
                Write-Host "    ▶ $(Get-TerminalAiText 'ExecutingFixed')`n" -ForegroundColor Yellow
                Invoke-AiExecutionGate -Command $fixedCode -AutoConfirm
            }
            'Copy' {
                Set-Clipboard -Value $fixedCode
                Write-Host "    ✔ $(Get-TerminalAiText 'Copied')`n" -ForegroundColor Green
            }
            'Insert' {
                Set-Clipboard -Value $fixedCode
                $pasted = $false
                try {
                    if (([System.Management.Automation.PSTypeName]'TerminalAiPasteHelper').Type) {
                        [TerminalAiPasteHelper]::DelayedPaste(200)
                        $pasted = $true
                    }
                } catch { }

                if (-not $pasted) {
                    try {
                        $ws = New-Object -ComObject WScript.Shell
                        $ws.SendKeys("^v")
                    } catch { }
                }
                Write-Host "    ✔ $(Get-TerminalAiText 'Inserted')`n" -ForegroundColor Green
            }
            'Cancel' {
                Write-Host "    $(Get-TerminalAiText 'Canceled')`n" -ForegroundColor DarkGray
            }
        }
    }
}

function Protect-AiSecretData {
    <#
    .SYNOPSIS
        Deterministically masks secrets, API tokens, and passwords before adding context.
    .DESCRIPTION
        Replaces known token formats, private keys, and passwords with safe placeholders.
    .PARAMETER Text
        Text or code to sanitize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $res = $Text

    # PEM private keys
    $res = [regex]::Replace($res, '(?s)-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----.*?-----END (?:[A-Z ]+)?PRIVATE KEY-----', '***[REDACTED PRIVATE KEY]***')

    # Known API token prefixes
    $res = [regex]::Replace($res, '\b(sk-ant-[a-zA-Z0-9_\-]{20,})\b', 'sk-ant-***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(sk-[a-zA-Z0-9_\-]{20,})\b', 'sk-***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(hf_[a-zA-Z0-9]{20,})\b', 'hf_***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(ghp_[a-zA-Z0-9]{20,})\b', 'ghp_***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(github_pat_[a-zA-Z0-9_]{20,})\b', 'github_pat_***[REDACTED]***')
    $res = [regex]::Replace($res, '\b(AKIA[0-9A-Z]{16})\b', '***[REDACTED AWS KEY]***')

    # Bearer tokens
    $res = [regex]::Replace($res, '(?i)(bearer\s+)[a-zA-Z0-9_\-\.]{20,}', '${1}***[REDACTED]***')

    # Passwords and secrets in parameters or configuration
    $res = [regex]::Replace($res, '(?i)([$]?(?:password|pass|pwd)\s*[:=]\s*[\x22\x27])(?![^\x22\x27]*\[REDACTED\])[^\r\n\x22\x27]{4,}([\x22\x27])', '${1}***[REDACTED]***${2}')
    $res = [regex]::Replace($res, '(?i)([$]?(?:api[_-]?key|secret|token)\s*[:=]\s*[\x22\x27])(?![^\x22\x27]*\[REDACTED\])[^\r\n\x22\x27]{4,}([\x22\x27])', '${1}***[REDACTED]***${2}')

    return $res
}

function Format-AiScriptDiff {
    <#
    .SYNOPSIS
        Produces a deterministic unified diff between existing and new text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [string]$OldLabel = "Existing File",
        [string]$NewLabel = "New AI Script",
        [switch]$PassThru
    )

    $oldLines = if ($OldText) { $OldText -split '\r?\n' } else { @() }
    $newLines = if ($NewText) { $NewText -split '\r?\n' } else { @() }

    $diffRecords = [System.Collections.Generic.List[psobject]]::new()
    $i = 0
    $j = 0
    $maxSteps = ($oldLines.Count + $newLines.Count) * 2 + 10
    $steps = 0

    while (($i -lt $oldLines.Count -or $j -lt $newLines.Count) -and ($steps -lt $maxSteps)) {
        $steps++
        $o = if ($i -lt $oldLines.Count) { $oldLines[$i] } else { $null }
        $n = if ($j -lt $newLines.Count) { $newLines[$j] } else { $null }

        if ($null -ne $o -and $null -ne $n -and $o -eq $n) {
            $diffRecords.Add([PSCustomObject]@{ Type = "Unchanged"; Line = "  $o" })
            $i++; $j++
        } elseif ($null -ne $o -and $null -ne $n -and $o -ne $n) {
            if (($j + 1) -lt $newLines.Count -and $newLines[$j + 1] -eq $o) {
                $diffRecords.Add([PSCustomObject]@{ Type = "Added"; Line = "+ $n" })
                $j++
            } elseif (($i + 1) -lt $oldLines.Count -and $oldLines[$i + 1] -eq $n) {
                $diffRecords.Add([PSCustomObject]@{ Type = "Removed"; Line = "- $o" })
                $i++
            } else {
                $diffRecords.Add([PSCustomObject]@{ Type = "Removed"; Line = "- $o" })
                $diffRecords.Add([PSCustomObject]@{ Type = "Added"; Line = "+ $n" })
                $i++; $j++
            }
        } elseif ($null -ne $o -and $null -eq $n) {
            $diffRecords.Add([PSCustomObject]@{ Type = "Removed"; Line = "- $o" })
            $i++
        } elseif ($null -eq $o -and $null -ne $n) {
            $diffRecords.Add([PSCustomObject]@{ Type = "Added"; Line = "+ $n" })
            $j++
        } else {
            break
        }
    }

    Write-Host ""
    Write-Host "    --- $OldLabel" -ForegroundColor Red
    Write-Host "    +++ $NewLabel" -ForegroundColor Green
    foreach ($dl in $diffRecords) {
        switch ($dl.Type) {
            "Added"     { Write-Host "    $($dl.Line)" -ForegroundColor Green }
            "Removed"   { Write-Host "    $($dl.Line)" -ForegroundColor Red }
            "Unchanged" { Write-Host "    $($dl.Line)" -ForegroundColor DarkGray }
        }
    }
    Write-Host ""

    if ($PassThru) {
        return @($diffRecords)
    }
}

function Save-AiScriptFile {
    <#
    .SYNOPSIS
        Atomically saves an AI-generated script with a diff and overwrite confirmation.
    .DESCRIPTION
        If the file already exists, returns immediately for identical content or displays a diff
        and requires explicit confirmation before an atomic UTF-8 BOM write.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Content,

        [switch]$Force,

        [string]$ConfirmInput,

        [switch]$PassThru
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $fileExists = Test-Path -Path $resolvedPath -PathType Leaf
    $diff = @()

    if ($fileExists) {
        $existingContent = try {
            [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
        } catch {
            Get-Content -Path $resolvedPath -Raw -ErrorAction SilentlyContinue
        }

        if ($null -ne $existingContent -and $existingContent.Trim() -eq $Content.Trim()) {
            Write-Host "    ℹ [TerminalAI] File already exists with identical content: $resolvedPath" -ForegroundColor DarkCyan
            if ($PassThru) {
                return [PSCustomObject]@{
                    Saved  = $true
                    Status = "Identical"
                    Path   = $resolvedPath
                    Diff   = @()
                }
            }
            return $true
        }

        # Show a diff when the existing file differs
        Write-Host ""
        Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "    │             ⚠  EXISTING FILE OVERWRITE WARNING  ⚠           │" -ForegroundColor Yellow
        Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host "    File: $resolvedPath" -ForegroundColor Cyan

        $diff = Format-AiScriptDiff -OldText $existingContent -NewText $Content -OldLabel "Existing File" -NewLabel "New AI Script" -PassThru

        if (-not $Force) {
            $confirmed = $false
            if ($PSBoundParameters.ContainsKey('ConfirmInput')) {
                $response = $ConfirmInput
            } else {
                try {
                    $isInteractive = [Environment]::UserInteractive
                    if ([Console]::IsInputRedirected) { $isInteractive = $false }
                } catch { $isInteractive = $true }

                if (-not $isInteractive) {
                    Write-Host "    ✖ Non-interactive session. Overwrite canceled for safety." -ForegroundColor Red
                    if ($PassThru) {
                        return [PSCustomObject]@{
                            Saved  = $false
                            Status = "BlockedNonInteractive"
                            Path   = $resolvedPath
                            Diff   = $diff
                        }
                    }
                    return $false
                }

                $response = Read-Host "    Overwrite this file? [y/N]"
            }

            if ($response -match '^(y|yes)$') {
                $confirmed = $true
            }

            if (-not $confirmed) {
                Write-Host "    ✖ Overwrite canceled by user." -ForegroundColor DarkGray
                if ($PassThru) {
                    return [PSCustomObject]@{
                        Saved  = $false
                        Status = "OverwriteDenied"
                        Path   = $resolvedPath
                        Diff   = $diff
                    }
                }
                return $false
            }
        }
    }

    # Write to a temporary file, then replace atomically
    $enc = New-Object System.Text.UTF8Encoding($true)
    $dir = [System.IO.Path]::GetDirectoryName($resolvedPath)
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $tmpPath = "$resolvedPath.tmp." + [System.Guid]::NewGuid().ToString("N")
    try {
        [System.IO.File]::WriteAllText($tmpPath, $Content, $enc)
        if ($fileExists) {
            [System.IO.File]::Copy($tmpPath, $resolvedPath, $true)
            [System.IO.File]::Delete($tmpPath)
        } else {
            [System.IO.File]::Move($tmpPath, $resolvedPath)
        }
        Write-Host "    ✔ File successfully saved: $resolvedPath" -ForegroundColor Green
        if ($PassThru) {
            return [PSCustomObject]@{
                Saved  = $true
                Status = if ($fileExists) { "Overwritten" } else { "Created" }
                Path   = $resolvedPath
                Diff   = if ($fileExists) { $diff } else { @() }
            }
        }
        return $true
    } catch {
        if (Test-Path $tmpPath) {
            Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host "    ✖ Error saving file: $($_.Exception.Message)" -ForegroundColor Red
        if ($PassThru) {
            return [PSCustomObject]@{
                Saved  = $false
                Status = "Error"
                Path   = $resolvedPath
                Error  = $_.Exception.Message
            }
        }
        return $false
    }
}

function New-AiScript {
    <#
    .SYNOPSIS
        Generates a complete parameterized PowerShell script with error handling.
    .EXAMPLE
        ai-script "Archive last month's logs and send a notification" -OutputPath ./backup_logs.ps1 -Edit
    #>
    [CmdletBinding()]
    [Alias("ai-script")]
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Description,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [switch]$Edit,

        [string]$Model
    )

    $fullDesc = ($Description -join " ").Trim()
    $cfg = Get-TerminalAiConfig
    $activeModel = if ($Model) { $Model } else { $cfg.Model }
    $isUk = ($cfg.Language -in @("uk", "ua"))

    Write-Host "`n  [AI-Script] $(Get-TerminalAiText 'Scripting')" -ForegroundColor Cyan
    $taskLabel = "Task:"
    Write-Host "  $taskLabel $fullDesc" -ForegroundColor DarkGray

    $scriptSystemPrompt = @"
You are a Principal PowerShell Engineer.
Write a production-grade, modular, well-commented PowerShell script for PowerShell 7.
Requirements:
1. Include a Help/Documentation block (<# .SYNOPSIS ... #>).
2. Use [CmdletBinding()] and a strongly-typed param() block with sensible defaults.
3. Wrap operations in robust try/catch blocks with informative error logging.
4. Output clean, readable, executable PowerShell script code.
5. If using markdown code fences, format them cleanly.
"@

    $rawResponse = Invoke-OllamaApi -Prompt $fullDesc -SystemPrompt $scriptSystemPrompt -Model $activeModel -Temperature 0.2
    if (-not $rawResponse) { return }

    $scriptContent = Format-AiCodeOutput -Text $rawResponse

    if ($OutputPath) {
        $saved = Save-AiScriptFile -Path $OutputPath -Content $scriptContent
        if ($saved -and $Edit) {
            if (Get-Command code -ErrorAction Ignore) {
                code $OutputPath
            } else {
                notepad $OutputPath
            }
        }
    } else {
        Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
        Write-Host $scriptContent -ForegroundColor White
        Write-Host ("=" * 70) + "`n" -ForegroundColor Cyan

        Write-Host "  $(Get-TerminalAiText 'SaveScriptPrompt')" -NoNewline -ForegroundColor Yellow
        $resp = Read-Host
        if ($resp -match '^(y|yes)$') {
            $defaultName = "script_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".ps1"
            $promptFileName = (Get-TerminalAiText "EnterFileName") -f $defaultName
            $savePath = Read-Host "  $promptFileName"
            if ([string]::IsNullOrWhiteSpace($savePath)) { $savePath = $defaultName }
            Save-AiScriptFile -Path $savePath -Content $scriptContent
        }
    }
}

function Invoke-AiAssistant {
    <#
    .SYNOPSIS
        Starts the interactive AI assistant in Windows Terminal or PowerShell.
    .DESCRIPTION
        Starts a multi-turn REPL with Tab completion, slash commands, and model selection.
    .EXAMPLE
        ai-chat
    .EXAMPLE
        ai-chat -Model qwen2.5-coder:7b
    #>
    [CmdletBinding()]
    [Alias("ai-chat", "ai-assistant")]
    param(
        [Parameter(Position = 0)]
        [string]$Model
    )

    $assistantScript = Join-Path $PSScriptRoot "TerminalAiAssistant.ps1"
    if (-not (Test-Path $assistantScript)) {
        $module = Get-Module TerminalAI -ListAvailable | Select-Object -First 1
        if ($module) {
            $assistantScript = Join-Path $module.ModuleBase "TerminalAiAssistant.ps1"
        }
    }

    if (Test-Path $assistantScript) {
        $params = @{}
        if ($Model) { $params["Model"] = $Model }
        & $assistantScript @params
    } else {
        $cfg = try { Get-TerminalAiConfig } catch { $null }
        $errNotFound = "TerminalAiAssistant.ps1 not found in '$PSScriptRoot'."
        Write-Error "[TerminalAI] $errNotFound"
    }
}

function Test-TerminalAiInstallation {
    <#
    .SYNOPSIS
        Runs comprehensive diagnostics for TerminalAI and its local environment.
    .DESCRIPTION
        Checks PowerShell compatibility, module registration, profile integration, the Windows
        Terminal fragment, Ollama availability, model configuration, the AST security gate,
        and module file integrity.
    .PARAMETER Fix
        Repairs detected issues when possible.
    .PARAMETER PassThru
        Returns a structured object containing every diagnostic result.
    .EXAMPLE
        ai-doctor
    .EXAMPLE
        Test-TerminalAiInstallation -PassThru
    #>
    [CmdletBinding()]
    [Alias("ai-doctor")]
    param(
        [switch]$Fix,
        [switch]$PassThru
    )

    $cfg = try { Get-TerminalAiConfig } catch { $null }

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "         ✦ TERMINAL AI SYSTEM DIAGNOSTICS (AI-DOCTOR) ✦        " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

    $results = [ordered]@{}
    $allPassed = $true

    # 1. PowerShell Environment
    $psVer = $PSVersionTable.PSVersion
    $currentEdition = $PSVersionTable.PSEdition
    $results["PowerShellVersion"] = "$psVer ($currentEdition)"
    $results["PowerShellOk"] = $true
    Write-Host "  1. PowerShell:           " -NoNewline -ForegroundColor DarkGray
    Write-Host "✔ $psVer ($currentEdition)" -ForegroundColor Green

    # 2. Module in PSModulePath
    $module = Get-Module -Name TerminalAI -ListAvailable | Select-Object -First 1
    $moduleOk = ($null -ne $module)
    $results["ModuleRegistered"] = $moduleOk
    $results["ModuleBase"] = if ($module) { $module.ModuleBase } else { "Not found" }
    Write-Host "  2. Module Registration:  " -NoNewline -ForegroundColor DarkGray
    if ($moduleOk) {
        Write-Host "✔ Found at $($module.ModuleBase)" -ForegroundColor Green
    } else {
        Write-Host "✖ Module not found in PSModulePath" -ForegroundColor Red
        $allPassed = $false
    }

    # 3. $PROFILE Integration
    $profilePath = if ($PROFILE.CurrentUserCurrentHost) { $PROFILE.CurrentUserCurrentHost } else { $PROFILE }
    $profileHasBlock = $false
    if (Test-Path $profilePath) {
        $pContent = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
        if ($pContent -match '(?ms)# >>> TerminalAI Initialization >>>.*?# <<< TerminalAI Initialization <<<|Import-Module\s+TerminalAI') {
            $profileHasBlock = $true
        }
    }
    $results["ProfileConfigured"] = $profileHasBlock
    $results["ProfilePath"] = $profilePath
    Write-Host "  3. Profile Integration:  " -NoNewline -ForegroundColor DarkGray
    if ($profileHasBlock) {
        Write-Host "✔ Configured in $profilePath" -ForegroundColor Green
    } else {
        Write-Host "⚠ Not configured in $profilePath" -ForegroundColor Yellow
    }

    # 4. Windows Terminal Fragment
    $fragCandidates = @(
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\TerminalAI\terminalai.json",
        "$env:ProgramData\Microsoft\Windows Terminal\Fragments\TerminalAI\terminalai.json"
    )
    $foundFrag = $null
    $fragValid = $false
    foreach ($fc in $fragCandidates) {
        if (Test-Path $fc) {
            $foundFrag = $fc
            try {
                $j = Get-Content -Path $fc -Raw | ConvertFrom-Json
                if ($j.profiles -or $j.actions) { $fragValid = $true }
            } catch { }
            break
        }
    }
    $results["FragmentFound"] = ($null -ne $foundFrag)
    $results["FragmentValid"] = $fragValid
    $results["FragmentPath"] = $foundFrag
    Write-Host "  4. WT Fragment JSON:     " -NoNewline -ForegroundColor DarkGray
    if ($fragValid) {
        Write-Host "✔ Valid Fragment at $foundFrag" -ForegroundColor Green
    } elseif ($foundFrag) {
        Write-Host "✖ Corrupted JSON at $foundFrag" -ForegroundColor Red
        $allPassed = $false
    } else {
        Write-Host "⚠ No Fragment registered in LocalAppData/ProgramData" -ForegroundColor Yellow
    }

    # 5. Ollama Service Reachability
    $ollamaOk = $false
    $ollamaUrl = if ($cfg -and $cfg.OllamaUrl) { $cfg.OllamaUrl } else { "http://localhost:11434" }
    $installedModels = @()
    $latencyMs = 0
    foreach ($cand in @($ollamaUrl, "http://127.0.0.1:11434", "http://localhost:11434")) {
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $res = Invoke-RestMethod -Uri "$($cand.TrimEnd('/'))/api/tags" -TimeoutSec 2 -ErrorAction Stop
            $sw.Stop()
            $latencyMs = [Math]::Round($sw.Elapsed.TotalMilliseconds)
            $installedModels = @($res.models.name)
            $ollamaOk = $true
            $ollamaUrl = $cand
            break
        } catch { }
    }
    $results["OllamaReachable"] = $ollamaOk
    $results["OllamaUrl"] = $ollamaUrl
    $results["OllamaLatencyMs"] = $latencyMs
    $results["InstalledModels"] = $installedModels
    Write-Host "  5. Ollama Local Service: " -NoNewline -ForegroundColor DarkGray
    if ($ollamaOk) {
        Write-Host "✔ Responding at $ollamaUrl (${latencyMs}ms, $($installedModels.Count) models)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Service unreachable at $ollamaUrl (start with 'ollama serve')" -ForegroundColor Yellow
    }

    # 6. Active Model Availability
    $activeModel = if ($cfg -and $cfg.Model) { $cfg.Model } else { "qwen2.5-coder:7b" }
    $modelPresent = ($installedModels -contains $activeModel)
    $results["ActiveModel"] = $activeModel
    $results["ActiveModelPresent"] = $modelPresent
    Write-Host "  6. Active Model:         " -NoNewline -ForegroundColor DarkGray
    if ($modelPresent) {
        Write-Host "✔ '$activeModel' is installed and ready" -ForegroundColor Green
    } elseif ($ollamaOk) {
        Write-Host "⚠ '$activeModel' not found in Ollama (pull with 'ollama pull $activeModel')" -ForegroundColor Yellow
    } else {
        Write-Host "⚠ Cannot verify model (Ollama service offline)" -ForegroundColor DarkYellow
    }

    # 7. AST Security Gate Engine
    $astOk = $false
    try {
        $sampleAst = Test-AiCommandAst -Command "Get-Process | Where-Object CPU -gt 10"
        $cat = if ($sampleAst.OverallCategory) { $sampleAst.OverallCategory } else { $sampleAst.Category }
        $risk = if ($sampleAst.OverallRisk) { $sampleAst.OverallRisk } else { $sampleAst.Risk }
        if ($sampleAst -and $cat -eq "ReadOnly" -and $risk -eq "Low") {
            $astOk = $true
        }
    } catch { }
    $results["AstEngineOk"] = $astOk
    Write-Host "  7. AST Security Gate:    " -NoNewline -ForegroundColor DarkGray
    if ($astOk) {
        Write-Host "✔ Engine operational (syntax, categories, risk gates)" -ForegroundColor Green
    } else {
        Write-Host "✖ AST Engine error" -ForegroundColor Red
        $allPassed = $false
    }

    # 8. Secret Redaction & Sanitization
    $redactionOk = $false
    try {
        $secretProbe = Protect-AiSecretData -Text "key sk-1234567890abcdef12345678"
        if ($secretProbe -match 'sk-\*\*\*\[REDACTED\]\*\*\*') {
            $redactionOk = $true
        }
    } catch { }
    $results["SecretRedactionOk"] = $redactionOk
    Write-Host "  8. Secret Protection:    " -NoNewline -ForegroundColor DarkGray
    if ($redactionOk) {
        Write-Host "✔ Active (deterministic regex masking & FIFO cap)" -ForegroundColor Green
    } else {
        Write-Host "✖ Redaction engine failure" -ForegroundColor Red
        $allPassed = $false
    }

    # 9. Claude Code Agent Mode (Optional)
    $agentReadiness = $null
    try {
        if (Get-Command Test-AiAgentReadiness -ErrorAction Ignore) {
            $agentReadiness = Test-AiAgentReadiness -PassThru
        }
    } catch { }

    $claudeAvailable = ($null -ne $agentReadiness -and $agentReadiness.ClaudeReady)
    $results["AgentModeAvailable"] = ($null -ne $agentReadiness -and $agentReadiness.Ready)
    $results["ClaudeExecutable"] = if ($agentReadiness) { $agentReadiness.ClaudePath } else { $null }
    $results["ClaudeVersion"] = if ($agentReadiness) { $agentReadiness.ClaudeVersion } else { $null }

    Write-Host "  9. Claude Code (Agent):  " -NoNewline -ForegroundColor DarkGray
    if ($claudeAvailable) {
        $vStr = if ($agentReadiness.ClaudeVersion) { " (v$($agentReadiness.ClaudeVersion))" } else { "" }
        Write-Host "✔ Detected$vStr - ready for 'ai-agent'" -ForegroundColor Green
    } else {
        Write-Host "ℹ Optional: Not installed (core features unaffected; install for 'ai-agent')" -ForegroundColor DarkCyan
    }

    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    if ($allPassed) {
        Write-Host "  ✦ All primary subsystems are healthy and operational! ✦" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ One or more items require attention. See details above." -ForegroundColor Yellow
    }
    Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

    $results["AllPassed"] = $allPassed

    if ($PassThru) {
        return [PSCustomObject]$results
    }
}

function Send-OllamaHttpAsync {
    [CmdletBinding()]
    param(
        [string]$Endpoint = "api/generate",
        [hashtable]$Payload
    )

    $cfg = Get-TerminalAiConfig
    $targetUrl = "$($cfg.OllamaUrl.TrimEnd('/'))/$($Endpoint.TrimStart('/'))"
    $bodyJson = $Payload | ConvertTo-Json -Depth 6

    if (-not ([System.Management.Automation.PSTypeName]'System.Net.Http.HttpClient').Type) {
        try { Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue } catch { }
    }

    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.Timeout = [TimeSpan]::FromSeconds($cfg.TimeoutSeconds)
    $httpContent = [System.Net.Http.StringContent]::new($bodyJson, [System.Text.Encoding]::UTF8, "application/json")
    $postTask = $httpClient.PostAsync($targetUrl, $httpContent)

    return @{
        Client = $httpClient
        Task   = $postTask
        Url    = $targetUrl
    }
}

# --- PSREADLINE HOTKEY INTEGRATION ---

function Register-TerminalAiKeyHandler {
    [CmdletBinding()]
    param(
        [string[]]$Chord
    )

    if (-not (Get-Module -Name PSReadLine)) {
        try {
            Import-Module PSReadLine -ErrorAction Stop
        } catch {
            $cfg = try { Get-TerminalAiConfig } catch { $null }
            $warnPsr = if ($cfg -and $cfg.Language -in @("uk", "ua")) {
                " [TerminalAI] PSReadLine was not found. Inline hotkeys are unavailable."
            } else {
                " [TerminalAI] PSReadLine module not found. Inline hotkeys are unavailable."
            }
            Write-Warning $warnPsr
            return
        }
    }

    $cfg = Get-TerminalAiConfig

    # Register F2, Ctrl+G, and Ctrl+Alt+A
    $targetChords = [System.Collections.Generic.List[string]]::new()
    $targetChords.Add("F2")
    foreach ($cg in @("Ctrl+g", "Ctrl+G")) {
        $targetChords.Add($cg)
    }
    foreach ($ca in @("Ctrl+Alt+a", "Ctrl+Alt+A")) {
        $targetChords.Add($ca)
    }
    if ($Chord) {
        foreach ($c in $Chord) {
            if (-not $targetChords.Contains($c)) { $targetChords.Add($c) }
        }
    } elseif ($cfg.HotkeyChord) {
        $custom = $cfg.HotkeyChord
        if (-not $targetChords.Contains($custom)) { $targetChords.Add($custom) }
        if (-not $targetChords.Contains($custom.ToLower())) { $targetChords.Add($custom.ToLower()) }
        if (-not $targetChords.Contains($custom.ToUpper())) { $targetChords.Add($custom.ToUpper()) }
    }

    $keyHandler = {
        param($key, $arg)

        $line = ""
        $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $query = $line.Trim()
        # Remove comment prefixes, aliases, and prompt templates
        if ($query -match '^(?:#\s*\[AI[^\]]*\]:?|#|\?\?)\s*(.*)') {
            $query = $Matches[1].Trim()
        }
        if ($query -match '^\[AI[^\]]*\]:?\s*(.*)') {
            $query = $Matches[1].Trim()
        }

        $cfg = Get-TerminalAiConfig

        if ([string]::IsNullOrWhiteSpace($query)) {
            # Insert a prompt template when the line is empty or contains only a prefix
            $promptPlaceholder = "# [AI Prompt]: "
            $currLine = ""
            $currCursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currLine, [ref]$currCursor)
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, $promptPlaceholder)
            return
        }

        try {
            $activeModel = $cfg.Model
            $sysPrompt = Get-AiSystemPrompt
            $payload = @{
                model      = $activeModel
                prompt     = $query
                system     = $sysPrompt
                stream     = $false
                keep_alive = "1h"
                options    = @{
                    temperature = 0.0
                    num_ctx     = 1024
                    num_predict = 120
                }
            }

            $asyncCall = Send-OllamaHttpAsync -Endpoint "api/generate" -Payload $payload
            $httpClient = $asyncCall.Client
            $postTask = $asyncCall.Task

            # Spinner frames and elapsed seconds
            $spinnerFrames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $frameIdx = 0

            # Shorten long prompts to fit the window
            $displayQuery = if ($query.Length -gt 45) { $query.Substring(0, 42) + "..." } else { $query }

            # Render the initial timer state immediately
            $currLine = ""
            $currCursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currLine, [ref]$currCursor)
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, "# [AI ⠋ 0s] $displayQuery")

            while (-not $postTask.IsCompleted) {
                $spinner = $spinnerFrames[$frameIdx % $spinnerFrames.Length]
                $sec = [Math]::Floor($stopwatch.Elapsed.TotalSeconds)
                $statusText = "# [AI $spinner ${sec}s] $displayQuery"

                $currLine = ""
                $currCursor = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currLine, [ref]$currCursor)
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, $statusText)

                Start-Sleep -Milliseconds 120
                $frameIdx++
            }
            $stopwatch.Stop()

            $cleanCode = ""
            try {
                $httpResponse = $postTask.GetAwaiter().GetResult()
                if ($httpResponse.IsSuccessStatusCode) {
                    $respString = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    $json = $respString | ConvertFrom-Json
                    $cleanCode = Format-AiCodeOutput -Text $json.response
                }
            }
            catch { }
            finally {
                $httpClient.Dispose()
            }

            $currLine = ""
            $currCursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currLine, [ref]$currCursor)

            if (-not [string]::IsNullOrWhiteSpace($cleanCode)) {
                # Replace the indicator with the generated command
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, $cleanCode)
            } else {
                # Report an empty or failed response and restore the line
                $msg = "# [AI: Ollama offline / error response]"
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $currLine.Length, "$msg $displayQuery")
                Start-Sleep -Milliseconds 900
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, "$msg $displayQuery".Length, $line)
            }
        }
        catch {
            # Restore the line safely after an exception
            try {
                $errLine = ""
                $errCursor = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$errLine, [ref]$errCursor)
                $errMsg = "# [AI: Ollama offline / connection error]"
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $errLine.Length, "$errMsg $displayQuery")
                Start-Sleep -Milliseconds 900
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, "$errMsg $displayQuery".Length, $line)
            } catch { }
        }
    }

    foreach ($c in $targetChords) {
        try {
            Set-PSReadLineKeyHandler -Chord $c -ScriptBlock $keyHandler -Description "Terminal AI: Generate PowerShell command" -ErrorAction SilentlyContinue
        }
        catch { }
    }
}

$script:TerminalAiCachedModels = $null
$script:TerminalAiCacheTime = [datetime]::MinValue

$script:TerminalAiGetModels = {
    param([string]$word = "")
    $now = [datetime]::UtcNow
    if ($script:TerminalAiCachedModels -and ($now - $script:TerminalAiCacheTime).TotalSeconds -lt 20) {
        return ($script:TerminalAiCachedModels | Where-Object { $_.CompletionText -like "$word*" })
    }

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
    try {
        $cfg = Get-TerminalAiConfig
        $url = if ($cfg.OllamaUrl) { $cfg.OllamaUrl } else { "http://127.0.0.1:11434" }
        $url = $url -replace 'localhost', '127.0.0.1'
        $res = Invoke-RestMethod -Uri "$url/api/tags" -Method Get -TimeoutSec 1 -ErrorAction Stop
        if ($res.models) {
            foreach ($m in $res.models) {
                $sizeGb = [math]::Round($m.size / 1GB, 1)
                $tooltip = "$($m.name) ($sizeGb GB)"
                $results.Add([System.Management.Automation.CompletionResult]::new($m.name, $m.name, 'ParameterValue', $tooltip))
            }
        }
    }
    catch { }

    if ($results.Count -eq 0) {
        $defaults = @('qwen2.5-coder:7b', 'granite4.2:8b', 'deepseek-coder:6.7b', 'qwen2.5-coder:1.5b')
        foreach ($d in $defaults) {
            $results.Add([System.Management.Automation.CompletionResult]::new($d, $d, 'ParameterValue', $d))
        }
    }
    $script:TerminalAiCachedModels = $results
    $script:TerminalAiCacheTime = $now
    return ($results | Where-Object { $_.CompletionText -like "$word*" })
}

function Register-TerminalAiArgumentCompleters {
    <#
    .SYNOPSIS
        Registers dynamic Tab completion for TerminalAI.
    .DESCRIPTION
        Completes subcommands, help topics, model response languages, and installed Ollama models.
    #>
    [CmdletBinding()]
    param()

    $commands = @('Invoke-AiCommand', 'ai', '??', 'Invoke-AiCommandFast', 'ai-fast', 'aif')

    # Complete -Topic for Show-TerminalAiHelp and ai-help
    $topicCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $topics = @(
            [System.Management.Automation.CompletionResult]::new('all', 'all', 'ParameterValue', 'Complete overview & command map'),
            [System.Management.Automation.CompletionResult]::new('shortcuts', 'shortcuts', 'ParameterValue', 'Keybindings, flags, and aliases cheat-sheet'),
            [System.Management.Automation.CompletionResult]::new('models', 'models', 'ParameterValue', 'Ollama coding models & VRAM requirements'),
            [System.Management.Automation.CompletionResult]::new('examples', 'examples', 'ParameterValue', 'Practical DevOps & sysadmin examples'),
            [System.Management.Automation.CompletionResult]::new('workflow', 'workflow', 'ParameterValue', 'Windows Terminal interactive workflow guide'),
            [System.Management.Automation.CompletionResult]::new('config', 'config', 'ParameterValue', 'Configuration parameters & options')
        )
        $topics | Where-Object { $_.CompletionText -like "$wordToComplete*" }
    }
    Register-ArgumentCompleter -CommandName @('Show-TerminalAiHelp', 'ai-help') -ParameterName 'Topic' -ScriptBlock $topicCompleter -ErrorAction Ignore

    # Complete installed Ollama models for -Model
    $modelCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        & $script:TerminalAiGetModels $wordToComplete
    }
    Register-ArgumentCompleter -CommandName $commands -ParameterName 'Model' -ScriptBlock $modelCompleter -ErrorAction Ignore

    # Complete subcommands, topics, languages, and models for Prompt
    $promptCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $elements = $commandAst.CommandElements
        $tokens = @()
        foreach ($el in $elements) {
            $t = $el.Extent.Text.Trim().Trim('"').Trim("'")
            if (-not [string]::IsNullOrWhiteSpace($t)) { $tokens += $t }
        }

        # First argument after the command
        if ($tokens.Count -le 1 -or ($tokens.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($wordToComplete))) {
            $subcommands = @(
                [System.Management.Automation.CompletionResult]::new('help', 'help', 'ParameterValue', 'Educational guides & cheat-sheets'),
                [System.Management.Automation.CompletionResult]::new('shortcuts', 'shortcuts', 'ParameterValue', 'Keybindings, flags, and aliases guide'),
                [System.Management.Automation.CompletionResult]::new('status', 'status', 'ParameterValue', 'System information, active model and language'),
                [System.Management.Automation.CompletionResult]::new('alias', 'alias', 'ParameterValue', 'Configure short PowerShell aliases (on | off)'),
                [System.Management.Automation.CompletionResult]::new('models', 'models', 'ParameterValue', 'List installed Ollama models'),
                [System.Management.Automation.CompletionResult]::new('model', 'model', 'ParameterValue', 'Switch active Ollama model'),
                [System.Management.Automation.CompletionResult]::new('lang', 'lang', 'ParameterValue', 'Switch model response language (en | uk)'),
                [System.Management.Automation.CompletionResult]::new('examples', 'examples', 'ParameterValue', 'Practical command examples'),
                [System.Management.Automation.CompletionResult]::new('workflow', 'workflow', 'ParameterValue', 'Interactive terminal workflow guide'),
                [System.Management.Automation.CompletionResult]::new('config', 'config', 'ParameterValue', 'View configuration JSON'),
                [System.Management.Automation.CompletionResult]::new('fonts', 'fonts', 'ParameterValue', 'List available terminal fonts')
            )
            return ($subcommands | Where-Object { $_.CompletionText -like "$wordToComplete*" })
        }

        # Use the first token to complete the second argument
        $firstArg = $tokens[1].ToLowerInvariant()

        if ($firstArg -in @('alias', 'aliases')) {
            $aliasOpts = @(
                [System.Management.Automation.CompletionResult]::new('on', 'on', 'ParameterValue', 'Enable short PowerShell aliases (gps, gci, select, ?, %)'),
                [System.Management.Automation.CompletionResult]::new('off', 'off', 'ParameterValue', 'Disable short aliases (use full cmdlet names)'),
                [System.Management.Automation.CompletionResult]::new('status', 'status', 'ParameterValue', 'Check current alias mode')
            )
            return ($aliasOpts | Where-Object { $_.CompletionText -like "$wordToComplete*" })
        }

        if ($firstArg -eq 'help') {
            $topics = @(
                [System.Management.Automation.CompletionResult]::new('all', 'all', 'ParameterValue', 'Complete overview & command map'),
                [System.Management.Automation.CompletionResult]::new('shortcuts', 'shortcuts', 'ParameterValue', 'Keybindings, flags, and aliases guide'),
                [System.Management.Automation.CompletionResult]::new('models', 'models', 'ParameterValue', 'Ollama coding models & VRAM requirements'),
                [System.Management.Automation.CompletionResult]::new('examples', 'examples', 'ParameterValue', 'Practical DevOps & sysadmin examples'),
                [System.Management.Automation.CompletionResult]::new('workflow', 'workflow', 'ParameterValue', 'Windows Terminal interactive workflow guide'),
                [System.Management.Automation.CompletionResult]::new('config', 'config', 'ParameterValue', 'Configuration parameters & options')
            )
            return ($topics | Where-Object { $_.CompletionText -like "$wordToComplete*" })
        }

        if ($firstArg -in @('model', 'set-model', 'use-model')) {
            return (& $script:TerminalAiGetModels $wordToComplete)
        }

        if ($firstArg -in @('lang', 'language', 'set-lang')) {
            $langs = @(
                [System.Management.Automation.CompletionResult]::new('en', 'en', 'ParameterValue', 'English language'),
                [System.Management.Automation.CompletionResult]::new('uk', 'uk', 'ParameterValue', 'Ukrainian language')
            )
            return ($langs | Where-Object { $_.CompletionText -like "$wordToComplete*" })
        }

        return @()
    }
    Register-ArgumentCompleter -CommandName $commands -ParameterName 'Prompt' -ScriptBlock $promptCompleter -ErrorAction Ignore
}

# --- ALIASES AND MODULE AUTOLOAD ---
Set-Alias -Name ai-help -Value Show-TerminalAiHelp
Set-Alias -Name ai-font -Value Set-TerminalAiFont
Set-Alias -Name ai-fonts -Value Show-TerminalAiFonts
Set-Alias -Name ai-lang -Value Set-TerminalAiLanguage
Set-Alias -Name ai-lang-permanent -Value Set-TerminalAiDefaultLanguage
Set-Alias -Name ai-lang-default -Value Set-TerminalAiDefaultLanguage
Set-Alias -Name ai-chat -Value Invoke-AiAssistant
Set-Alias -Name ai-assistant -Value Invoke-AiAssistant

$hasFastCmdlet = $false
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $hasFastCmdlet = $null -ne ($ExecutionContext.SessionState.InvokeCommand.GetCmdlet("Invoke-AiCommandFast"))
}

if ($hasFastCmdlet) {
    Set-Alias -Name aif -Value Invoke-AiCommandFast
    Set-Alias -Name ai-fast -Value Invoke-AiCommandFast
} else {
    Set-Alias -Name aif -Value Invoke-AiCommand
    Set-Alias -Name ai-fast -Value Invoke-AiCommand
}

if ($env:TERMINAL_AI_PORTABLE -ne "1") {
    Register-TerminalAiKeyHandler
}
Register-TerminalAiArgumentCompleters

$exportCmdlets = @()
if ($hasFastCmdlet) {
    $exportCmdlets = @("Invoke-AiCommandFast")
}

# Export functions and aliases
Export-ModuleMember -Function @(
    "Invoke-AiCommand",
    "Invoke-AiFix",
    "New-AiScript",
    "Invoke-AiAssistant",
    "Show-TerminalAiHelp",
    "Register-TerminalAiArgumentCompleters",
    "Get-TerminalAiConfig",
    "Set-TerminalAiConfig",
    "Get-TerminalAiModels",
    "Show-TerminalAiModels",
    "Get-WindowsTerminalSettingsPath",
    "Get-TerminalAiFonts",
    "Show-TerminalAiFonts",
    "Set-TerminalAiFont",
    "Set-TerminalAiLanguage",
    "Set-TerminalAiDefaultLanguage",
    "Register-TerminalAiKeyHandler",
    "Invoke-OllamaApi",
    "Format-AiCodeOutput",
    "Show-AiAnswer",
    "Show-AiCodeCard",
    "Show-AiActionMenu",
    "Get-TerminalAiText",
    "Show-TerminalAiWelcome",
    "Get-AiSystemPrompt",
    "Clear-AiInputBuffer",
    "Get-AiMenuKeyPress",
    "Test-AiCommandAst",
    "Invoke-AiExecutionGate",
    "Protect-AiSecretData",
    "Format-AiScriptDiff",
    "Save-AiScriptFile",
    "Test-TerminalAiInstallation",
    "Invoke-AiAgent",
    "Test-AiAgentReadiness"
) -Cmdlet $exportCmdlets -Alias @(
    "ai",
    "??",
    "ai-help",
    "ai-fast",
    "aif",
    "ai-fix",
    "fix-error",
    "ai-script",
    "ai-font",
    "ai-fonts",
    "ai-lang",
    "ai-lang-permanent",
    "ai-lang-default",
    "ai-chat",
    "ai-assistant",
    "ai-doctor",
    "ai-agent",
    "Clean-AiCodeOutput"
)
