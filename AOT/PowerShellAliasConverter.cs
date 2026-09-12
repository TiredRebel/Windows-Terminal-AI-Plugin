using System;
using System.Text.RegularExpressions;

namespace TerminalAI.Aot;

public static class PowerShellAliasConverter
{
    private static readonly (string Full, string Short)[] CmdletPairs = new[]
    {
        ("Get-Process", "gps"),
        ("Get-ChildItem", "gci"),
        ("Where-Object", "?"),
        ("ForEach-Object", "%"),
        ("Select-Object", "select"),
        ("Sort-Object", "sort"),
        ("Measure-Object", "measure"),
        ("Get-Content", "gc"),
        ("Set-Content", "sc"),
        ("Select-String", "sls"),
        ("Get-Service", "gsv"),
        ("Stop-Process", "kill"),
        ("Format-Table", "ft"),
        ("Format-List", "fl"),
        ("Export-Csv", "epcsv"),
        ("Import-Csv", "ipcsv"),
        ("Get-Help", "help"),
        ("Clear-Host", "cls"),
        ("Copy-Item", "cpi"),
        ("Move-Item", "mi"),
        ("Remove-Item", "ri"),
        ("New-Item", "ni"),
        ("Get-Item", "gi"),
        ("Set-Item", "si"),
        ("Get-Location", "gl"),
        ("Set-Location", "sl")
    };

    public static string ToShortAliases(string script)
    {
        if (string.IsNullOrWhiteSpace(script)) return script;

        // Auto-correct any hallucinated patterns
        script = Regex.Replace(script, @"\b(?:gci|Get-ChildItem)\s+tcpconn\b", "Get-NetTCPConnection", RegexOptions.IgnoreCase);

        foreach (var (full, sh) in CmdletPairs)
        {
            var pattern = $@"(?<![\w\-])\b{Regex.Escape(full)}\b(?![\w\-])";
            script = Regex.Replace(script, pattern, sh, RegexOptions.IgnoreCase);
        }

        // Convert -ErrorAction SilentlyContinue -> -ea 0
        script = Regex.Replace(script, @"(?<![\w\-])-ErrorAction\s+(?:SilentlyContinue|0)\b", "-ea 0", RegexOptions.IgnoreCase);

        return script;
    }

    public static string ToFullCmdlets(string script)
    {
        if (string.IsNullOrWhiteSpace(script)) return script;

        // Auto-correct any hallucinated patterns
        script = Regex.Replace(script, @"\b(?:gci|Get-ChildItem)\s+tcpconn\b", "Get-NetTCPConnection", RegexOptions.IgnoreCase);

        foreach (var (full, sh) in CmdletPairs)
        {
            if (sh is "?" or "%")
            {
                // In PowerShell pipeline / subexpression: | ?, | %, ( ?, { ?
                var pattern = $@"(?<=[|\(\{{;\s]|^)\{Regex.Escape(sh)}(?=\s|[\{{])";
                script = Regex.Replace(script, pattern, full);
            }
            else
            {
                var pattern = $@"(?<![\w\-])\b{Regex.Escape(sh)}\b(?![\w\-])";
                script = Regex.Replace(script, pattern, full, RegexOptions.IgnoreCase);
            }
        }

        // Convert -ea 0 -> -ErrorAction SilentlyContinue
        script = Regex.Replace(script, @"(?<![\w\-])-ea\s+0\b", "-ErrorAction SilentlyContinue", RegexOptions.IgnoreCase);

        return script;
    }
}
