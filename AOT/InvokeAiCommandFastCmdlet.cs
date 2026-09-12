using System;
using System.Diagnostics;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace TerminalAI.Aot;

[Cmdlet(VerbsLifecycle.Invoke, "AiCommandFast")]
[Alias("ai-fast", "aif")]
public class InvokeAiCommandFastCmdlet : PSCmdlet
{
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

    protected override void ProcessRecord()
    {
        var cfg = AiConfig.Load();
        var isUk = cfg.Language != "en";
        var activeModel = string.IsNullOrWhiteSpace(Model) ? cfg.Model : Model;
        var fullPrompt = string.Join(" ", Prompt).Trim();

        // 1. Дефект: коли промпт порожній -> показуємо швидку довідку замість обов'язкового запиту
        if (string.IsNullOrWhiteSpace(fullPrompt))
        {
            ShowQuickReference(isUk);
            return;
        }

        // 2. Підтримка команд допомоги
        var lowerPrompt = fullPrompt.ToLowerInvariant();
        if (lowerPrompt is "help" or "/?" or "-?" or "--help" or "-h" or "довідка" or "допомога")
        {
            ShowQuickReference(isUk);
            return;
        }

        // 3. Статус та системна інформація
        if (Regex.IsMatch(lowerPrompt, @"^(?:which|what)\s+model|яка\s+модель|яку\s+модель|current\s+model|status|info|інфо|статус"))
        {
            ShowStatus(cfg, isUk);
            return;
        }

        // 4. Список моделей
        if (lowerPrompt is "models" or "--models" or "-m" or "моделі")
        {
            ShowModels(cfg, isUk);
            return;
        }

        // 5. Зміна активної моделі: ai-fast model <name>
        var modelMatch = Regex.Match(fullPrompt, @"^(?:set-model|use-model|use|model)\s+([A-Za-z0-9.:_\-\/]+)$", RegexOptions.IgnoreCase);
        if (modelMatch.Success)
        {
            var newModel = modelMatch.Groups[1].Value.Trim();
            cfg.Model = newModel;
            cfg.Save();
            var msg = isUk ? $"Активну модель успішно змінено на '{newModel}'!" : $"Active model successfully changed to '{newModel}'!";
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, $"\n    ✔ {msg}\n");
            return;
        }

        // 6. Перегляд та зміна мови
        if (lowerPrompt is "lang" or "language" or "--lang" or "-l" or "мова")
        {
            ShowLanguageInfo(cfg, isUk);
            return;
        }

        var langMatch = Regex.Match(fullPrompt, @"^(?:set-lang|lang|language|мова)(?:\s+(?:permanent|save|default|--permanent|-p|постійно))?\s+(uk|ua|en)$", RegexOptions.IgnoreCase);
        if (!langMatch.Success)
        {
            langMatch = Regex.Match(fullPrompt, @"^(?:set-lang|lang|language|мова)\s+(uk|ua|en)(?:\s+(?:permanent|save|default|--permanent|-p|постійно))?$", RegexOptions.IgnoreCase);
        }
        if (langMatch.Success)
        {
            var rawLang = langMatch.Groups[1].Value.ToLowerInvariant();
            var newLang = rawLang == "ua" ? "uk" : rawLang;
            cfg.Language = newLang;
            cfg.Save();
            var msg = newLang == "uk" ? "Мову інтерфейсу успішно змінено на Українську (uk)!" : "Interface language successfully changed to English (en)!";
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, $"\n    ✔ {msg}\n");
            return;
        }

        // 7. Конфігурація: ai-fast config
        if (lowerPrompt is "config" or "--config" or "-c")
        {
            ShowConfig(cfg);
            return;
        }

        // 8. Якщо явно запитано текстову відповідь (-Ask)
        if (Ask)
        {
            ShowAnswer(cfg, activeModel, fullPrompt, isUk);
            return;
        }

        // 9. Генерація PowerShell команди
        var connectingText = isUk ? $"Звертаюсь до Ollama ({activeModel})..." : $"Connecting to Ollama ({activeModel})...";
        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {connectingText}");

        var sw = Stopwatch.StartNew();
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

        // Попередження про невідомий командлет
        CheckUnknownCmdlet(command, isUk);

        // Рендеринг картки з таймером відклику
        RenderCard(command, activeModel, sw.ElapsedMilliseconds, isUk);

        if (Copy || cfg.AutoCopy)
        {
            CopyToClipboard(command);
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, isUk ? "    ✔ Скопійовано в буфер обміну!\n" : "    ✔ Copied to clipboard!\n");
        }

        if (Execute)
        {
            ExecuteCommand(command, isUk);
            return;
        }

        if (Explain)
        {
            ShowExplanation(cfg, activeModel, command, isUk);
            return;
        }

        // Меню дій
        RenderMenu(isUk);

        var action = Win32Console.ReadMenuAction();
        switch (action)
        {
            case MenuAction.Execute:
                ExecuteCommand(command, isUk);
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

            case MenuAction.Explain:
                ShowExplanation(cfg, activeModel, command, isUk);
                break;

            case MenuAction.Ask:
                ShowAnswer(cfg, activeModel, fullPrompt, isUk);
                break;

            case MenuAction.Cancel:
                Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, isUk ? "    Скасовано.\n" : "    Canceled.\n");
                break;
        }
    }

    private void ExecuteCommand(string command, bool isUk)
    {
        Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, isUk ? "    ▶ Виконання команди:\n" : "    ▶ Executing command:\n");
        var scriptBlock = ScriptBlock.Create(command);
        scriptBlock.Invoke();
    }

    private void ShowExplanation(AiConfig cfg, string model, string command, bool isUk)
    {
        var statusText = isUk ? "Формую детальне пояснення команди..." : "Generating detailed command explanation...";
        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {statusText}");

        var langInstruction = isUk ? "Respond strictly in Ukrainian language." : "Respond in English.";
        var explainSystemPrompt = $"You are an expert technical educator explaining PowerShell commands to engineers.\n{langInstruction}\nExplain concisely:\n1. What the command does overall.\n2. Breakdown of key parameters and pipeline operators.\n3. Any potential performance or security considerations.\nFormat with clean bullet points.";

        try
        {
            var userPrompt = $"Explain this PowerShell command:\n\n{command}";
            var explanation = OllamaClient.GenerateRawAsync(cfg.OllamaUrl, model, userPrompt, explainSystemPrompt, 0.3).GetAwaiter().GetResult();
            if (!string.IsNullOrWhiteSpace(explanation))
            {
                var title = isUk ? "Пояснення команди" : "Command Explanation";
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
            Host.UI.WriteErrorLine($"[TerminalAI.AOT] Помилка пояснення: {ex.Message}");
        }
    }

    private void ShowAnswer(AiConfig cfg, string model, string question, bool isUk)
    {
        var statusText = isUk ? $"Формую відповідь через {model}..." : $"Generating answer via {model}...";
        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {statusText}");

        var langInstruction = isUk ? "Respond strictly in Ukrainian language." : "Respond in English.";
        var askSystemPrompt = $"You are Terminal AI, an expert engineering assistant built for PowerShell and Windows Terminal.\n{langInstruction}\nProvide a concise, direct, helpful explanation to the user's question.";

        try
        {
            var answer = OllamaClient.GenerateRawAsync(cfg.OllamaUrl, model, question, askSystemPrompt, 0.3).GetAwaiter().GetResult();
            if (!string.IsNullOrWhiteSpace(answer))
            {
                var cardTitle = isUk ? "AI Відповідь" : "AI Answer";
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
            Host.UI.WriteErrorLine($"[TerminalAI.AOT] Помилка відповіді: {ex.Message}");
        }
    }

    private void CheckUnknownCmdlet(string command, bool isUk)
    {
        try
        {
            var parts = command.Trim().Split(new[] { ' ', '|', '(', ')' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length > 0)
            {
                var firstWord = parts[0].TrimStart('(').Trim();
                if (Regex.IsMatch(firstWord, @"^[A-Za-z]+-[A-Za-z0-9]+$"))
                {
                    var cmd = SessionState.InvokeCommand.GetCommand(firstWord, CommandTypes.All);
                    if (cmd == null)
                    {
                        var warnTitle = isUk ? "Попередження" : "Warning";
                        var warnMsg = isUk ? $"Команду не знайдено в сесії PowerShell: '{firstWord}'" : $"Command not found in PowerShell session: '{firstWord}'";
                        var warnHint = isUk ? "(Ймовірно, ваше питання мало інформаційний характер або модель вигадала команду)" : "(Likely your query was informational or model hallucinated a cmdlet)";

                        Host.UI.WriteLine(ConsoleColor.DarkYellow, Host.UI.RawUI.BackgroundColor, $"    ⚠ [{warnTitle}] {warnMsg}");
                        Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, $"      {warnHint}\n");
                    }
                }
            }
        }
        catch { }
    }

    private void ShowQuickReference(bool isUk)
    {
        Host.UI.WriteLine("");
        if (isUk)
        {
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "    ✦ Terminal AI Fast (AOT) • Швидка довідка");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭──────────────────────────────────────────────────────────────────╮");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");
            Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, "    │   Використання:  ai-fast <опис команди природною мовою>          │");
            Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, "    │                  aif <опис команди>                              │");
            Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, "    │                  F2 (інлайн-генерація в терміналі)               │");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │   Приклади:                                                      │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast показати 5 процесів з найбільшим CPU                 │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast знайти всі файли .log більше 50MB                    │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast status      (інформація про систему та налаштування) │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast model <модель>   (змінити модель Ollama)             │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast models           (список встановлених моделей)       │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast lang uk | en     (перемкнути мову інтерфейсу)        │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast config           (переглянути конфігурацію JSON)     │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast \"архівувати log\" -Explain  (з поясненням)            │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast \"як працює WSL?\" -Ask      (текстова відповідь)      │");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰──────────────────────────────────────────────────────────────────╯\n");
        }
        else
        {
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "    ✦ Terminal AI Fast (AOT) • Quick Reference");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭──────────────────────────────────────────────────────────────────╮");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");
            Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, "    │   Usage:         ai-fast <natural language prompt>               │");
            Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, "    │                  aif <natural language prompt>                   │");
            Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, "    │                  F2 (inline generation in terminal)              │");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │   Examples:                                                      │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast show top 5 processes by CPU usage                    │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast find all .log files larger than 50MB                 │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast status      (system information & settings)          │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast model <name>     (change active Ollama model)        │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast models           (view installed models)             │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast lang en | uk     (switch interface language)         │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast config           (view configuration JSON)           │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast \"archive logs\" -Explain  (with explanation)          │");
            Host.UI.WriteLine(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    │     ai-fast \"how does WSL work?\" -Ask (text explanation)         │");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰──────────────────────────────────────────────────────────────────╯\n");
        }
    }

    private void ShowStatus(AiConfig cfg, bool isUk)
    {
        var title = isUk ? "Інформація про систему" : "System Information";
        var lblModel = isUk ? "Активна модель:" : "Active Model:";
        var lblFont = isUk ? "Шрифт терміналу:" : "Terminal Font:";
        var lblServer = isUk ? "Локальний сервер:" : "Local Server:";
        var lblHotkey = isUk ? "Швидке доповнення:" : "Quick Inline:";
        var lblLang = isUk ? "Основна мова:" : "Language:";
        var hintModel = isUk ? "Змінити модель:  ai-fast model <назва>" : "Change model:  ai-fast model <name>";
        var hintLang = isUk ? "Змінити мову:    ai-fast lang uk | en" : "Change lang:   ai-fast lang en | uk";

        Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n    ✦ Terminal AI Fast (AOT) • {title}");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╭──────────────────────────────────────────────────────────────────╮");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");

        RenderRow(lblModel, cfg.Model, ConsoleColor.Green);
        RenderRow(lblFont, string.IsNullOrEmpty(cfg.Font) ? "Default" : cfg.Font, ConsoleColor.Cyan);
        RenderRow(lblServer, cfg.OllamaUrl, ConsoleColor.White);
        RenderRow(lblHotkey, $"{cfg.HotkeyChord} / F2", ConsoleColor.Yellow);
        RenderRow(lblLang, cfg.Language == "en" ? "en (English)" : "uk (Українська)", ConsoleColor.White);

        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    │                                                                  │");
        Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "    ╰──────────────────────────────────────────────────────────────────╯\n");

        Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, $"    💡 {hintModel}");
        Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, $"    💡 {hintLang}\n");
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
            var models = OllamaClient.GetModelsAsync(cfg.OllamaUrl).GetAwaiter().GetResult();
            if (models.Count == 0)
            {
                var msg = isUk ? " [TerminalAI] Моделей не знайдено або Ollama не запущена." : " [TerminalAI] No models found or Ollama is not running.";
                Host.UI.WriteLine(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, $"\n   {msg}\n");
                return;
            }

            var title = isUk ? $"Встановлені моделі Ollama (поточна: {cfg.Model}):" : $"Installed Ollama models (active: {cfg.Model}):";
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, $"\n  ✦ {title}\n");

            var colCur = isUk ? "Поточна" : "Active";
            var colName = isUk ? "Назва" : "Name";
            var colSize = isUk ? "Розмір (GB)" : "Size (GB)";
            var colUpd = isUk ? "Оновлено" : "Updated";

            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, string.Format("  {0,-10} {1,-32} {2,-14} {3,-20}", colCur, colName, colSize, colUpd));
            Host.UI.WriteLine(ConsoleColor.DarkCyan, Host.UI.RawUI.BackgroundColor, "  " + new string('─', 78));

            foreach (var m in models)
            {
                var isCur = m.Name.Equals(cfg.Model, StringComparison.OrdinalIgnoreCase);
                var curMarker = isCur ? "--> *" : "   ";
                var sizeGb = Math.Round((double)m.Size / (1024 * 1024 * 1024), 2).ToString("0.00");
                var updatedStr = m.ModifiedAt.HasValue ? m.ModifiedAt.Value.ToString("yyyy-MM-dd HH:mm") : "-";

                var color = isCur ? ConsoleColor.Green : ConsoleColor.White;
                Host.UI.Write(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, string.Format("  {0,-10} ", curMarker));
                Host.UI.Write(color, Host.UI.RawUI.BackgroundColor, string.Format("{0,-32} ", m.Name));
                Host.UI.Write(ConsoleColor.Gray, Host.UI.RawUI.BackgroundColor, string.Format("{0,-14} ", sizeGb));
                Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, updatedStr);
            }
            Host.UI.WriteLine("");
        }
        catch (Exception ex)
        {
            Host.UI.WriteErrorLine($"[TerminalAI.AOT] Помилка отримання моделей: {ex.Message}");
        }
    }

    private void ShowLanguageInfo(AiConfig cfg, bool isUk)
    {
        Host.UI.WriteLine("");
        if (cfg.Language == "en")
        {
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "    ✦ Current language: en (English)");
            Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    💡 Switch language:  ai-fast lang uk  |  ai-fast lang en\n");
        }
        else
        {
            Host.UI.WriteLine(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "    ✦ Поточна мова: uk (Українська)");
            Host.UI.WriteLine(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "    💡 Змінити мову:     ai-fast lang en  |  ai-fast lang uk\n");
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
        catch { }
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
        var tInsert = isUk ? "Вставити" : "Insert";
        var tExplain = isUk ? "Пояснити" : "Explain";
        var tAsk = isUk ? "Текст" : "Text";
        var tCancel = isUk ? "Скасувати" : "Cancel";

        Host.UI.Write(ConsoleColor.Green, Host.UI.RawUI.BackgroundColor, "    [Enter] ");
        Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tEnter}   ");
        Host.UI.Write(ConsoleColor.Yellow, Host.UI.RawUI.BackgroundColor, "[C] ");
        Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tCopy}   ");
        Host.UI.Write(ConsoleColor.Cyan, Host.UI.RawUI.BackgroundColor, "[I] ");
        Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tInsert}   ");
        Host.UI.Write(ConsoleColor.Magenta, Host.UI.RawUI.BackgroundColor, "[X] ");
        Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tExplain}   ");
        Host.UI.Write(ConsoleColor.Blue, Host.UI.RawUI.BackgroundColor, "[A] ");
        Host.UI.Write(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tAsk}   ");
        Host.UI.Write(ConsoleColor.DarkGray, Host.UI.RawUI.BackgroundColor, "[Esc] ");
        Host.UI.WriteLine(ConsoleColor.White, Host.UI.RawUI.BackgroundColor, $"{tCancel}\n");
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
