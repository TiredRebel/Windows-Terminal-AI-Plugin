using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Management.Automation;
using System.Text.RegularExpressions;
using System.Threading;

namespace TerminalAI.Aot;

[Cmdlet(VerbsLifecycle.Invoke, "AiCommandFast", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[Alias("ai-fast", "aif")]
public class InvokeAiCommandFastCmdlet : PSCmdlet
{
    private readonly CancellationTokenSource requestCancellation = new();

    protected override void StopProcessing()
    {
        requestCancellation.Cancel();
        base.StopProcessing();
    }

    [Parameter(Position = 0, Mandatory = false, ValueFromRemainingArguments = true)]
    public string[] Prompt { get; set; } = Array.Empty<string>();

    [Parameter]
    public string? Model { get; set; }

    [Alias("x", "y")]
    [Parameter]
    public SwitchParameter Execute { get; set; }

    [Alias("c")]
    [Parameter]
    public SwitchParameter Copy { get; set; }

    [Parameter]
    public SwitchParameter Explain { get; set; }

    [Alias("chat", "question")]
    [Parameter]
    public SwitchParameter Ask { get; set; }

    [Alias("Autonomous")]
    [Parameter]
    public SwitchParameter Agent { get; set; }

    [Alias("a", "Short", "UseAliases")]
    [Parameter]
    public SwitchParameter Alias { get; set; }

    [Alias("Save", "OutFile")]
    [Parameter]
    public string? SavePath { get; set; }

    [Alias("f")]
    [Parameter]
    public SwitchParameter Force { get; set; }

    [Parameter]
    public string? ConfirmInput { get; set; }

    protected override void ProcessRecord()
    {
        var cfg = AiConfig.Load();
        var isUk = cfg.Language is "uk" or "ua";
        var activeModel = string.IsNullOrWhiteSpace(Model) ? cfg.Model : Model;
        var fullPrompt = string.Join(" ", Prompt).Trim();

        // Delegate to the autonomous agent
        var isAgentPrompt = fullPrompt.StartsWith("agent ", StringComparison.OrdinalIgnoreCase) || fullPrompt.Equals("agent", StringComparison.OrdinalIgnoreCase);
        if (Agent.IsPresent || isAgentPrompt)
        {
            var agentPrompt = isAgentPrompt && fullPrompt.Length > 5 ? fullPrompt[6..].Trim() : fullPrompt;
            DelegateToAgentMode(agentPrompt, activeModel, isUk);
            return;
        }

        // Show quick help when the prompt is empty
        if (string.IsNullOrWhiteSpace(fullPrompt))
        {
            ShowHelpTopic("all", isUk);
            return;
        }

        // Support help topics
        var lowerPrompt = fullPrompt.ToLowerInvariant();
        var helpMatch = Regex.Match(fullPrompt, @"^(?:help)(?:\s+(all|shortcuts|models|examples|workflow|config))?\s*$", RegexOptions.IgnoreCase);
        if (helpMatch.Success)
        {
            var topic = helpMatch.Groups[1].Success ? helpMatch.Groups[1].Value.ToLowerInvariant() : "all";
            ShowHelpTopic(topic, isUk);
            return;
        }

        if (lowerPrompt is "/?" or "-?" or "--help" or "-h")
        {
            ShowHelpTopic("all", isUk);
            return;
        }

        if (lowerPrompt is "shortcuts")
        {
            ShowHelpTopic("shortcuts", isUk);
            return;
        }

        if (lowerPrompt is "examples")
        {
            ShowHelpTopic("examples", isUk);
            return;
        }

        if (lowerPrompt is "workflow")
        {
            ShowHelpTopic("workflow", isUk);
            return;
        }

        // System status
        if (Regex.IsMatch(lowerPrompt, @"^(?:which|what)\s+model|current\s+model|status|info"))
        {
            ShowStatus(cfg, isUk);
            return;
        }

        // List models
        if (lowerPrompt is "models" or "--models" or "-m")
        {
            ShowModels(cfg, isUk);
            return;
        }

        // Change the active model
        var modelMatch = Regex.Match(fullPrompt, @"^(?:set-model|use-model|use|model)\s+([A-Za-z0-9.:_\-\/]+)$", RegexOptions.IgnoreCase);
        if (modelMatch.Success)
        {
            var newModel = modelMatch.Groups[1].Value.Trim();
            cfg.Model = newModel;
            cfg.Save();
            var msg = $"Active model successfully changed to '{newModel}'!";
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, $"\n    ✔ {msg}\n");
            return;
        }

        // View and change language
        if (lowerPrompt is "lang" or "language" or "--lang" or "-l")
        {
            ShowLanguageInfo(cfg, isUk);
            return;
        }

        var langMatch = Regex.Match(fullPrompt, @"^(?:set-lang|lang|language)(?:\s+(?:permanent|save|default|--permanent|-p))?\s+(uk|ua|en)$", RegexOptions.IgnoreCase);
        if (!langMatch.Success)
        {
            langMatch = Regex.Match(fullPrompt, @"^(?:set-lang|lang|language)\s+(uk|ua|en)(?:\s+(?:permanent|save|default|--permanent|-p))?$", RegexOptions.IgnoreCase);
        }
        if (langMatch.Success)
        {
            var rawLang = langMatch.Groups[1].Value.ToLowerInvariant();
            var newLang = rawLang == "ua" ? "uk" : rawLang;
            cfg.Language = newLang;
            cfg.Save();
            var msg = newLang == "uk" ? "Model response language changed to Ukrainian (uk)!" : "Model response language changed to English (en)!";
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, $"\n    ✔ {msg}\n");
            return;
        }

        // Configuration
        if (lowerPrompt is "config" or "--config" or "-c")
        {
            ShowConfig(cfg);
            return;
        }

        // Manage alias mode
        if (lowerPrompt is "alias" or "aliases" or "--alias" or "-a")
        {
            var statusStr = cfg.UseAliases ? "ENABLED (gps, gci, select, ?, %)" : "DISABLED (full cmdlets)";
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n    ✦ Short aliases mode: {statusStr}");
            Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    💡 Enable:  aif alias on   |   Disable: aif alias off\n");
            return;
        }

        if (Regex.IsMatch(lowerPrompt, @"^(?:alias|aliases)\s+(?:on|1|true|enable)$") ||
            lowerPrompt is "use-aliases" or "use aliases")
        {
            cfg.UseAliases = true;
            cfg.Save();
            var msg = "PowerShell short aliases mode successfully ENABLED (defaulting to: gps, gci, select, ?, %)";
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, $"\n    ✔ {msg}\n");
            return;
        }

        if (Regex.IsMatch(lowerPrompt, @"^(?:alias|aliases)\s+(?:off|0|false|disable)$") ||
            lowerPrompt is "no-aliases" or "no aliases")
        {
            cfg.UseAliases = false;
            cfg.Save();
            var msg = "PowerShell short aliases mode DISABLED (using full cmdlet names)";
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, $"\n    ✔ {msg}\n");
            return;
        }

        // Handle an explicit text response request
        if (Ask)
        {
            ShowAnswer(cfg, activeModel, fullPrompt, isUk);
            return;
        }

        // Generate a PowerShell command
        var preferAliases = Alias.IsPresent || cfg.UseAliases;
        var naturalAliasMatch = Regex.Match(fullPrompt, @"(?:\s*[\(\[]?\s*(?:use|with)\s+alias(?:es)?\s*[\)\]]?)$", RegexOptions.IgnoreCase);
        if (naturalAliasMatch.Success)
        {
            preferAliases = true;
            fullPrompt = fullPrompt.Substring(0, naturalAliasMatch.Index).Trim();
        }

        var connectingText = $"Connecting to Ollama ({activeModel})...";
        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {connectingText}");

        var sw = Stopwatch.StartNew();
        var systemPrompt = @"You are an elite PowerShell 7 and Windows Systems engineer.
Target Environment: PowerShell 7 on Windows.
Goal: Translate the user's natural language request into a single, efficient, idiomatic, robust PowerShell command or pipeline.

Rules:
1. Output ONLY the raw executable PowerShell code without markdown, backticks, or explanations.
2. Robustness & Safety:
   - For inspecting listening ports or active connections, ALWAYS use safe pipeline filtering:
     Get-NetTCPConnection -LocalPort <port> -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue }
   - NEVER write 'Get-Process -Id (Get-NetTCPConnection ...).OwningProcess' because if no process listens on that port, -Id receives null and crashes with 'Cannot bind argument to parameter Id because it is null'!
3. Cmdlet Integrity:
   - NEVER hallucinate or invent fake cmdlets or fake aliases (e.g. NEVER use 'gci tcpconn', 'gci-tcpconn', 'netconn').
   - Specialized cmdlets like Get-NetTCPConnection, Test-NetConnection, Get-CimInstance, Get-ItemProperty have NO aliases and MUST be written in full.
4. Error Handling: Always use -ErrorAction SilentlyContinue when inspecting dynamic resources that might be missing.";

        string command;
        try
        {
            command = OllamaClient.GenerateAsync(cfg.OllamaUrl, activeModel, fullPrompt, systemPrompt, cfg.Temperature, cfg.TimeoutSeconds, isUk, requestCancellation.Token).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            var errPrefix = "[TerminalAI.AOT] Ollama error:";
            Host.UI.WriteErrorLine($"{errPrefix} {ex.Message}");
            return;
        }

        sw.Stop();
        if (string.IsNullOrWhiteSpace(command)) return;

        // Auto-correct any hallucinated patterns
        command = Regex.Replace(command, @"\b(?:gci|Get-ChildItem)\s+tcpconn\b", "Get-NetTCPConnection", RegexOptions.IgnoreCase);

        if (preferAliases)
        {
            command = PowerShellAliasConverter.ToShortAliases(command);
        }

        // Validate the AST and assess risk
        var astAnalysis = ValidateAndInspectAst(command, isUk);

        // Render the result card with latency
        RenderCard(command, activeModel, sw.ElapsedMilliseconds, isUk, astAnalysis);

        if (!astAnalysis.IsValid)
        {
            var blockedText = "    ✖ Command execution is blocked due to syntax errors.\n";
            Host.UI.WriteLine(ConsoleColor.Red, Host.UI.RawUI.BackgroundColor, blockedText);
            return;
        }

        if (Copy || cfg.AutoCopy)
        {
            CopyToClipboard(command);
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    ✔ Copied to clipboard!\n");
        }

        if (!string.IsNullOrWhiteSpace(SavePath))
        {
            var saveResult = AotScriptSafety.SaveScriptFile(SavePath, command, Force.IsPresent, ConfirmInput, this, isUk);
            WriteObject(saveResult);
            return;
        }

        if (Execute || (MyInvocation.BoundParameters.ContainsKey("WhatIf") && ((SwitchParameter)MyInvocation.BoundParameters["WhatIf"]).IsPresent))
        {
            ExecuteCommand(command, isUk, autoConfirm: true);
            return;
        }

        if (Explain)
        {
            ShowExplanation(cfg, activeModel, command, isUk);
            return;
        }

        // Action menu with alias toggling
        while (true)
        {
            RenderMenu(isUk, preferAliases);

            var action = Win32Console.ReadMenuAction();
            if (action == MenuAction.Execute)
            {
                ExecuteCommand(command, isUk);
                break;
            }
            if (action == MenuAction.Copy)
            {
                CopyToClipboard(command);
                Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    ✔ Copied to clipboard!\n");
                break;
            }
            if (action == MenuAction.Insert)
            {
                CopyToClipboard(command);
                Win32Console.DelayedPaste(200);
                Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    ✔ Command inserted into input line!\n");
                break;
            }
            if (action == MenuAction.Explain)
            {
                ShowExplanation(cfg, activeModel, command, isUk);
                break;
            }
            if (action == MenuAction.Ask)
            {
                ShowAnswer(cfg, activeModel, fullPrompt, isUk);
                break;
            }
            if (action == MenuAction.ShortAlias)
            {
                preferAliases = !preferAliases;
                command = preferAliases
                    ? PowerShellAliasConverter.ToShortAliases(command)
                    : PowerShellAliasConverter.ToFullCmdlets(command);

                astAnalysis = ValidateAndInspectAst(command, isUk);
                RenderCard(command, activeModel, 0, isUk, astAnalysis);
                continue;
            }
            if (action == MenuAction.Save)
            {
                var promptSave = "    Enter file path to save script (.ps1): ";
                Host.UI.Write(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, promptSave);
                var targetPath = Console.ReadLine()?.Trim();
                if (!string.IsNullOrWhiteSpace(targetPath))
                {
                    AotScriptSafety.SaveScriptFile(targetPath, command, Force.IsPresent, ConfirmInput, this, isUk);
                }
                else
                {
                    Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    Save canceled.\n");
                }
                break;
            }
            if (action == MenuAction.Cancel)
            {
                Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    Canceled.\n");
                break;
            }
        }
    }

    private void ExecuteCommand(string command, bool isUk, bool autoConfirm = false)
    {
        AotExecutionGate.Execute(
            caller: this,
            command: command,
            autoConfirm: autoConfirm,
            returnOutput: false,
            confirmInput: ConfirmInput,
            isUk: isUk
        );
    }

    private void ShowExplanation(AiConfig cfg, string model, string command, bool isUk)
    {
        var statusText = "Generating detailed command explanation...";
        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {statusText}");

        var langInstruction = isUk ? "Respond strictly in Ukrainian language." : "Respond in English.";
        var explainSystemPrompt = $"You are an expert technical educator explaining PowerShell commands to engineers.\n{langInstruction}\nExplain concisely:\n1. What the command does overall.\n2. Breakdown of key parameters and pipeline operators.\n3. Any potential performance or security considerations.\nFormat with clean bullet points.";

        try
        {
            var userPrompt = $"Explain this PowerShell command:\n\n{command}";
            var explanation = OllamaClient.GenerateRawAsync(cfg.OllamaUrl, model, userPrompt, explainSystemPrompt, 0.3, cfg.TimeoutSeconds, isUk, requestCancellation.Token).GetAwaiter().GetResult();
            if (!string.IsNullOrWhiteSpace(explanation))
            {
                var title = "Command Explanation";
                Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n    ✦ {title}:");
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    " + new string('─', 66));
                foreach (var line in explanation.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
                {
                    Host.UI.WriteLine(ConsoleColor.Gray, Host.UI.RawUI.BackgroundColor, $"    {line}");
                }
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    " + new string('─', 66) + "\n");
            }
        }
        catch (Exception ex)
        {
            var errPrefix = "[TerminalAI.AOT] Explanation error:";
            Host.UI.WriteErrorLine($"{errPrefix} {ex.Message}");
        }
    }

    private void ShowAnswer(AiConfig cfg, string model, string question, bool isUk)
    {
        var statusText = $"Generating answer via {model}...";
        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {statusText}");

        var langInstruction = isUk ? "Respond strictly in Ukrainian language." : "Respond in English.";
        var askSystemPrompt = $"You are Terminal AI, an expert engineering assistant built for PowerShell and Windows Terminal.\n{langInstruction}\nProvide a concise, direct, helpful explanation to the user's question.";

        try
        {
            var answer = OllamaClient.GenerateRawAsync(cfg.OllamaUrl, model, question, askSystemPrompt, 0.3, cfg.TimeoutSeconds, isUk, requestCancellation.Token).GetAwaiter().GetResult();
            if (!string.IsNullOrWhiteSpace(answer))
            {
                var cardTitle = "AI Answer";
                Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n    ✦ {cardTitle} • {model}");
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    " + new string('─', 66));
                foreach (var line in answer.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
                {
                    Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"    {line}");
                }
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    " + new string('─', 66) + "\n");
            }
        }
        catch (Exception ex)
        {
            var errPrefix = "[TerminalAI.AOT] Answer error:";
            Host.UI.WriteErrorLine($"{errPrefix} {ex.Message}");
        }
    }

    private AstAnalysisResult ValidateAndInspectAst(string command, bool isUk)
    {
        var analysis = AotCommandAstAnalyzer.Analyze(command, SessionState);
        if (!analysis.IsValid)
        {
            Host.UI.WriteLine(ConsoleColor.Red, Host.UI.RawUI.BackgroundColor, "\n    ┌─────────────────────────────────────────────────────────────┐");
            Host.UI.WriteLine(ConsoleColor.Red, Host.UI.RawUI.BackgroundColor, "    │          ✖  TERMINAL AI AOT GATE: SYNTAX ERROR              │");
            Host.UI.WriteLine(ConsoleColor.Red, Host.UI.RawUI.BackgroundColor, "    └─────────────────────────────────────────────────────────────┘");
            var blockMsg = "    Command execution BLOCKED due to syntax errors:";
            Host.UI.WriteLine(ConsoleColor.DarkYellow, Host.UI.RawUI.BackgroundColor, blockMsg);
            foreach (var err in analysis.ParseErrors)
            {
                int line = err.Extent?.StartLineNumber ?? 1;
                int col = err.Extent?.StartColumnNumber ?? 1;
                Host.UI.WriteLine(ConsoleColor.Red, Host.UI.RawUI.BackgroundColor, $"      • Line {line}, Col {col}: {err.Message}");
            }
            Host.UI.WriteLine("");
            return analysis;
        }

        foreach (var cmd in analysis.Commands)
        {
            if (cmd.CommandType == "Unknown" && Regex.IsMatch(cmd.CommandName, @"^[A-Za-z]+-[A-Za-z0-9]+$"))
            {
                var warnTitle = "Warning";
                var warnMsg = $"Command not found in PowerShell session: '{cmd.CommandName}'";
                var warnHint = "(Likely model hallucinated a cmdlet)";

                Host.UI.WriteLine(ConsoleColor.DarkYellow, Host.UI.RawUI.BackgroundColor, $"    ⚠ [{warnTitle}] {warnMsg}");
                Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, $"      {warnHint}\n");
            }
            if (cmd.InvalidParameters.Count > 0)
            {
                var warnTitle = "Invalid Parameters";
                var invalidList = string.Join(", -", cmd.InvalidParameters);
                var warnMsg = $"Unknown parameters detected for '{cmd.CommandName}': -{invalidList}";
                Host.UI.WriteLine(ConsoleColor.DarkYellow, Host.UI.RawUI.BackgroundColor, $"    ⚠ [{warnTitle}] {warnMsg}\n");
            }
        }

        return analysis;
    }

    private void RenderHelpLine(string text, ConsoleColor color, int boxWidth = 68)
    {
        int maxTextLen = Math.Max(0, boxWidth - 2);
        if (text.Length > maxTextLen)
        {
            text = text.Substring(0, maxTextLen);
        }
        var pad = boxWidth - 2 - text.Length;
        if (pad < 0) pad = 0;
        Host.UI.Write(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │ ");
        Host.UI.Write(color, Host.UI.RawUI.BackgroundColor, text);
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, new string(' ', pad) + " │");
    }

    private void ShowHelpTopic(string topic, bool isUk)
    {
        int bw = Math.Min(68, Math.Max(40, GetTerminalWidth() - 8));
        Host.UI.WriteLine("");
        switch (topic.ToLowerInvariant())
        {
            case "shortcuts":
            {
                var title = "Shortcuts, Aliases & Keybindings Guide";
                Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"    ✦ Terminal AI Fast (AOT) • {title}");
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭" + new string('─', bw) + "╮");
                RenderHelpLine("", ConsoleColor.White, bw);
                {
                    RenderHelpLine("1. PRIMARY ALIASES:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("   aif <prompt>   Compiled managed .NET 10 helper module", ConsoleColor.White, bw);
                    RenderHelpLine("   ai <prompt>    Standard PowerShell module", ConsoleColor.White, bw);
                    RenderHelpLine("   ?? <prompt>    Short alias for command generation", ConsoleColor.White, bw);
                    RenderHelpLine("   F2             Inline PSReadLine generation directly in prompt", ConsoleColor.Yellow, bw);
                    RenderHelpLine("   ai-fix         Diagnose and fix the last failed command in session", ConsoleColor.White, bw);
                    RenderHelpLine("   ai-script      Generate complex multi-step .ps1 automation scripts", ConsoleColor.White, bw);
                    RenderHelpLine("   ai-chat        Interactive terminal assistant with Tab completion", ConsoleColor.White, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("2. SHORT EXECUTION FLAGS:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("   -x, -y         Execute command immediately without confirmation", ConsoleColor.Yellow, bw);
                    RenderHelpLine("   -c             Copy generated command directly to clipboard", ConsoleColor.Yellow, bw);
                    RenderHelpLine("   -SavePath      Save generated script directly to file with diff preview", ConsoleColor.DarkGreen, bw);
                    RenderHelpLine("   -Explain       Generate comprehensive educational breakdown of code", ConsoleColor.Magenta, bw);
                    RenderHelpLine("   -Ask, -chat    Get educational text response instead of script", ConsoleColor.Blue, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("3. INTERACTIVE MENU KEYPRESSES (after generation):", ConsoleColor.Cyan, bw);
                    RenderHelpLine("   [Enter]        Execute command in current session", ConsoleColor.Green, bw);
                    RenderHelpLine("   [C] / [c]      Copy command to system clipboard", ConsoleColor.Yellow, bw);
                    RenderHelpLine("   [I] / [i]      Insert command into prompt line for manual editing", ConsoleColor.Cyan, bw);
                    RenderHelpLine("   [S] / [s]      Toggle between short aliases and full cmdlets", ConsoleColor.DarkYellow, bw);
                    RenderHelpLine("   [X] / [x]      Explain command syntax, flags, and safety", ConsoleColor.Magenta, bw);
                    RenderHelpLine("   [A] / [a]      Provide full conceptual explanation", ConsoleColor.Blue, bw);
                    RenderHelpLine("   [W] / [w]      Save script to file with safe unified diff preview", ConsoleColor.DarkGreen, bw);
                    RenderHelpLine("   [Esc]          Cancel and return to prompt", ConsoleColor.DarkGray, bw);
                }
                RenderHelpLine("", ConsoleColor.White, bw);
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰" + new string('─', bw) + "╯\n");
                break;
            }

            case "models":
            {
                var title = "Ollama Coding Models Guide";
                Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"    ✦ Terminal AI Fast (AOT) • {title}");
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭" + new string('─', bw) + "╮");
                RenderHelpLine("", ConsoleColor.White, bw);
                {
                    RenderHelpLine("RECOMMENDED LOCAL CODING MODELS FOR POWERSHELL:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  • qwen2.5-coder:7b   [~4.4GB VRAM] Top choice for PowerShell 7 pipelines & CLI", ConsoleColor.Green, bw);
                    RenderHelpLine("  • granite4.2:8b      [~5.0GB VRAM] Enterprise IBM model, great for sysadmin tasks", ConsoleColor.White, bw);
                    RenderHelpLine("  • deepseek-coder:6.7b[~4.0GB VRAM] Fast, precise code generation", ConsoleColor.White, bw);
                    RenderHelpLine("  • qwen2.5-coder:1.5b [~1.2GB VRAM] Ultra-lightweight for CPU laptops", ConsoleColor.Yellow, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("MODEL MANAGEMENT COMMANDS:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  aif models              View list of installed models & active marker", ConsoleColor.White, bw);
                    RenderHelpLine("  aif model <name>        Switch active model", ConsoleColor.White, bw);
                    RenderHelpLine("  ollama pull <name>      Download model (e.g. ollama pull qwen2.5-coder:7b)", ConsoleColor.DarkGray, bw);
                    RenderHelpLine("  ollama list             List all models downloaded locally", ConsoleColor.DarkGray, bw);
                }
                RenderHelpLine("", ConsoleColor.White, bw);
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰" + new string('─', bw) + "╯\n");
                break;
            }

            case "examples":
            {
                var title = "Practical DevOps & Admin Examples";
                Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"    ✦ Terminal AI Fast (AOT) • {title}");
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭" + new string('─', bw) + "╮");
                RenderHelpLine("", ConsoleColor.White, bw);
                {
                    RenderHelpLine("FILES & DIRECTORIES:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  aif 'find all .log files larger than 50MB modified in last 2 days'", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif 'calculate total size of C:\\Temp directory in gigabytes'", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif 'delete empty folders recursively' -Explain", ConsoleColor.Green, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("PROCESSES & DIAGNOSTICS:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  aif 'show top 5 processes by working set memory in MB'", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif 'find process listening on port 8080'", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif 'terminate all hung node processes' -x", ConsoleColor.Green, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("NETWORKING & SYSTEMS:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  aif 'test TCP connection to 8.8.8.8 on port 53'", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif 'display default gateway and active DNS servers'", ConsoleColor.Green, bw);
                    RenderHelpLine("  ai-fix  (auto-diagnose and fix the last error)", ConsoleColor.Yellow, bw);
                }
                RenderHelpLine("", ConsoleColor.White, bw);
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰" + new string('─', bw) + "╯\n");
                break;
            }

            case "workflow":
            {
                var title = "Interactive Workflow Guide";
                Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"    ✦ Terminal AI Fast (AOT) • {title}");
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭" + new string('─', bw) + "╮");
                RenderHelpLine("", ConsoleColor.White, bw);
                {
                    RenderHelpLine("1. INLINE GENERATION (Fastest method):", ConsoleColor.Cyan, bw);
                    RenderHelpLine("   • Type any goal in plain English directly at the terminal prompt", ConsoleColor.White, bw);
                    RenderHelpLine("   • Press F2 (or Ctrl+Space) -> prompt is replaced with valid code", ConsoleColor.Yellow, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("2. INTERACTIVE ACTION MENU (Safe verification):", ConsoleColor.Cyan, bw);
                    RenderHelpLine("   • Run: aif 'your task description'", ConsoleColor.White, bw);
                    RenderHelpLine("   • Press [Enter] to run, [C] to copy to clipboard,", ConsoleColor.White, bw);
                    RenderHelpLine("     [I] to insert into line for editing, [X] to explain syntax,", ConsoleColor.White, bw);
                    RenderHelpLine("     [A] for conceptual answer, or [Esc] to dismiss.", ConsoleColor.White, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("3. AUTOMATED ERROR RECOVERY:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("   • When any terminal command fails, immediately run: ai-fix", ConsoleColor.Yellow, bw);
                    RenderHelpLine("   • AI analyzes the error stream and suggests a fix.", ConsoleColor.White, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("4. PRODUCTION SCRIPTS & CHAT ASSISTANT:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("   • Multi-step scripts: ai-script 'backup IIS logs with compression'", ConsoleColor.White, bw);
                    RenderHelpLine("   • Multi-turn assistant: ai-chat (supports /help, /model, /clear)", ConsoleColor.White, bw);
                }
                RenderHelpLine("", ConsoleColor.White, bw);
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰" + new string('─', bw) + "╯\n");
                break;
            }

            case "config":
            {
                var title = "Configuration Settings Guide";
                Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"    ✦ Terminal AI Fast (AOT) • {title}");
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭" + new string('─', bw) + "╮");
                RenderHelpLine("", ConsoleColor.White, bw);
                {
                    RenderHelpLine("CONFIGURATION FILE:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  Location: ~/.terminalai/config.json", ConsoleColor.White, bw);
                    RenderHelpLine("  View:     aif config   or   ai config", ConsoleColor.Green, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("KEY SETTINGS:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  • Model        Active coding model (default: qwen2.5-coder:7b)", ConsoleColor.White, bw);
                    RenderHelpLine("  • OllamaUrl    Ollama server endpoint (http://localhost:11434)", ConsoleColor.White, bw);
                    RenderHelpLine("  • Language     Model response language (en or uk)", ConsoleColor.White, bw);
                    RenderHelpLine("  • Temperature  Generation determinism (0.2 for strict code)", ConsoleColor.White, bw);
                    RenderHelpLine("  • AutoCopy     Auto-copy generated command to clipboard", ConsoleColor.White, bw);
                    RenderHelpLine("  • Font         Windows Terminal font (e.g. Cascadia Code NF)", ConsoleColor.White, bw);
                    RenderHelpLine("  • HotkeyChord  Inline shortcut chord (F2 or Ctrl+Space)", ConsoleColor.White, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("QUICK CONFIGURATION COMMANDS:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  aif model <name>        Switch active Ollama model", ConsoleColor.Yellow, bw);
                    RenderHelpLine("  aif lang en | uk        Switch model response language", ConsoleColor.Yellow, bw);
                    RenderHelpLine("  ai font <name> [size]   Configure Windows Terminal font", ConsoleColor.Yellow, bw);
                }
                RenderHelpLine("", ConsoleColor.White, bw);
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰" + new string('─', bw) + "╯\n");
                break;
            }

            default:
            {
                // Complete help
                var title = "Complete Reference & Commands Map";
                Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"    ✦ Terminal AI Fast (AOT) • {title}");
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭" + new string('─', bw) + "╮");
                RenderHelpLine("", ConsoleColor.White, bw);
                {
                    RenderHelpLine("AVAILABLE COMMANDS:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  aif, ai-fast      Fast native C# binary module (recommended)", ConsoleColor.White, bw);
                    RenderHelpLine("  ai, ??            Classic PowerShell module with latency timing", ConsoleColor.White, bw);
                    RenderHelpLine("  ai-fix            Diagnose and fix the last failed command in session", ConsoleColor.White, bw);
                    RenderHelpLine("  ai-script         Generate production-ready multi-line .ps1 scripts", ConsoleColor.White, bw);
                    RenderHelpLine("  ai-chat           Interactive terminal assistant with history", ConsoleColor.White, bw);
                    RenderHelpLine("  F2                Inline generation directly in PSReadLine prompt", ConsoleColor.Yellow, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("DETAILED TOPICS:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  aif help shortcuts Full cheat-sheet of keybindings, flags, and aliases", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif help models    VRAM requirements & coding LLM recommendations", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif help examples  Practical sysadmin & automation pipeline examples", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif help workflow  Workflow guide for menus, inline, and error fixing", ConsoleColor.Green, bw);
                    RenderHelpLine("  aif help config    Configuration guide (~/.terminalai/config.json)", ConsoleColor.Green, bw);
                    RenderHelpLine("", ConsoleColor.White, bw);
                    RenderHelpLine("NATIVE POWERSHELL HELP:", ConsoleColor.Cyan, bw);
                    RenderHelpLine("  Get-Help aif -Full        Full MAML manual with parameters and types", ConsoleColor.DarkGray, bw);
                    RenderHelpLine("  Get-Help aif -Examples    Real-world usage examples", ConsoleColor.DarkGray, bw);
                }
                RenderHelpLine("", ConsoleColor.White, bw);
                Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰" + new string('─', bw) + "╯\n");
                break;
            }
        }
    }


    private void ShowStatus(AiConfig cfg, bool isUk)
    {
        var title = "System Information";
        var lblModel = "Active Model:";
        var lblFont = "Terminal Font:";
        var lblServer = "Local Server:";
        var lblHotkey = "Quick Inline:";
        var lblLang = "Model Response Language:";
        var hintModel = "Change model:  ai-fast model <name>";
        var hintLang = "Change lang:   ai-fast lang en | uk";

        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n    ✦ Terminal AI Fast (AOT) • {title}");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭──────────────────────────────────────────────────────────────────╮");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");

        RenderRow(lblModel, cfg.Model, ConsoleColor.Green);
        RenderRow(lblFont, string.IsNullOrEmpty(cfg.Font) ? "Default" : cfg.Font, ConsoleColor.Cyan);
        RenderRow(lblServer, cfg.OllamaUrl, ConsoleColor.White);
        RenderRow(lblHotkey, $"{cfg.HotkeyChord} / F2", ConsoleColor.Yellow);
        RenderRow(lblLang, cfg.Language == "en" ? "en (English)" : "uk (Ukrainian)", ConsoleColor.White);

        var lblAliases = "Command Aliases:";
        var valAliases = cfg.UseAliases ? "Enabled (short)" : "Disabled (full)";
        RenderRow(lblAliases, valAliases, cfg.UseAliases ? ConsoleColor.Yellow : ConsoleColor.DarkGray);

        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰──────────────────────────────────────────────────────────────────╯\n");

        var hintAlias = "Toggle aliases:   ai-fast alias on | off";
        Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, $"    💡 {hintModel}");
        Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, $"    💡 {hintLang}");
        Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, $"    💡 {hintAlias}\n");
    }

    private void RenderRow(string label, string value, ConsoleColor valueColor)
    {
        if (label.Length > 22) label = label.Substring(0, 22);
        if (value.Length > 38) value = value.Substring(0, 35) + "...";

        Host.UI.Write(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │   ");
        Host.UI.Write(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, string.Format("{0,-22}", label));
        Host.UI.Write(valueColor, Host.UI.RawUI.BackgroundColor, string.Format("{0,-38}", value));
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "   │");
    }

    private void ShowModels(AiConfig cfg, bool isUk)
    {
        try
        {
            var models = OllamaClient.GetModelsAsync(cfg.OllamaUrl, 15, isUk, requestCancellation.Token).GetAwaiter().GetResult();
            if (models.Count == 0)
            {
                var msg = " [TerminalAI] No models found or Ollama is not running.";
                Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, $"\n   {msg}\n");
                return;
            }

            var title = $"Installed Ollama models (active: {cfg.Model}):";
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {title}\n");

            var colCur = "Active";
            var colName = "Name";
            var colSize = "Size (GB)";
            var colUpd = "Updated";

            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, string.Format("  {0,-10} {1,-32} {2,-14} {3,-20}", colCur, colName, colSize, colUpd));
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "  " + new string('─', 78));

            foreach (var m in models)
            {
                var isCurrent = m.Name.Equals(cfg.Model, StringComparison.OrdinalIgnoreCase);
                var curMark = isCurrent ? "  ★ " : "    ";
                var curColor = isCurrent ? ConsoleColor.Green : ConsoleColor.White;
                var sizeGb = (m.Size / 1024.0 / 1024.0 / 1024.0).ToString("F1");
                var upd = m.ModifiedAt.HasValue ? m.ModifiedAt.Value.ToString("yyyy-MM-dd HH:mm") : "-";

                Host.UI.Write(isCurrent ? ConsoleColor.Yellow : ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, string.Format("  {0,-10}", curMark));
                Host.UI.Write(curColor, Host.UI.RawUI.BackgroundColor, string.Format("{0,-32} ", m.Name));
                Host.UI.Write(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, string.Format("{0,-14} ", sizeGb));
                Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, string.Format("{0,-20}", upd));
            }
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "  " + new string('─', 78) + "\n");
        }
        catch (Exception ex)
        {
            var errPrefix = "[TerminalAI.AOT] Error retrieving models list:";
            Host.UI.WriteErrorLine($"{errPrefix} {ex.Message}");
        }
    }

    private void ShowLanguageInfo(AiConfig cfg, bool isUk)
    {
        Host.UI.WriteLine("");
        if (cfg.Language == "en")
        {
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "    ✦ Current model response language: en (English)");
            Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    💡 Switch model response language:  ai-fast lang uk  |  ai-fast lang en\n");
        }
        else
        {
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "    ✦ Current model response language: uk (Ukrainian)");
            Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    💡 Switch model response language:  ai-fast lang en  |  ai-fast lang uk\n");
        }
    }

    private void ShowConfig(AiConfig cfg)
    {
        try
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var path = Path.Combine(home, ".terminal-ai", "config.json");
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ Terminal AI Config ({path}):\n");
            var json = System.Text.Json.JsonSerializer.Serialize(cfg, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            Host.UI.WriteLine(ConsoleColor.Gray, Host.UI.RawUI.BackgroundColor, json + "\n");
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[InvokeAiCommandFast] ShowConfig error: {ex.Message}");
        }
    }

    private int GetTerminalWidth()
    {
        try
        {
            if (Host?.UI?.RawUI?.WindowSize.Width > 20)
                return Host.UI.RawUI.WindowSize.Width;
            if (Console.WindowWidth > 20)
                return Console.WindowWidth;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[InvokeAiCommandFast] GetTerminalWidth error: {ex.Message}");
        }
        return 80;
    }

    private static List<string> WrapCode(string code, int maxWidth)
    {
        var result = new List<string>();
        if (string.IsNullOrEmpty(code))
        {
            result.Add(string.Empty);
            return result;
        }

        if (maxWidth < 20) maxWidth = 20;

        var rawLines = code.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
        foreach (var rawLine in rawLines)
        {
            if (rawLine.Length <= maxWidth)
            {
                result.Add(rawLine);
                continue;
            }

            var rem = rawLine;
            while (rem.Length > maxWidth)
            {
                int breakIdx = -1;
                int searchStart = Math.Max(0, maxWidth - 24);
                for (int i = maxWidth; i >= searchStart; i--)
                {
                    if (rem[i] == ' ' || rem[i] == '|')
                    {
                        breakIdx = (rem[i] == '|') ? i : i + 1;
                        break;
                    }
                }

                if (breakIdx <= 0 || breakIdx > maxWidth)
                {
                    breakIdx = maxWidth;
                }

                result.Add(rem.Substring(0, breakIdx).TrimEnd());
                rem = rem.Substring(breakIdx).TrimStart();
            }

            if (rem.Length > 0)
            {
                result.Add(rem);
            }
        }

        return result;
    }

    private void RenderCard(string code, string model, long elapsedMs, bool isUk, AstAnalysisResult? analysis = null)
    {
        bool hasSecret = AotSecretSanitizer.ContainsSecret(code);
        string displayCode = hasSecret ? AotSecretSanitizer.Sanitize(code) : code;

        var latency = elapsedMs > 0 ? $"{elapsedMs}ms" : "0ms";
        var title = $"AI Command (AOT • {latency})";

        if (hasSecret)
        {
            var secWarn = "    ⚠ [SECURITY] Sensitive data detected: automatically masked for display.";
            Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, secWarn);
        }

        int termWidth = GetTerminalWidth();
        int maxAllowedInner = Math.Max(30, termWidth - 8);
        int maxCodeWidth = maxAllowedInner - 4;

        var wrappedLines = WrapCode(displayCode, maxCodeWidth);
        int maxLineLen = 0;
        foreach (var l in wrappedLines)
        {
            if (l.Length > maxLineLen) maxLineLen = l.Length;
        }

        int minBoxInner = Math.Min(54, maxAllowedInner);
        int boxInnerWidth = Math.Min(maxAllowedInner, Math.Max(minBoxInner, maxLineLen + 4));

        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n    ✦ {title} • {model}");

        if (analysis != null)
        {
            RenderSecurityBadges(analysis, isUk);
        }

        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭" + new string('─', boxInnerWidth) + "╮");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │" + new string(' ', boxInnerWidth) + "│");

        foreach (var line in wrappedLines)
        {
            var pad = boxInnerWidth - 4 - line.Length;
            if (pad < 0) pad = 0;
            Host.UI.Write(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │  ");
            Host.UI.Write(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, line);
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, new string(' ', pad) + "  │");
        }

        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │" + new string(' ', boxInnerWidth) + "│");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰" + new string('─', boxInnerWidth) + "╯");

        if (analysis != null)
        {
            RenderSecurityFootnotes(analysis, code, isUk);
        }
        Host.UI.WriteLine();
    }

    private void RenderSecurityBadges(AstAnalysisResult analysis, bool isUk)
    {
        ConsoleColor riskColor = analysis.OverallRisk switch
        {
            CommandRiskLevel.Critical => ConsoleColor.Red,
            CommandRiskLevel.High => ConsoleColor.Red,
            CommandRiskLevel.Medium => ConsoleColor.Yellow,
            _ => ConsoleColor.Green
        };

        ConsoleColor catColor = analysis.OverallCategory switch
        {
            CommandCategory.ReadOnly => ConsoleColor.Cyan,
            CommandCategory.Deletion or CommandCategory.DiskOrPartition => ConsoleColor.Red,
            CommandCategory.Registry or CommandCategory.NetworkChange or CommandCategory.ServiceOrProcess => ConsoleColor.Yellow,
            _ => ConsoleColor.White
        };

        Host.UI.Write(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "      [");
        Host.UI.Write(catColor, Host.UI.RawUI.BackgroundColor, analysis.OverallCategory.ToString());
        Host.UI.Write(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "]  [Risk: ");
        Host.UI.Write(riskColor, Host.UI.RawUI.BackgroundColor, analysis.OverallRisk.ToString());
        Host.UI.Write(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "]  [WhatIf: ");
        Host.UI.Write(analysis.CanPreview ? ConsoleColor.Cyan : ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, analysis.CanPreview ? "Supported" : "Unavailable");
        Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "]");
    }

    private void RenderSecurityFootnotes(AstAnalysisResult analysis, string command, bool isUk)
    {
        if (analysis.Targets != null && analysis.Targets.Count > 0 && !(analysis.Targets.Count == 1 && analysis.Targets[0] == "Unknown target"))
        {
            var targetsDisplay = string.Join(", ", analysis.Targets.Select(AotSecretSanitizer.Sanitize));
            var tLabel = "Targets";
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, $"    🎯 {tLabel}: {targetsDisplay}");
        }

        if (RequiresElevation(analysis, command) && !IsProcessElevated())
        {
            var elevWarn = "    ⚠ Requires Administrator elevation (current session is not elevated).";
            Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, elevWarn);
        }
    }

    private static bool RequiresElevation(AstAnalysisResult analysis, string command)
    {
        if (analysis.OverallCategory is CommandCategory.DiskOrPartition or CommandCategory.NetworkChange)
            return true;

        if (analysis.OverallCategory == CommandCategory.Registry &&
            Regex.IsMatch(command, @"(?i)\b(?:HKLM:|Registry::HKEY_LOCAL_MACHINE)"))
            return true;

        if (analysis.Commands != null && analysis.Commands.Any(c =>
            c.Category == CommandCategory.ServiceOrProcess &&
            Regex.IsMatch(c.OriginalName, @"(?i)(?:-Service\b)")))
            return true;

        return false;
    }

    private static bool IsProcessElevated()
    {
        if (OperatingSystem.IsWindows())
        {
            try
            {
                using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
                var principal = new System.Security.Principal.WindowsPrincipal(identity);
                return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[InvokeAiCommandFast] IsProcessElevated check error: {ex.Message}");
            }
        }
        return false;
    }

    private void RenderMenu(bool isUk, bool preferAliases)
    {
        var tEnter = "Execute";
        var tCopy = "Copy";
        var tInsert = "Insert";
        var tAlias = preferAliases ? "Full" : "Alias";
        var tExplain = "Explain";
        var tAsk = "Text";
        var tSave = "Save";
        var tCancel = "Cancel";

        int termWidth = GetTerminalWidth();
        if (termWidth >= 110)
        {
            Host.UI.Write(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    [Enter] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tEnter}   ");
            Host.UI.Write(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, "[C] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tCopy}   ");
            Host.UI.Write(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "[I] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tInsert}   ");
            Host.UI.Write(ConsoleColor.DarkYellow, Host.UI.RawUI.BackgroundColor, "[S] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tAlias}   ");
            Host.UI.Write(ConsoleColor.Magenta, Host.UI.RawUI.BackgroundColor, "[X] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tExplain}   ");
            Host.UI.Write(ConsoleColor.Blue, Host.UI.RawUI.BackgroundColor, "[A] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tAsk}   ");
            Host.UI.Write(ConsoleColor.DarkGreen, Host.UI.RawUI.BackgroundColor, "[W] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tSave}   ");
            Host.UI.Write(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "[Esc] ");
            Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tCancel}\n");
        }
        else
        {
            Host.UI.Write(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    [Enter] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tEnter,-14} ");
            Host.UI.Write(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, "[C] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tCopy,-14} ");
            Host.UI.Write(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "[I] ");
            Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, tInsert);

            Host.UI.Write(ConsoleColor.DarkYellow, Host.UI.RawUI.BackgroundColor, "    [S]     ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tAlias,-14} ");
            Host.UI.Write(ConsoleColor.Magenta, Host.UI.RawUI.BackgroundColor, "[X] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tExplain,-14} ");
            Host.UI.Write(ConsoleColor.Blue, Host.UI.RawUI.BackgroundColor, "[A] ");
            Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tAsk,-8} ");
            Host.UI.Write(ConsoleColor.DarkGreen, Host.UI.RawUI.BackgroundColor, "[W] ");
            Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tSave,-10}");

            Host.UI.Write(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    [Esc]   ");
            Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tCancel}\n");
        }
    }

    private void CopyToClipboard(string text)
    {
        try
        {
            var sanitized = AotSecretSanitizer.Sanitize(text);
            AotClipboard.SetText(sanitized, SessionState);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[InvokeAiCommandFast] CopyToClipboard error: {ex.Message}");
        }
    }

    private void DelegateToAgentMode(string agentPrompt, string activeModel, bool isUk)
    {
        if (string.IsNullOrWhiteSpace(agentPrompt) || agentPrompt.Equals("help", StringComparison.OrdinalIgnoreCase) || agentPrompt.Equals("--help", StringComparison.OrdinalIgnoreCase))
        {
            var title = "Autonomous Agent Mode (Claude Code + Ollama)";
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ Terminal AI • {title}");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "  " + new string('─', 70));
            {
                Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, "    Command `aif -Agent <prompt>` safely delegates autonomous tasks to Claude Code,");
                Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, "    connected to your local Ollama model via the Anthropic Messages API protocol.");
                Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    Example: aif -Agent 'audit repository for unreferenced scripts and create summary'");
            }
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "  " + new string('─', 70) + "\n");
            return;
        }

        CommandInfo? agentCmd = null;
        try
        {
            agentCmd = SessionState?.InvokeCommand?.GetCommand("Invoke-AiAgent", CommandTypes.Function | CommandTypes.Cmdlet);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[InvokeAiCommandFast] Agent check error: {ex.Message}");
        }

        if (agentCmd != null)
        {
            using var ps = PowerShell.Create(RunspaceMode.CurrentRunspace);
            ps.AddCommand("Invoke-AiAgent");
            if (!string.IsNullOrWhiteSpace(agentPrompt))
            {
                ps.AddParameter("Prompt", agentPrompt);
            }
            if (!string.IsNullOrWhiteSpace(activeModel))
            {
                ps.AddParameter("Model", activeModel);
            }
            var results = ps.Invoke();
            foreach (var item in results)
            {
                WriteObject(item);
            }
        }
        else
        {
            var warnTitle = "Agent Mode unavailable in current session";
            var warnHint = "To use autonomous agent mode, load the primary module: Import-Module TerminalAI";
            Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, $"\n    ⚠ [{warnTitle}]");
            Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, $"      {warnHint}\n");
        }
    }

}
