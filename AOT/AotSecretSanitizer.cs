using System;
using System.Text.RegularExpressions;

namespace TerminalAI.Aot;

public static class AotSecretSanitizer
{
    private static readonly Regex OpenAiKeyRegex = new(@"\b(sk-)[a-zA-Z0-9_\-]{16,}\b", RegexOptions.Compiled);
    private static readonly Regex GitHubPatRegex = new(@"\b(ghp_)[a-zA-Z0-9]{16,}\b", RegexOptions.Compiled);
    private static readonly Regex GitHubFineGrainedRegex = new(@"\b(github_pat_)[a-zA-Z0-9_]{16,}\b", RegexOptions.Compiled);
    private static readonly Regex AwsKeyRegex = new(@"\b(AKIA)[0-9A-Z]{16}\b", RegexOptions.Compiled);
    private static readonly Regex SlackTokenRegex = new(@"\b(xox[baprs]-)[0-9a-zA-Z\-]{16,}\b", RegexOptions.Compiled);
    private static readonly Regex PemKeyRegex = new(@"-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----", RegexOptions.Compiled);
    private static readonly Regex CmdParameterSecretRegex = new(@"(?i)(-(?:Password|Token|ApiKey|Secret|AccessKey)\s+)(['""]?)[^'""\s]+(\2)", RegexOptions.Compiled);
    private static readonly Regex KeyValueSecretRegex = new(@"(?i)\b((?:password|secret|apikey|api_key|access_token|private_key)\s*[:=]\s*)(['""]?)[^'""\s\r\n]+(\2)", RegexOptions.Compiled);

    public static string Sanitize(string? input)
    {
        if (string.IsNullOrEmpty(input)) return string.Empty;

        string result = input;
        result = PemKeyRegex.Replace(result, "[REDACTED PRIVATE KEY]");
        result = OpenAiKeyRegex.Replace(result, "$1***[REDACTED]");
        result = GitHubPatRegex.Replace(result, "$1***[REDACTED]");
        result = GitHubFineGrainedRegex.Replace(result, "$1***[REDACTED]");
        result = AwsKeyRegex.Replace(result, "$1***[REDACTED]");
        result = SlackTokenRegex.Replace(result, "$1***[REDACTED]");
        result = CmdParameterSecretRegex.Replace(result, "$1$2***[REDACTED]$2");
        result = KeyValueSecretRegex.Replace(result, "$1$2***[REDACTED]$2");

        return result;
    }

    public static bool ContainsSecret(string? input)
    {
        if (string.IsNullOrEmpty(input)) return false;

        return PemKeyRegex.IsMatch(input) ||
               OpenAiKeyRegex.IsMatch(input) ||
               GitHubPatRegex.IsMatch(input) ||
               GitHubFineGrainedRegex.IsMatch(input) ||
               AwsKeyRegex.IsMatch(input) ||
               SlackTokenRegex.IsMatch(input) ||
               CmdParameterSecretRegex.IsMatch(input) ||
               KeyValueSecretRegex.IsMatch(input);
    }
}
