using System;
using System.Diagnostics;
using System.IO;

namespace TerminalAI.Launcher;

internal static class Program
{
    private static int Main(string[] args)
    {
        string? pwsh = FindPowerShell();
        string scriptDir = AppDomain.CurrentDomain.BaseDirectory;
        string bootstrapScript = Path.Combine(scriptDir, "bootstrap.ps1");

        var psi = new ProcessStartInfo
        {
            FileName = pwsh ?? "powershell.exe",
            UseShellExecute = false
        };

        string passArgs = string.Join(" ", args);
        psi.Arguments = $"-NoExit -ExecutionPolicy Bypass -File \"{bootstrapScript}\" -Mode Portable {passArgs}".Trim();

        try
        {
            using var proc = Process.Start(psi);
            proc?.WaitForExit();
            return proc?.ExitCode ?? 0;
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"Failed to launch TerminalAI: {ex.Message}");
            Console.ResetColor();
            return 1;
        }
    }

    private static string? FindPowerShell()
    {
        var pathVar = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in pathVar.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var cand = Path.Combine(dir.Trim(), "pwsh.exe");
            if (File.Exists(cand)) return cand;
        }

        var pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var cand7 = Path.Combine(pf, "PowerShell", "7", "pwsh.exe");
        if (File.Exists(cand7)) return cand7;

        return null;
    }
}
