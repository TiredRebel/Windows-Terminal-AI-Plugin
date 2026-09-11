using System;
using System.IO;
using System.Text.Json;

namespace TerminalAI.Aot;

public class AiConfig
{
    public string OllamaUrl { get; set; } = "http://localhost:11434";
    public string Model { get; set; } = "qwen2.5-coder:7b";
    public double Temperature { get; set; } = 0.0;
    public string Language { get; set; } = "uk";
    public bool AutoCopy { get; set; } = false;

    public static AiConfig Load()
    {
        try
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var path = Path.Combine(home, ".terminal-ai", "config.json");
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
}
