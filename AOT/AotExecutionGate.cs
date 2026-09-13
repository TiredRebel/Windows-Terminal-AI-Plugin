using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Text.RegularExpressions;

namespace TerminalAI.Aot;

public record ExecutionGateResult(
    bool Executed,
    string Status,
    string Command,
    AstAnalysisResult? Analysis,
    object? Output
);

public static class AotExecutionGate
{
    public static ExecutionGateResult Execute(
        PSCmdlet caller,
        string command,
        bool autoConfirm = false,
        bool returnOutput = false,
        string? confirmInput = null,
        bool isUk = false,
        bool preview = false)
    {
        bool isWhatIf = preview;
        if (caller?.MyInvocation?.BoundParameters != null &&
            caller.MyInvocation.BoundParameters.ContainsKey("WhatIf"))
        {
            var whatIfVal = caller.MyInvocation.BoundParameters["WhatIf"];
            if (whatIfVal is SwitchParameter sw && sw.IsPresent)
            {
                isWhatIf = true;
            }
            else if (whatIfVal is bool b && b)
            {
                isWhatIf = true;
            }
        }

        return ExecuteCore(
            command: command,
            sessionState: caller?.SessionState,
            ui: caller?.Host?.UI,
            autoConfirm: autoConfirm,
            returnOutput: returnOutput,
            confirmInput: confirmInput,
            isUk: isUk,
            isWhatIf: isWhatIf
        );
    }

    public static ExecutionGateResult ExecuteCore(
        string command,
        SessionState? sessionState = null,
        PSHostUserInterface? ui = null,
        bool autoConfirm = false,
        bool returnOutput = false,
        string? confirmInput = null,
        bool isUk = false,
        bool isWhatIf = false)
    {
        if (string.IsNullOrWhiteSpace(command))
        {
            return new ExecutionGateResult(false, "EmptyCommand", command ?? string.Empty, null, null);
        }

        // 1. AST Analysis
        var analysis = AotCommandAstAnalyzer.Analyze(command, sessionState);

        // 2. Syntax validation
        if (!analysis.IsValid || (analysis.ParseErrors != null && analysis.ParseErrors.Count > 0))
        {
            RenderSyntaxError(ui, analysis, isUk);
            return new ExecutionGateResult(false, "SyntaxError", command, analysis, null);
        }

        // 3. WhatIf / Preview Mode
        if (isWhatIf)
        {
            if (!analysis.CanPreview)
            {
                RenderPreviewUnavailable(ui, analysis, isUk);
                return new ExecutionGateResult(false, "PreviewUnavailable", command, analysis, null);
            }

            WriteColorLine(ui, ConsoleColor.Cyan,
                "    🔍 [WhatIf Preview] Running command in safe simulation mode...");

            try
            {
                var whatIfScript = $"$WhatIfPreference = $true; $ErrorActionPreference = 'Continue'; . {{ {command} }}";
                if (sessionState != null)
                {
                    if (returnOutput)
                    {
                        var outList = sessionState.InvokeCommand.InvokeScript(whatIfScript);
                        return new ExecutionGateResult(true, "Previewed", command, analysis, outList);
                    }
                    else
                    {
                        sessionState.InvokeCommand.InvokeScript(whatIfScript + " | Out-Default");
                        return new ExecutionGateResult(true, "Previewed", command, analysis, null);
                    }
                }
                else
                {
                    using var ps = PowerShell.Create();
                    ps.AddScript(whatIfScript);
                    if (!returnOutput) ps.AddCommand("Out-Default");
                    var res = ps.Invoke();
                    return new ExecutionGateResult(true, "Previewed", command, analysis, returnOutput ? res : null);
                }
            }
            catch (Exception ex)
            {
                WriteColorLine(ui, ConsoleColor.Red, $"[WhatIf Error] {ex.Message}");
                return new ExecutionGateResult(false, "ExecutionError", command, analysis, ex.Message);
            }
        }

        // 4. Security Check & Confirmation
        bool isDangerous = analysis.RequiresConfirmation ||
                           analysis.OverallRisk is CommandRiskLevel.High or CommandRiskLevel.Critical ||
                           analysis.OverallCategory is CommandCategory.DynamicOrUnknown;

        bool needsPrompt = isDangerous || !autoConfirm;

        if (needsPrompt)
        {
            RenderSecurityGateCard(ui, command, analysis, isUk);

            string promptDefault = (analysis.OverallRisk is CommandRiskLevel.High or CommandRiskLevel.Critical) ? "y/N" : "Y/n";
            string promptText = $"    Execute this command? [{promptDefault}]: ";

            string? response = confirmInput;
            if (response == null)
            {
                bool isInteractive = Environment.UserInteractive && !Console.IsInputRedirected;
                if (!isInteractive)
                {
                    WriteColorLine(ui, ConsoleColor.Red,
                        "    ✖ Non-interactive host detected. Unconfirmed command blocked.");
                    return new ExecutionGateResult(false, "BlockedNonInteractive", command, analysis, null);
                }

                if (ui != null)
                {
                    ui.Write(ConsoleColor.White, ConsoleColor.Black, promptText);
                }
                else
                {
                    Console.Write(promptText);
                }

                response = Console.ReadLine() ?? string.Empty;
            }

            bool confirmed = false;
            var trimmedResponse = response.Trim();
            if (analysis.OverallRisk is CommandRiskLevel.High or CommandRiskLevel.Critical)
            {
                if (Regex.IsMatch(trimmedResponse, @"^(?:y|yes)$", RegexOptions.IgnoreCase))
                {
                    confirmed = true;
                }
            }
            else
            {
                if (string.IsNullOrWhiteSpace(trimmedResponse) || Regex.IsMatch(trimmedResponse, @"^(?:y|yes)$", RegexOptions.IgnoreCase))
                {
                    confirmed = true;
                }
            }

            if (!confirmed)
            {
                WriteColorLine(ui, ConsoleColor.DarkGray,
                    "    ✖ Execution canceled by user.");
                return new ExecutionGateResult(false, "Denied", command, analysis, null);
            }
        }

        // 5. Safe Execution
        try
        {
            WriteColorLine(ui, ConsoleColor.Yellow,
                "    ▶ Executing command:\n");

            if (sessionState != null)
            {
                if (returnOutput)
                {
                    var output = sessionState.InvokeCommand.InvokeScript(command);
                    return new ExecutionGateResult(true, "Executed", command, analysis, output);
                }
                else
                {
                    var script = $". {{ {command} }} | Out-Default";
                    sessionState.InvokeCommand.InvokeScript(script);
                    return new ExecutionGateResult(true, "Executed", command, analysis, null);
                }
            }
            else
            {
                using var ps = PowerShell.Create();
                ps.AddScript(command);
                if (!returnOutput) ps.AddCommand("Out-Default");
                var output = ps.Invoke();
                return new ExecutionGateResult(true, "Executed", command, analysis, returnOutput ? output : null);
            }
        }
        catch (Exception ex)
        {
            WriteColorLine(ui, ConsoleColor.Red, $"    ✖ {ex.Message}\n");
            return new ExecutionGateResult(false, "ExecutionError", command, analysis, ex.Message);
        }
    }

    private static void RenderSyntaxError(PSHostUserInterface? ui, AstAnalysisResult analysis, bool isUk)
    {
        WriteColorLine(ui, ConsoleColor.Red, "");
        WriteColorLine(ui, ConsoleColor.Red, "    ┌─────────────────────────────────────────────────────────────┐");
        WriteColorLine(ui, ConsoleColor.Red, "    │          ✖  TERMINAL AI SECURITY GATE: SYNTAX ERROR         │");
        WriteColorLine(ui, ConsoleColor.Red, "    └─────────────────────────────────────────────────────────────┘");
        WriteColorLine(ui, ConsoleColor.DarkYellow, "    Command execution BLOCKED due to syntax errors:");

        if (analysis.ParseErrors != null)
        {
            foreach (var err in analysis.ParseErrors)
            {
                int lineNum = err.Extent?.StartLineNumber ?? 1;
                int colNum = err.Extent?.StartColumnNumber ?? 1;
                WriteColorLine(ui, ConsoleColor.Red, $"      • Line {lineNum}, Col {colNum}: {err.Message}");
            }
        }
        WriteColorLine(ui, ConsoleColor.Red, "");
    }

    private static void RenderPreviewUnavailable(PSHostUserInterface? ui, AstAnalysisResult analysis, bool isUk)
    {
        string reason = !string.IsNullOrWhiteSpace(analysis.PreviewUnavailableReason)
            ? analysis.PreviewUnavailableReason
            : "WhatIf preview is not supported for this command.";

        WriteColorLine(ui, ConsoleColor.DarkYellow, "");
        WriteColorLine(ui, ConsoleColor.DarkYellow, $"    ⚠ [Preview Unavailable] {reason}");
        WriteColorLine(ui, ConsoleColor.DarkGray, "      Command contains external binaries or operations without SupportsShouldProcess.");
        WriteColorLine(ui, ConsoleColor.DarkYellow, "");
    }

    private static void RenderSecurityGateCard(PSHostUserInterface? ui, string command, AstAnalysisResult analysis, bool isUk)
    {
        ConsoleColor headerColor = analysis.OverallRisk switch
        {
            CommandRiskLevel.Critical => ConsoleColor.Red,
            CommandRiskLevel.High => ConsoleColor.Red,
            CommandRiskLevel.Medium => ConsoleColor.Yellow,
            _ => ConsoleColor.Cyan
        };

        WriteColorLine(ui, headerColor, "");
        WriteColorLine(ui, headerColor, "    ┌─────────────────────────────────────────────────────────────┐");
        WriteColorLine(ui, headerColor, "    │               ⚠  TERMINAL AI SECURITY GATE  ⚠               │");
        WriteColorLine(ui, headerColor, "    └─────────────────────────────────────────────────────────────┘");

        WriteInline(ui, ConsoleColor.White, "    Command:  ");
        WriteColorLine(ui, ConsoleColor.Cyan, AotSecretSanitizer.Sanitize(command));

        WriteInline(ui, ConsoleColor.White, "    Category: ");
        WriteColorLine(ui, ConsoleColor.Yellow, analysis.OverallCategory.ToString());

        WriteInline(ui, ConsoleColor.White, "    Risk:     ");
        WriteColorLine(ui, headerColor, analysis.OverallRisk.ToString());

        if (analysis.Targets != null && analysis.Targets.Count > 0)
        {
            WriteInline(ui, ConsoleColor.White, "    Targets:  ");
            var sanitizedTargets = analysis.Targets.Select(AotSecretSanitizer.Sanitize);
            WriteColorLine(ui, ConsoleColor.Magenta, string.Join(", ", sanitizedTargets));
        }

        var reasons = new List<string>();
        if (analysis.HasDynamicInvocation)
        {
            reasons.Add("Dynamic command invocation detected (& $var, Invoke-Expression, iex)");
        }
        if (analysis.HasDynamicTarget)
        {
            reasons.Add("Dynamic or unresolved target (variable/expression in arguments)");
        }
        if (analysis.HasSplatting)
        {
            reasons.Add("Parameter splatting detected (@params)");
        }
        foreach (var cmd in analysis.Commands)
        {
            if (cmd.InvalidParameters != null && cmd.InvalidParameters.Count > 0)
            {
                reasons.Add($"Unknown parameter(s) for {cmd.CommandName}: {string.Join(", ", cmd.InvalidParameters)}");
            }
            if (cmd.Category is CommandCategory.Deletion or CommandCategory.DiskOrPartition or CommandCategory.Registry or CommandCategory.NetworkChange or CommandCategory.ServiceOrProcess)
            {
                reasons.Add($"Operation category '{cmd.Category}' modifies system state ({cmd.CommandName})");
            }
        }

        if (reasons.Count > 0)
        {
            WriteColorLine(ui, ConsoleColor.White, "    Reasons:");
            foreach (var r in reasons)
            {
                WriteColorLine(ui, ConsoleColor.DarkYellow, $"      • {r}");
            }
        }
    }

    private static void WriteColorLine(PSHostUserInterface? ui, ConsoleColor color, string message)
    {
        if (ui != null)
        {
            ui.WriteLine(color, ConsoleColor.Black, message);
        }
        else
        {
            var prev = Console.ForegroundColor;
            Console.ForegroundColor = color;
            Console.WriteLine(message);
            Console.ForegroundColor = prev;
        }
    }

    private static void WriteInline(PSHostUserInterface? ui, ConsoleColor color, string message)
    {
        if (ui != null)
        {
            ui.Write(color, ConsoleColor.Black, message);
        }
        else
        {
            var prev = Console.ForegroundColor;
            Console.ForegroundColor = color;
            Console.Write(message);
            Console.ForegroundColor = prev;
        }
    }
}
