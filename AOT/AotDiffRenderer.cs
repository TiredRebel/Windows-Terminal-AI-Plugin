using System;
using System.Collections.Generic;
using System.Management.Automation.Host;
using System.Text.RegularExpressions;

namespace TerminalAI.Aot;

public enum DiffLineType
{
    Unchanged,
    Added,
    Removed
}

public sealed class DiffRecord
{
    public DiffLineType Type { get; set; }
    public string Line { get; set; } = string.Empty;

    public override string ToString() => Line;
}

public static class AotDiffRenderer
{
    /// <summary>
    /// Generates a deterministic unified diff between oldText and newText.
    /// Matches the behavior of Format-AiScriptDiff in TerminalAI.psm1.
    /// </summary>
    public static List<DiffRecord> FormatDiff(string? oldText, string? newText)
    {
        var oldLines = string.IsNullOrEmpty(oldText) ? Array.Empty<string>() : Regex.Split(oldText, @"\r?\n");
        var newLines = string.IsNullOrEmpty(newText) ? Array.Empty<string>() : Regex.Split(newText, @"\r?\n");

        var diffRecords = new List<DiffRecord>();
        int i = 0;
        int j = 0;
        int maxSteps = (oldLines.Length + newLines.Length) * 2 + 10;
        int steps = 0;

        while ((i < oldLines.Length || j < newLines.Length) && (steps < maxSteps))
        {
            steps++;
            string? o = i < oldLines.Length ? oldLines[i] : null;
            string? n = j < newLines.Length ? newLines[j] : null;

            if (o != null && n != null && string.Equals(o, n, StringComparison.Ordinal))
            {
                diffRecords.Add(new DiffRecord { Type = DiffLineType.Unchanged, Line = "  " + o });
                i++;
                j++;
            }
            else if (o != null && n != null && !string.Equals(o, n, StringComparison.Ordinal))
            {
                if ((j + 1) < newLines.Length && string.Equals(newLines[j + 1], o, StringComparison.Ordinal))
                {
                    diffRecords.Add(new DiffRecord { Type = DiffLineType.Added, Line = "+ " + n });
                    j++;
                }
                else if ((i + 1) < oldLines.Length && string.Equals(oldLines[i + 1], n, StringComparison.Ordinal))
                {
                    diffRecords.Add(new DiffRecord { Type = DiffLineType.Removed, Line = "- " + o });
                    i++;
                }
                else
                {
                    diffRecords.Add(new DiffRecord { Type = DiffLineType.Removed, Line = "- " + o });
                    diffRecords.Add(new DiffRecord { Type = DiffLineType.Added, Line = "+ " + n });
                    i++;
                    j++;
                }
            }
            else if (o != null && n == null)
            {
                diffRecords.Add(new DiffRecord { Type = DiffLineType.Removed, Line = "- " + o });
                i++;
            }
            else if (o == null && n != null)
            {
                diffRecords.Add(new DiffRecord { Type = DiffLineType.Added, Line = "+ " + n });
                j++;
            }
            else
            {
                break;
            }
        }

        return diffRecords;
    }

    /// <summary>
    /// Renders unified diff records with color coding to PSHostUserInterface or Console.
    /// </summary>
    public static void RenderToHost(
        IEnumerable<DiffRecord> diff,
        PSHostUserInterface? ui,
        string oldLabel = "Existing File",
        string newLabel = "New AI Script")
    {
        if (ui != null)
        {
            var bg = ui.RawUI.BackgroundColor;
            ui.WriteLine();
            ui.WriteLine(ConsoleColor.Red, bg, $"    --- {oldLabel}");
            ui.WriteLine(ConsoleColor.Green, bg, $"    +++ {newLabel}");

            foreach (var dl in diff)
            {
                switch (dl.Type)
                {
                    case DiffLineType.Added:
                        ui.WriteLine(ConsoleColor.Green, bg, $"    {dl.Line}");
                        break;
                    case DiffLineType.Removed:
                        ui.WriteLine(ConsoleColor.Red, bg, $"    {dl.Line}");
                        break;
                    case DiffLineType.Unchanged:
                    default:
                        ui.WriteLine(ConsoleColor.DarkGray, bg, $"    {dl.Line}");
                        break;
                }
            }
            ui.WriteLine();
        }
        else
        {
            var prevColor = Console.ForegroundColor;
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"    --- {oldLabel}");
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine($"    +++ {newLabel}");

            foreach (var dl in diff)
            {
                switch (dl.Type)
                {
                    case DiffLineType.Added:
                        Console.ForegroundColor = ConsoleColor.Green;
                        break;
                    case DiffLineType.Removed:
                        Console.ForegroundColor = ConsoleColor.Red;
                        break;
                    case DiffLineType.Unchanged:
                    default:
                        Console.ForegroundColor = ConsoleColor.DarkGray;
                        break;
                }
                Console.WriteLine($"    {dl.Line}");
            }
            Console.ForegroundColor = prevColor;
            Console.WriteLine();
        }
    }
}
