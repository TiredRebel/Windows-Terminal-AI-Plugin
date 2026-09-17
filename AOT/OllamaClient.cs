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
        // Use infinite timeout on HttpClient and control per-request timeouts with CancellationTokenSource
        Http = new HttpClient(handler)
        {
            Timeout = Timeout.InfiniteTimeSpan
        };
    }

    public static async Task<string> GenerateAsync(
        string url,
        string model,
        string prompt,
        string systemPrompt,
        double temperature,
        int timeoutSeconds = 120,
        bool isUk = false,
        CancellationToken ct = default)
    {
        var raw = await RequestGenerateAsync(url, model, prompt, systemPrompt, temperature, timeoutSeconds, isUk, ct).ConfigureAwait(false);
        return CleanOutput(raw);
    }

    public static async Task<string> GenerateRawAsync(
        string url,
        string model,
        string prompt,
        string systemPrompt,
        double temperature,
        int timeoutSeconds = 120,
        bool isUk = false,
        CancellationToken ct = default)
    {
        var raw = await RequestGenerateAsync(url, model, prompt, systemPrompt, temperature, timeoutSeconds, isUk, ct).ConfigureAwait(false);
        return StripThinking(raw);
    }

    private static async Task<string> RequestGenerateAsync(
        string url,
        string model,
        string prompt,
        string systemPrompt,
        double temperature,
        int timeoutSeconds = 120,
        bool isUk = false,
        CancellationToken ct = default)
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

        int effectiveTimeout = timeoutSeconds > 0 ? timeoutSeconds : 120;
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(effectiveTimeout));

        bool activity = Win32Console.BeginActivity();
        try
        {
            using var resp = await Http.PostAsync(endpoint, content, cts.Token).ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode)
            {
                if (resp.StatusCode == System.Net.HttpStatusCode.NotFound)
                {
                    var notFoundMsg = $"Model '{model}' was not found in Ollama (HTTP 404). Run 'ollama pull {model}' or choose another model via 'aif model <name>'.";
                    throw new InvalidOperationException(notFoundMsg);
                }
                var rawErr = await resp.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false);
                throw new HttpRequestException($"HTTP {(int)resp.StatusCode} ({resp.ReasonPhrase}): {rawErr}");
            }

            using var stream = await resp.Content.ReadAsStreamAsync(cts.Token).ConfigureAwait(false);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cts.Token).ConfigureAwait(false);
            if (doc.RootElement.TryGetProperty("response", out var respProp))
            {
                return respProp.GetString() ?? string.Empty;
            }
            return string.Empty;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            var timeoutMsg = $"Ollama request timed out after {effectiveTimeout}s for model '{model}'. You can increase 'TimeoutSeconds' in config or use a faster model.";
            throw new TimeoutException(timeoutMsg);
        }
        catch (HttpRequestException ex) when (ex.InnerException is System.Net.Sockets.SocketException sockEx && sockEx.SocketErrorCode == System.Net.Sockets.SocketError.ConnectionRefused)
        {
            var connMsg = $"Cannot connect to Ollama service at '{url}'. Please ensure Ollama is installed and running ('ollama serve').";
            throw new InvalidOperationException(connMsg, ex);
        }
        catch (JsonException ex)
        {
            var jsonMsg = $"Received malformed JSON response from Ollama: {ex.Message}";
            throw new InvalidOperationException(jsonMsg, ex);
        }
        finally
        {
            Win32Console.EndActivity(activity);
        }
    }

    public static async Task<List<OllamaModelInfo>> GetModelsAsync(
        string url,
        int timeoutSeconds = 15,
        bool isUk = false,
        CancellationToken ct = default)
    {
        var list = new List<OllamaModelInfo>();
        int effectiveTimeout = timeoutSeconds > 0 ? timeoutSeconds : 15;
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(effectiveTimeout));

        try
        {
            var endpoint = $"{url.TrimEnd('/')}/api/tags";
            using var resp = await Http.GetAsync(endpoint, cts.Token).ConfigureAwait(false);
            resp.EnsureSuccessStatusCode();

            using var stream = await resp.Content.ReadAsStreamAsync(cts.Token).ConfigureAwait(false);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cts.Token).ConfigureAwait(false);
            if (doc.RootElement.TryGetProperty("models", out var modelsProp) && modelsProp.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in modelsProp.EnumerateArray())
                {
                    var name = el.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    var size = el.TryGetProperty("size", out var s) && s.TryGetInt64(out var sz) ? sz : 0L;
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
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[OllamaClient.GetModelsAsync] Failed to retrieve models: {ex.Message}");
        }
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
