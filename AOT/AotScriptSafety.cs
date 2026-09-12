using System;
using System.Collections.Generic;
using System.IO;
using System.Management.Automation;
using System.Text;
using System.Text.RegularExpressions;

namespace TerminalAI.Aot;

public sealed class SaveScriptResult
{
    public bool Saved { get; set; }
    public string Status { get; set; } = string.Empty; // Created, Overwritten, Identical, BlockedNonInteractive, OverwriteDenied, Error
    public string Path { get; set; } = string.Empty;
    public List<DiffRecord> Diff { get; set; } = new();
    public string? ErrorMessage { get; set; }

    public override string ToString() => $"[SaveScriptResult Saved={Saved}, Status={Status}, Path={Path}]";
}

public static class AotScriptSafety
{
    /// <summary>
    /// Checks whether code represents a multi-line script or multiple command statements.
    /// </summary>
    public static bool IsMultiLineScript(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return false;
        var trimmed = code.Trim();
        if (trimmed.Contains('\n') || trimmed.Contains('\r')) return true;
        if (Regex.IsMatch(trimmed, @"\b(?:function|filter|workflow|param\s*\(|begin\s*\{|process\s*\{|end\s*\{)\b", RegexOptions.IgnoreCase))
        {
            return true;
        }
        return false;
    }

    /// <summary>
    /// Checks whether a target file has a valid UTF-8 BOM (0xEF, 0xBB, 0xBF).
    /// </summary>
    public static bool HasUtf8Bom(string filePath)
    {
        if (!File.Exists(filePath)) return false;
        try
        {
            using var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            if (fs.Length < 3) return false;
            var bom = new byte[3];
            int read = fs.Read(bom, 0, 3);
            return read == 3 && bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[AotScriptSafety.HasUtf8Bom] Error reading BOM: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Safely and atomically saves AI script content to disk with unified diff preview,
    /// identical content detection, overwrite protection, and UTF-8 BOM encoding.
    /// Matches the contract of Save-AiScriptFile in TerminalAI.psm1.
    /// </summary>
    public static SaveScriptResult SaveScriptFile(
        string path,
        string content,
        bool force = false,
        string? confirmInput = null,
        PSCmdlet? caller = null,
        bool isUk = false)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return new SaveScriptResult
            {
                Saved = false,
                Status = "Error",
                ErrorMessage = "Target path cannot be null or whitespace."
            };
        }

        string resolvedPath;
        try
        {
            if (caller?.SessionState?.Path != null)
            {
                resolvedPath = caller.SessionState.Path.GetUnresolvedProviderPathFromPSPath(path);
            }
            else
            {
                resolvedPath = Path.GetFullPath(path);
            }
        }
        catch (Exception ex)
        {
            return new SaveScriptResult
            {
                Saved = false,
                Status = "Error",
                Path = path,
                ErrorMessage = $"Failed to resolve path: {ex.Message}"
            };
        }

        bool fileExists = File.Exists(resolvedPath);
        var diff = new List<DiffRecord>();

        if (fileExists)
        {
            string existingContent = string.Empty;
            try
            {
                existingContent = File.ReadAllText(resolvedPath, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                return new SaveScriptResult
                {
                    Saved = false,
                    Status = "Error",
                    Path = resolvedPath,
                    ErrorMessage = $"Failed to read existing file: {ex.Message}"
                };
            }

            if (string.Equals(existingContent.Trim(), content.Trim(), StringComparison.Ordinal))
            {
                var infoMsg = isUk
                    ? $"    ℹ [TerminalAI] Файл вже існує з ідентичним вмістом: {resolvedPath}"
                    : $"    ℹ [TerminalAI] File already exists with identical content: {resolvedPath}";

                if (caller?.Host?.UI != null)
                {
                    caller.Host.UI.WriteLine(ConsoleColor.DarkCyan, caller.Host.UI.RawUI.BackgroundColor, infoMsg);
                }
                else
                {
                    Console.WriteLine(infoMsg);
                }

                return new SaveScriptResult
                {
                    Saved = true,
                    Status = "Identical",
                    Path = resolvedPath,
                    Diff = new List<DiffRecord>()
                };
            }

            // File exists and differs: render unified diff warning
            diff = AotDiffRenderer.FormatDiff(existingContent, content);

            if (caller?.Host?.UI != null)
            {
                var bg = caller.Host.UI.RawUI.BackgroundColor;
                caller.Host.UI.WriteLine();
                caller.Host.UI.WriteLine(ConsoleColor.Yellow, bg, "    ┌─────────────────────────────────────────────────────────────┐");
                caller.Host.UI.WriteLine(ConsoleColor.Yellow, bg, "    │             ⚠  EXISTING FILE OVERWRITE WARNING  ⚠           │");
                caller.Host.UI.WriteLine(ConsoleColor.Yellow, bg, "    └─────────────────────────────────────────────────────────────┘");
                caller.Host.UI.WriteLine(ConsoleColor.Cyan, bg, $"    File: {resolvedPath}");
                AotDiffRenderer.RenderToHost(diff, caller.Host.UI);
            }
            else
            {
                Console.WriteLine();
                Console.WriteLine("    ┌─────────────────────────────────────────────────────────────┐");
                Console.WriteLine("    │             ⚠  EXISTING FILE OVERWRITE WARNING  ⚠           │");
                Console.WriteLine("    └─────────────────────────────────────────────────────────────┘");
                Console.WriteLine($"    File: {resolvedPath}");
                AotDiffRenderer.RenderToHost(diff, null);
            }

            if (!force)
            {
                bool confirmed = false;
                if (!string.IsNullOrEmpty(confirmInput))
                {
                    if (Regex.IsMatch(confirmInput.Trim(), @"^(y|yes|так|т)$", RegexOptions.IgnoreCase))
                    {
                        confirmed = true;
                    }
                }
                else
                {
                    bool isInteractive;
                    try
                    {
                        isInteractive = Environment.UserInteractive && !Console.IsInputRedirected;
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[AotScriptSafety.SaveScriptFile] UserInteractive check error: {ex.Message}");
                        isInteractive = false;
                    }

                    if (!isInteractive)
                    {
                        var blockedMsg = isUk
                            ? "    ✖ Неінтерактивна сесія. Перезапис скасовано заради безпеки."
                            : "    ✖ Non-interactive session. Overwrite canceled for safety.";

                        if (caller?.Host?.UI != null)
                        {
                            caller.Host.UI.WriteLine(ConsoleColor.Red, caller.Host.UI.RawUI.BackgroundColor, blockedMsg);
                        }
                        else
                        {
                            Console.WriteLine(blockedMsg);
                        }

                        return new SaveScriptResult
                        {
                            Saved = false,
                            Status = "BlockedNonInteractive",
                            Path = resolvedPath,
                            Diff = diff
                        };
                    }

                    var promptText = isUk ? "    Перезаписати цей файл? [y/N]: " : "    Overwrite this file? [y/N]: ";
                    Console.Write(promptText);
                    var response = Console.ReadLine()?.Trim() ?? string.Empty;
                    if (Regex.IsMatch(response, @"^(y|yes|так|т)$", RegexOptions.IgnoreCase))
                    {
                        confirmed = true;
                    }
                }

                if (!confirmed)
                {
                    var cancelMsg = isUk
                        ? "    ✖ Перезапис скасовано користувачем."
                        : "    ✖ Overwrite canceled by user.";

                    if (caller?.Host?.UI != null)
                    {
                        caller.Host.UI.WriteLine(ConsoleColor.DarkGray, caller.Host.UI.RawUI.BackgroundColor, cancelMsg);
                    }
                    else
                    {
                        Console.WriteLine(cancelMsg);
                    }

                    return new SaveScriptResult
                    {
                        Saved = false,
                        Status = "OverwriteDenied",
                        Path = resolvedPath,
                        Diff = diff
                    };
                }
            }
        }

        // Atomic write via temp file with UTF-8 BOM
        var enc = new UTF8Encoding(encoderShouldEmitUTF8Identifier: true);
        var dir = Path.GetDirectoryName(resolvedPath);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        string tmpPath = resolvedPath + ".tmp." + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(tmpPath, content, enc);
            if (fileExists)
            {
                File.Copy(tmpPath, resolvedPath, overwrite: true);
                File.Delete(tmpPath);
            }
            else
            {
                File.Move(tmpPath, resolvedPath);
            }

            var successMsg = isUk
                ? $"    ✔ Файл успішно збережено: {resolvedPath}"
                : $"    ✔ File successfully saved: {resolvedPath}";

            if (caller?.Host?.UI != null)
            {
                caller.Host.UI.WriteLine(ConsoleColor.Green, caller.Host.UI.RawUI.BackgroundColor, successMsg);
            }
            else
            {
                Console.WriteLine(successMsg);
            }

            return new SaveScriptResult
            {
                Saved = true,
                Status = fileExists ? "Overwritten" : "Created",
                Path = resolvedPath,
                Diff = fileExists ? diff : new List<DiffRecord>()
            };
        }
        catch (Exception ex)
        {
            if (File.Exists(tmpPath))
            {
                try { File.Delete(tmpPath); }
                catch (Exception delEx)
                {
                    System.Diagnostics.Debug.WriteLine($"[AotScriptSafety] Failed to delete temp file '{tmpPath}': {delEx.Message}");
                }
            }

            var errMsg = isUk
                ? $"    ✖ Помилка збереження файлу: {ex.Message}"
                : $"    ✖ Error saving file: {ex.Message}";

            if (caller?.Host?.UI != null)
            {
                caller.Host.UI.WriteLine(ConsoleColor.Red, caller.Host.UI.RawUI.BackgroundColor, errMsg);
            }
            else
            {
                Console.WriteLine(errMsg);
            }

            return new SaveScriptResult
            {
                Saved = false,
                Status = "Error",
                Path = resolvedPath,
                ErrorMessage = ex.Message
            };
        }
    }
}
