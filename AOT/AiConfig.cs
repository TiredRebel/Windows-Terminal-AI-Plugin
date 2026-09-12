using System;
using System.IO;
using System.Text.Json;

namespace TerminalAI.Aot;

public class AiConfig
{
    public string OllamaUrl { get; set; } = "http://localhost:11434";
    public string Model { get; set; } = "qwen2.5-coder:7b";
    public string Language { get; set; } = "uk";
    public string Font { get; set; } = "Cascadia Code";
    public double Temperature { get; set; } = 0.2;
    public int TimeoutSeconds { get; set; } = 120;
    public string HotkeyChord { get; set; } = "Ctrl+Alt+A";
    public bool AutoCopy { get; set; } = false;
    public bool ShowExplanation { get; set; } = true;

    private static string GetConfigFilePath()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var dir = Path.Combine(home, ".terminal-ai");
        if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
        return Path.Combine(dir, "config.json");
    }

    public static AiConfig Load()
    {
        try
        {
            var path = GetConfigFilePath();
            if (File.Exists(path))
            {
                var json = File.ReadAllText(path);
                var cfg = JsonSerializer.Deserialize<AiConfig>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                if (cfg != null) return cfg;
            }
        }
        catch { }
        return new AiConfig();
    }

    public void Save()
    {
        try
        {
            var path = GetConfigFilePath();
            var options = new JsonSerializerOptions { WriteIndented = true };
            var json = JsonSerializer.Serialize(this, options);
            File.WriteAllText(path, json);
        }
        catch { }
    }
}

