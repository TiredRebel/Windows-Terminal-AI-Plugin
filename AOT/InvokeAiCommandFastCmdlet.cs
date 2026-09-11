using System;
using System.Diagnostics;
using System.Management.Automation;

namespace TerminalAI.Aot;

[Cmdlet(VerbsLifecycle.Invoke, "AiCommandFast")]
[Alias("ai-fast", "aif")]
public class InvokeAiCommandFastCmdlet : PSCmdlet
{
    [Parameter(Position = 0, Mandatory = true, ValueFromRemainingArguments = true)]
    public string[] Prompt { get; set; } = Array.Empty<string>();

    [Parameter]
    public string? Model { get; set; }

    [Parameter]
    public SwitchParameter Execute { get; set; }

    [Parameter]
    public SwitchParameter Copy { get; set; }

    protected override void ProcessRecord()
    {
        var fullPrompt = string.Join(" ", Prompt).Trim();
        if (string.IsNullOrWhiteSpace(fullPrompt)) return;

        var cfg = AiConfig.Load();
        var activeModel = string.IsNullOrWhiteSpace(Model) ? cfg.Model : Model;
        var isUk = cfg.Language != "en";

        var sw = Stopwatch.StartNew();
        var connectingText = isUk ? $"Звертаюсь до Ollama ({activeModel})..." : $"Connecting to Ollama ({activeModel})...";
        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {connectingText}");

        var systemPrompt = "You are an expert PowerShell engineer. Generate strictly the raw PowerShell command with no markdown, backticks, or explanation.";

        string command;
        try
        {
            command = OllamaClient.GenerateAsync(cfg.OllamaUrl, activeModel, fullPrompt, systemPrompt, cfg.Temperature).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            Host.UI.WriteErrorLine($"[TerminalAI.AOT] Помилка Ollama: {ex.Message}");
            return;
        }

        sw.Stop();
        if (string.IsNullOrWhiteSpace(command)) return;

        // Рендеринг картки з таймером відклику
        RenderCard(command, activeModel, sw.ElapsedMilliseconds, isUk);

        if (Copy || cfg.AutoCopy)
        {
            CopyToClipboard(command);
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, isUk ? "    ✔ Скопійовано в буфер обміну!\n" : "    ✔ Copied to clipboard!\n");
        }

        if (Execute)
        {
            Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, isUk ? "    ▶ Виконання команди:\n" : "    ▶ Executing command:\n");
            var scriptBlock = ScriptBlock.Create(command);
            scriptBlock.Invoke();
            return;
        }

        // Меню дій
        RenderMenu(isUk);

        var action = Win32Console.ReadMenuAction();
        switch (action)
        {
            case MenuAction.Execute:
                Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, isUk ? "    ▶ Виконання команди:\n" : "    ▶ Executing command:\n");
                var sb = ScriptBlock.Create(command);
                sb.Invoke();
                break;

            case MenuAction.Copy:
                CopyToClipboard(command);
                Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, isUk ? "    ✔ Скопійовано в буфер обміну!\n" : "    ✔ Copied to clipboard!\n");
                break;

            case MenuAction.Insert:
                CopyToClipboard(command);
                Win32Console.DelayedPaste(200);
                Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, isUk ? "    ✔ Команду вставлено у рядок введення!\n" : "    ✔ Command inserted into input line!\n");
                break;

            case MenuAction.Cancel:
                Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, isUk ? "    Скасовано.\n" : "    Canceled.\n");
                break;
        }
    }

    private void RenderCard(string code, string model, long elapsedMs, bool isUk)
    {
        var latency = $"{elapsedMs}ms";
        var title = isUk ? $"AI Команда (AOT • {latency})" : $"AI Command (AOT • {latency})";
        var boxWidth = Math.Max(66, code.Length + 6);

        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n    ✦ {title} • {model}");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭" + new string('─', boxWidth) + "╮");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │" + new string(' ', boxWidth) + "│");

        var pad = boxWidth - 4 - code.Length;
        if (pad < 0) pad = 0;
        Host.UI.Write(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │  ");
        Host.UI.Write(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, code);
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, new string(' ', pad) + "  │");

        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │" + new string(' ', boxWidth) + "│");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰" + new string('─', boxWidth) + "╯\n");
    }

    private void RenderMenu(bool isUk)
    {
        var tEnter = isUk ? "Виконати" : "Execute";
        var tCopy = isUk ? "Скопіювати" : "Copy";
        var tInsert = isUk ? "Вставити в рядок" : "Insert into line";
        var tCancel = isUk ? "Скасувати" : "Cancel";

        Host.UI.Write(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    [Enter] ");
        Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, string.Format("{0,-18}", tEnter));
        Host.UI.Write(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, "[C] ");
        Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, string.Format("{0,-18}", tCopy));
        Host.UI.Write(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "[I] ");
        Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, string.Format("{0,-18}", tInsert));
        Host.UI.Write(ConsoleColor.Gray, Host.UI.RawUI.BackgroundColor, " [Esc] ");
        Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, tCancel + "\n");
    }

    private void CopyToClipboard(string text)
    {
        try
        {
            var sb = ScriptBlock.Create($"Set-Clipboard -Value '{text.Replace("'", "''")}'");
            sb.Invoke();
        }
        catch { }
    }
}
