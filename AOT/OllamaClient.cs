using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace TerminalAI.Aot;

public record OllamaModelInfo(string Name, long Size, DateTime? ModifiedAt);

public static class OllamaClient
{
    private static readonly HttpClient Http;

    static OllamaClient()
    {
        var handler = new SocketsHttpHandler
        {
            PooledConnectionLifetime = TimeSpan.FromMinutes(15),
            PooledConnectionIdleTimeout = TimeSpan.FromMinutes(5),
            EnableMultipleHttp2Connections = true,
            KeepAlivePingDelay = TimeSpan.FromSeconds(30),
            KeepAlivePingTimeout = TimeSpan.FromSeconds(5),
            KeepAlivePingPolicy = HttpKeepAlivePingPolicy.Always
        };
        Http = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(120)
        };
    }

    public static async Task<string> GenerateAsync(string url, string model, string prompt, string systemPrompt, double temperature, CancellationToken ct = default)
    {
        var raw = await RequestGenerateAsync(url, model, prompt, systemPrompt, temperature, ct).ConfigureAwait(false);
        return CleanOutput(raw);
    }

    public static async Task<string> GenerateRawAsync(string url, string model, string prompt, string systemPrompt, double temperature, CancellationToken ct = default)
    {
        var raw = await RequestGenerateAsync(url, model, prompt, systemPrompt, temperature, ct).ConfigureAwait(false);
        return StripThinking(raw);
    }

    private static async Task<string> RequestGenerateAsync(string url, string model, string prompt, string systemPrompt, double temperature, CancellationToken ct = default)
    {
        var endpoint = $"{url.TrimEnd('/')}/api/generate";
        var payload = new
        {
            model,
            prompt,
            system = systemPrompt,
            stream = false,
            keep_alive = "1h",
            options = new
            {
                temperature
            }
        };

        var json = JsonSerializer.Serialize(payload);
        using var content = new StringContent(json, Encoding.UTF8, "application/json");
        using var resp = await Http.PostAsync(endpoint, content, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();

        using var stream = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct).ConfigureAwait(false);
        if (doc.RootElement.TryGetProperty("response", out var respProp))
        {
            return respProp.GetString() ?? string.Empty;
        }
        return string.Empty;
    }

    public static async Task<List<OllamaModelInfo>> GetModelsAsync(string url, CancellationToken ct = default)
    {
        var list = new List<OllamaModelInfo>();
        try
        {
            var endpoint = $"{url.TrimEnd('/')}/api/tags";
            using var resp = await Http.GetAsync(endpoint, ct).ConfigureAwait(false);
            resp.EnsureSuccessStatusCode();

            using var stream = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct).ConfigureAwait(false);
            if (doc.RootElement.TryGetProperty("models", out var modelsProp) && modelsProp.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in modelsProp.EnumerateArray())
                {
                    var name = el.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    var size = el.TryGetProperty("size", out var s) ? s.GetInt64() : 0L;
                    DateTime? mod = null;
                    if (el.TryGetProperty("modified_at", out var m) && DateTime.TryParse(m.GetString(), out var dt))
                    {
                        mod = dt;
                    }
                    if (!string.IsNullOrEmpty(name))
                    {
                        list.Add(new OllamaModelInfo(name, size, mod));
                    }
                }
            }
        }
        catch { }
        return list;
    }

    public static string StripThinking(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return string.Empty;
        var text = raw.Trim();
        var thinkIdx = text.IndexOf("</think>", StringComparison.OrdinalIgnoreCase);
        if (thinkIdx >= 0)
        {
            return text[(thinkIdx + 8)..].Trim();
        }
        if (text.StartsWith("<think>", StringComparison.OrdinalIgnoreCase))
        {
            var endTag = text.IndexOf("</think>", StringComparison.OrdinalIgnoreCase);
            if (endTag >= 0) return text[(endTag + 8)..].Trim();
        }
        return text;
    }

    public static string CleanOutput(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return string.Empty;

        // 1. Remove <think>...</think>
        var text = StripThinking(raw);

        // 2. Remove ```powershell ... ``` blocks
        if (text.StartsWith("```", StringComparison.Ordinal))
        {
            var firstLineEnd = text.IndexOf('\n');
            if (firstLineEnd > 0)
            {
                var lastTicks = text.LastIndexOf("```", StringComparison.Ordinal);
                if (lastTicks > firstLineEnd)
                {
                    text = text.Substring(firstLineEnd + 1, lastTicks - firstLineEnd - 1).Trim();
                }
            }
        }

        // 3. Remove single backticks
        if (text.StartsWith('`') && text.EndsWith('`') && text.Length > 2)
        {
            text = text[1..^1].Trim();
        }

        return text;
    }
}
