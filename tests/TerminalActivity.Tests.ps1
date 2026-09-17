#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $root 'AOT/bin/Release/net10.0/TerminalAI.Aot.dll')
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'TerminalAI.psm1'), [ref]$null, [ref]$null)
$names = 'Update-TerminalAiActivityDepth', 'Start-TerminalAiActivity', 'Stop-TerminalAiActivity', 'Invoke-OllamaApi', 'Invoke-AiExecutionGate'
foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names }, $true)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

function Assert-Activity($condition, $message) {
    if (-not $condition) { throw $message }
}

$domain = [AppDomain]::CurrentDomain
$key = 'TerminalAI.ActivityDepth'
$originalDepth = $domain.GetData($key)
$originalWriter = [Console]::Out
$capture = [IO.StringWriter]::new()
$begin = [TerminalAI.Aot.Win32Console].GetMethod('BeginActivityCore', [Reflection.BindingFlags]'NonPublic,Static')
$pair = [char]27 + ']9;4;3;0' + [char]7 + [char]27 + ']9;4;0;0' + [char]7
function Get-CapturedActivity {
    ([regex]::Matches($capture.ToString(), '\x1b\]9;4;[03];0\x07') | ForEach-Object Value) -join ''
}
try {
    $domain.SetData($key, 0)
    [Console]::SetOut([IO.TextWriter]::Synchronized($capture))
    if ([Console]::IsOutputRedirected -or -not $env:WT_SESSION) {
        Assert-Activity (-not (Start-TerminalAiActivity)) 'PowerShell emitted activity in an unsupported host'
        Assert-Activity (-not [TerminalAI.Aot.Win32Console]::BeginActivity()) 'C# emitted activity in an unsupported host'
        Assert-Activity ($capture.ToString() -eq '') 'Escape sequences leaked into redirected output'
    }

    # Exercise the native write boundary without requiring an attached GUI console.
    $active = Update-TerminalAiActivityDepth -Change 1
    $nested = $begin.Invoke($null, @())
    [TerminalAI.Aot.Win32Console]::EndActivity($nested)
    Assert-Activity ($domain.GetData($key) -eq 1) 'Nested C# completion cleared the PowerShell operation'
    Stop-TerminalAiActivity -Active $active
    Stop-TerminalAiActivity -Active $false
    Assert-Activity ($capture.ToString() -eq $pair) 'Incorrect start/reset bytes or duplicate transitions'

    function Start-TerminalAiActivity { Update-TerminalAiActivityDepth -Change 1 }
    function Get-TerminalAiConfig { @{ Model = 'test'; Temperature = 0; OllamaUrl = 'http://127.0.0.1'; TimeoutSeconds = 1 } }
    function Invoke-RestMethod { @{ response = 'result'; message = @{ content = 'chat-result' } } }
    $capture.GetStringBuilder().Clear() > $null
    Assert-Activity ((Invoke-OllamaApi -Prompt 'test') -eq 'result') 'Generation result changed'
    Assert-Activity ((Invoke-OllamaApi -Messages @(@{role='user'; content='test'})) -eq 'chat-result') 'Chat result changed'
    Assert-Activity ($capture.ToString() -eq ($pair + $pair)) 'Request lifecycle did not reset'

    function Invoke-RestMethod { throw 'simulated network failure' }
    $capture.GetStringBuilder().Clear() > $null
    try { Invoke-OllamaApi -Prompt 'test' -ErrorAction Stop } catch { }
    Assert-Activity ($domain.GetData($key) -eq 0 -and $capture.ToString() -eq $pair) 'Network failure left activity enabled'

    $capture.GetStringBuilder().Clear() > $null
    $result = Invoke-AiExecutionGate -Command '42' -SkipAstAnalysis -ConfirmInput yes -ReturnOutput -PassThru
    Assert-Activity ($result.Executed -and $result.Output -eq 42) 'Confirmed execution changed output'
    Assert-Activity ((Get-CapturedActivity) -eq $pair) 'Confirmed execution left activity enabled'
    $capture.GetStringBuilder().Clear() > $null
    Invoke-AiExecutionGate -Command '42' -SkipAstAnalysis -ConfirmInput no > $null
    Assert-Activity ((Get-CapturedActivity) -eq '') 'Denied execution enabled activity'

    $capture.GetStringBuilder().Clear() > $null
    $result = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore('Write-Output 42', $null, $null, $false, $true, 'yes', $false, $false)
    Assert-Activity ($result.Executed -and [int]$result.Output[0] -eq 42) 'C# execution changed output'
    $expected = if (-not [Console]::IsOutputRedirected -and $env:WT_SESSION) { $pair } else { '' }
    Assert-Activity ((Get-CapturedActivity) -eq $expected) 'C# execution did not reset activity'

    # PowerShell.Stop uses the same pipeline stopping path as host Ctrl+C.
    $ps = [Management.Automation.PowerShell]::Create()
    try {
        $source = ($names | ForEach-Object { "function $_ { $((Get-Command $_).Definition) }" }) -join "`n"
        $source += "`nfunction Get-TerminalAiConfig { @{Model='test'; OllamaUrl='http://127.0.0.1'; Temperature=0; TimeoutSeconds=60} }"
        $source += "`nfunction Invoke-RestMethod { Start-Sleep -Seconds 30 }"
        $ps.AddScript($source + "`nInvoke-OllamaApi -Prompt test") > $null
        $capture.GetStringBuilder().Clear() > $null
        $pending = $ps.BeginInvoke()
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while ($domain.GetData($key) -ne 1 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
        Assert-Activity ($domain.GetData($key) -eq 1) 'Cancellation test never started work'
        $ps.Stop()
        try { $ps.EndInvoke($pending) > $null } catch { }
        Assert-Activity ($domain.GetData($key) -eq 0 -and $capture.ToString() -eq $pair) 'Pipeline cancellation failed to run finally cleanup'
    }
    finally { $ps.Dispose() }

    # Exercise the cmdlet's StopProcessing token against a real pending HTTP request.
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $cmdlet = [TerminalAI.Aot.InvokeAiCommandFastCmdlet]::new()
    $flags = [Reflection.BindingFlags]'NonPublic,Instance'
    $cancellation = $cmdlet.GetType().GetField('requestCancellation', $flags).GetValue($cmdlet)
    $client = $null
    try {
        $capture.GetStringBuilder().Clear() > $null
        $accept = $listener.AcceptTcpClientAsync()
        $port = $listener.LocalEndpoint.Port
        $request = [TerminalAI.Aot.OllamaClient]::GenerateAsync("http://127.0.0.1:$port", 'test', 'test', 'test', 0, 60, $false, $cancellation.Token)
        Assert-Activity ($accept.Wait(3000)) 'HTTP cancellation test never connected'
        $client = $accept.GetAwaiter().GetResult()
        $cmdlet.GetType().GetMethod('StopProcessing', $flags).Invoke($cmdlet, @()) > $null
        $cancelled = $false
        try { $request.GetAwaiter().GetResult() > $null }
        catch { $cancelled = $_.Exception -is [OperationCanceledException] -or $_.Exception.InnerException -is [OperationCanceledException] }
        Assert-Activity ($cancelled -and $domain.GetData($key) -eq 0) 'C# StopProcessing did not cancel HTTP or clear activity'
        if (-not [Console]::IsOutputRedirected -and $env:WT_SESSION) {
            Assert-Activity ((Get-CapturedActivity) -eq $pair) 'C# cancellation emitted incorrect lifecycle bytes'
        }
    }
    finally {
        if ($client) { $client.Dispose() }
        $listener.Stop()
        $cancellation.Dispose()
    }
}
finally {
    [Console]::SetOut($originalWriter)
    $domain.SetData($key, $originalDepth)
    $capture.Dispose()
}
[Console]::WriteLine('PASS: activity bytes, mixed nesting, redirection, generation/chat, errors, execution, denial, PowerShell/C# cancellation')
