using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text.RegularExpressions;

namespace TerminalAI.Aot;

public enum CommandRiskLevel
{
    Low,
    Medium,
    High,
    Critical
}

public enum CommandCategory
{
    ReadOnly,
    SystemChange,
    Deletion,
    NetworkChange,
    ServiceOrProcess,
    Registry,
    DiskOrPartition,
    DynamicOrUnknown,
    ExternalProgram
}

public record CommandAnalysisItem(
    string OriginalName,
    string CommandName,
    string? ResolvedTarget,
    string CommandType,
    CommandCategory Category,
    CommandRiskLevel Risk,
    bool SupportsWhatIf,
    IReadOnlyList<string> Parameters,
    IReadOnlyList<string> InvalidParameters,
    IReadOnlyList<string> Targets
);

public record AstAnalysisResult(
    bool IsValid,
    IReadOnlyList<ParseError> ParseErrors,
    IReadOnlyList<CommandAnalysisItem> Commands,
    CommandCategory OverallCategory,
    CommandRiskLevel OverallRisk,
    bool RequiresConfirmation,
    bool CanPreview,
    string? PreviewUnavailableReason,
    IReadOnlyList<string> Targets,
    bool HasDynamicInvocation,
    bool HasDynamicTarget,
    bool HasSplatting
);

public static class AotCommandAstAnalyzer
{
    private static readonly string[] CommonParameters = new[]
    {
        "Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction",
        "ErrorVariable", "WarningVariable", "InformationVariable", "OutVariable",
        "OutBuffer", "PipelineVariable", "WhatIf", "Confirm"
    };

    private static readonly CommandCategory[] CategoryPrecedence = new[]
    {
        CommandCategory.DiskOrPartition,
        CommandCategory.Deletion,
        CommandCategory.Registry,
        CommandCategory.ServiceOrProcess,
        CommandCategory.NetworkChange,
        CommandCategory.DynamicOrUnknown,
        CommandCategory.ExternalProgram,
        CommandCategory.SystemChange,
        CommandCategory.ReadOnly
    };

    public static AstAnalysisResult Analyze(string script, SessionState? sessionState = null)
    {
        if (string.IsNullOrWhiteSpace(script))
        {
            return new AstAnalysisResult(
                IsValid: false,
                ParseErrors: Array.Empty<ParseError>(),
                Commands: Array.Empty<CommandAnalysisItem>(),
                OverallCategory: CommandCategory.DynamicOrUnknown,
                OverallRisk: CommandRiskLevel.Low,
                RequiresConfirmation: false,
                CanPreview: false,
                PreviewUnavailableReason: "Command string is empty or whitespace.",
                Targets: Array.Empty<string>(),
                HasDynamicInvocation: false,
                HasDynamicTarget: false,
                HasSplatting: false
            );
        }

        // 1. AST Parsing
        var ast = Parser.ParseInput(script, out _, out var errors);
        if (errors != null && errors.Length > 0)
        {
            return new AstAnalysisResult(
                IsValid: false,
                ParseErrors: errors,
                Commands: Array.Empty<CommandAnalysisItem>(),
                OverallCategory: CommandCategory.DynamicOrUnknown,
                OverallRisk: CommandRiskLevel.High,
                RequiresConfirmation: true,
                CanPreview: false,
                PreviewUnavailableReason: "Command contains syntax errors.",
                Targets: Array.Empty<string>(),
                HasDynamicInvocation: false,
                HasDynamicTarget: false,
                HasSplatting: false
            );
        }

        var analyzedCommands = new List<CommandAnalysisItem>();
        var allTargets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        bool hasDynamicInvocation = false;
        bool hasDynamicTarget = false;
        bool hasSplatting = ast.FindAll(x => x is VariableExpressionAst v && v.Splatted, true).Any();

        var cmdAsts = ast.FindAll(x => x is CommandAst, true);

        foreach (CommandAst cAst in cmdAsts.Cast<CommandAst>())
        {
            var rawName = cAst.GetCommandName();
            string originalName = rawName ?? cAst.Extent.Text;
            string? resolvedTarget = null;
            CommandInfo? cmdInfo = null;
            string commandType = "Unknown";
            CommandCategory category = CommandCategory.DynamicOrUnknown;
            CommandRiskLevel risk = CommandRiskLevel.Medium;
            bool supportsWhatIf = false;
            var invalidParams = new List<string>();
            var paramsFound = new List<string>();
            var cmdTargets = new List<string>();

            if (string.IsNullOrWhiteSpace(rawName))
            {
                commandType = "DynamicInvocation";
                category = CommandCategory.DynamicOrUnknown;
                risk = CommandRiskLevel.High;
                hasDynamicInvocation = true;
            }
            else
            {
                string effectiveName = rawName;

                if (sessionState != null)
                {
                    try
                    {
                        var aliasInfo = sessionState.InvokeCommand.GetCommand(rawName, CommandTypes.Alias) as AliasInfo;
                        if (aliasInfo != null)
                        {
                            commandType = "Alias";
                            resolvedTarget = aliasInfo.Definition;
                            effectiveName = resolvedTarget;
                            cmdInfo = sessionState.InvokeCommand.GetCommand(resolvedTarget, CommandTypes.All);
                        }
                        else
                        {
                            cmdInfo = sessionState.InvokeCommand.GetCommand(rawName, CommandTypes.All);
                        }
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[AotCommandAstAnalyzer] GetCommand resolution failed for '{rawName}': {ex.Message}");
                    }
                }

                if (cmdInfo != null)
                {
                    if (cmdInfo.CommandType is CommandTypes.Cmdlet or CommandTypes.Function or CommandTypes.Filter or CommandTypes.Script)
                    {
                        if (commandType != "Alias") commandType = cmdInfo.CommandType.ToString();
                        resolvedTarget = cmdInfo.Name;

                        // Check ShouldProcess / WhatIf support
                        if (cmdInfo.Parameters != null && cmdInfo.Parameters.ContainsKey("WhatIf"))
                        {
                            supportsWhatIf = true;
                        }
                        else if (cmdInfo is CmdletInfo cmdletInfo && cmdletInfo.ImplementingType != null)
                        {
                            var cmdAttr = (CmdletAttribute?)Attribute.GetCustomAttribute(cmdletInfo.ImplementingType, typeof(CmdletAttribute));
                            if (cmdAttr != null && cmdAttr.SupportsShouldProcess)
                            {
                                supportsWhatIf = true;
                            }
                        }
                    }
                    else if (cmdInfo.CommandType == CommandTypes.Application)
                    {
                        commandType = "ExternalProgram";
                        resolvedTarget = cmdInfo.Source;
                        category = CommandCategory.ExternalProgram;
                        risk = CommandRiskLevel.Medium;
                        supportsWhatIf = false;
                    }
                }
                else if (sessionState == null)
                {
                    commandType = "StaticCmdlet";
                    resolvedTarget = rawName;
                }
                else
                {
                    commandType = "Unknown";
                    category = CommandCategory.DynamicOrUnknown;
                    risk = CommandRiskLevel.High;
                }

                // Parameter Analysis
                var paramAsts = cAst.FindAll(x => x is CommandParameterAst, false);
                foreach (CommandParameterAst p in paramAsts.Cast<CommandParameterAst>())
                {
                    var pName = p.ParameterName;
                    paramsFound.Add(pName);

                    if (cmdInfo?.Parameters != null)
                    {
                        bool known = cmdInfo.Parameters.ContainsKey(pName) || CommonParameters.Contains(pName, StringComparer.OrdinalIgnoreCase);
                        if (!known)
                        {
                            bool prefixMatch = cmdInfo.Parameters.Keys.Any(k => k.StartsWith(pName, StringComparison.OrdinalIgnoreCase)) ||
                                               CommonParameters.Any(k => k.StartsWith(pName, StringComparison.OrdinalIgnoreCase));
                            if (!prefixMatch)
                            {
                                invalidParams.Add(pName);
                            }
                        }
                    }
                }

                // Target and Argument Analysis
                for (int i = 1; i < cAst.CommandElements.Count; i++)
                {
                    var elem = cAst.CommandElements[i];
                    if (elem is CommandParameterAst) continue;

                    if (elem is StringConstantExpressionAst strConst)
                    {
                        var val = strConst.Value;
                        if (!string.IsNullOrWhiteSpace(val) && !val.StartsWith("-"))
                        {
                            cmdTargets.Add(val);
                            allTargets.Add(val);
                        }
                    }
                    else if (elem is ExpandableStringExpressionAst expStr)
                    {
                        var val = expStr.Extent.Text.Trim('"', '\'');
                        if (!string.IsNullOrWhiteSpace(val))
                        {
                            cmdTargets.Add(val);
                            allTargets.Add(val);
                        }
                    }
                    else if (elem is VariableExpressionAst or SubExpressionAst or ScriptBlockExpressionAst)
                    {
                        cmdTargets.Add("Unknown target");
                        hasDynamicTarget = true;
                        allTargets.Add("Unknown target");
                    }
                }

                // Classification of category and risk
                string eff = resolvedTarget ?? effectiveName;

                if (commandType == "ExternalProgram")
                {
                    category = CommandCategory.ExternalProgram;
                    if (Regex.IsMatch(eff, @"^(?:rm|del|erase|format|fdisk|dd|diskpart|mkfs)$", RegexOptions.IgnoreCase))
                    {
                        category = CommandCategory.Deletion;
                        risk = CommandRiskLevel.High;
                    }
                    else
                    {
                        risk = CommandRiskLevel.Medium;
                    }
                }
                else if (commandType == "Unknown")
                {
                    category = CommandCategory.DynamicOrUnknown;
                    risk = CommandRiskLevel.High;
                }
                else
                {
                    if (Regex.IsMatch(eff, @"^(?:Remove-|Clear-|Reset-)", RegexOptions.IgnoreCase))
                    {
                        category = CommandCategory.Deletion;
                        risk = CommandRiskLevel.High;
                    }
                    else if (Regex.IsMatch(eff, @"^(?:Stop-Process|kill|Stop-Service|Restart-Service|Suspend-Service|Set-Service)", RegexOptions.IgnoreCase))
                    {
                        category = CommandCategory.ServiceOrProcess;
                        risk = CommandRiskLevel.High;
                    }
                    else if (Regex.IsMatch(eff, @"^(?:Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|Clear-ItemProperty)", RegexOptions.IgnoreCase) ||
                             (Regex.IsMatch(eff, @"^(?:Get-ItemProperty|New-Item|Remove-Item|Set-Item)", RegexOptions.IgnoreCase) && Regex.IsMatch(script, @"(?i)\b(?:HKCU:|HKLM:|HKCR:|HKU:|HKCC:|Registry::)")))
                    {
                        category = CommandCategory.Registry;
                        risk = CommandRiskLevel.High;
                    }
                    else if (Regex.IsMatch(eff, @"(?i)(?:-Disk\b|-Partition\b|-Volume\b|Format-Volume|Initialize-Disk|Clear-Disk)"))
                    {
                        category = CommandCategory.DiskOrPartition;
                        risk = CommandRiskLevel.Critical;
                    }
                    else if (Regex.IsMatch(eff, @"(?i)^(?:Set-Net|New-Net|Remove-Net|Disable-Net|Enable-Net|Rename-Net)"))
                    {
                        category = CommandCategory.NetworkChange;
                        risk = CommandRiskLevel.High;
                    }
                    else if (Regex.IsMatch(eff, @"(?i)^(?:Set-|New-|Add-|Register-|Unregister-|Install-|Uninstall-|Enable-|Disable-|Grant-|Revoke-)"))
                    {
                        category = CommandCategory.SystemChange;
                        risk = CommandRiskLevel.Medium;
                    }
                    else if (Regex.IsMatch(eff, @"(?i)^(?:Get-|Select-|Where-|ForEach-|Measure-|Sort-|Out-|Format-|Export-|Test-|Show-|Find-|Read-|Compare-|Group-)"))
                    {
                        category = CommandCategory.ReadOnly;
                        risk = CommandRiskLevel.Low;
                    }
                    else
                    {
                        category = CommandCategory.DynamicOrUnknown;
                        risk = CommandRiskLevel.Medium;
                    }
                }

                if (invalidParams.Count > 0 && risk == CommandRiskLevel.Low)
                {
                    risk = CommandRiskLevel.Medium;
                }
            }

            analyzedCommands.Add(new CommandAnalysisItem(
                OriginalName: originalName,
                CommandName: resolvedTarget ?? originalName,
                ResolvedTarget: resolvedTarget,
                CommandType: commandType,
                Category: category,
                Risk: risk,
                SupportsWhatIf: supportsWhatIf,
                Parameters: paramsFound,
                InvalidParameters: invalidParams,
                Targets: cmdTargets
            ));
        }

        // Overall category resolution by precedence
        CommandCategory overallCat = CommandCategory.ReadOnly;
        foreach (var cat in CategoryPrecedence)
        {
            if (analyzedCommands.Any(c => c.Category == cat))
            {
                overallCat = cat;
                break;
            }
        }

        // Overall risk resolution
        CommandRiskLevel overallRisk = CommandRiskLevel.Low;
        if (analyzedCommands.Any(c => c.Risk == CommandRiskLevel.Critical)) overallRisk = CommandRiskLevel.Critical;
        else if (analyzedCommands.Any(c => c.Risk == CommandRiskLevel.High)) overallRisk = CommandRiskLevel.High;
        else if (analyzedCommands.Any(c => c.Risk == CommandRiskLevel.Medium)) overallRisk = CommandRiskLevel.Medium;

        if (hasDynamicInvocation && (overallRisk == CommandRiskLevel.Low || overallRisk == CommandRiskLevel.Medium))
        {
            overallRisk = CommandRiskLevel.High;
            overallCat = CommandCategory.DynamicOrUnknown;
        }

        bool requiresConfirm = overallRisk is CommandRiskLevel.High or CommandRiskLevel.Critical ||
                               hasDynamicInvocation || hasDynamicTarget;

        bool canPreview = analyzedCommands.Count > 0 &&
                          analyzedCommands.All(c => c.Category == CommandCategory.ReadOnly || c.SupportsWhatIf);

        string? previewReason = null;
        if (!canPreview)
        {
            if (analyzedCommands.Any(c => c.CommandType == "ExternalProgram"))
            {
                previewReason = "Safe preview (-WhatIf) is unavailable for external binary programs.";
            }
            else
            {
                previewReason = "Safe preview (-WhatIf) is not supported by one or more commands.";
            }
        }

        if (allTargets.Count == 0)
        {
            allTargets.Add("Unknown target");
        }

        return new AstAnalysisResult(
            IsValid: true,
            ParseErrors: Array.Empty<ParseError>(),
            Commands: analyzedCommands,
            OverallCategory: overallCat,
            OverallRisk: overallRisk,
            RequiresConfirmation: requiresConfirm,
            CanPreview: canPreview,
            PreviewUnavailableReason: previewReason,
            Targets: allTargets.ToList(),
            HasDynamicInvocation: hasDynamicInvocation,
            HasDynamicTarget: hasDynamicTarget,
            HasSplatting: hasSplatting
        );
    }
}
