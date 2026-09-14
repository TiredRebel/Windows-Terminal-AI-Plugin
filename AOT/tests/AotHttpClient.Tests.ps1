#Requires -Version 7.0
<#
.SYNOPSIS
    Comprehensive test suite for TerminalAI AOT HTTP Client, Timeout & Resilience (Cycle 8).
.DESCRIPTION
    Validates:
      - CleanOutput and StripThinking
      - TimeoutSeconds wiring and TimeoutException
      - Connection refused friendly error messages
      - Model 404 friendly error messages
      - CancellationToken immediate cancellation
      - English error message parity for either response-language setting
#>

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dllPath = Join-Path $repoRoot "AOT\bin\Release\net10.0\TerminalAI.Aot.dll"

if (-not (Test-Path $dllPath)) {
    Write-Error "AOT DLL not found at: $dllPath. Run 'dotnet build -c Release' first."
    exit 1
}

# Load assembly
Add-Type -Path $dllPath

$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0

function Assert-AotFixture {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$TestBlock
    )
    $script:TotalTests++
    try {
        & $TestBlock
        $script:PassedTests++
        Write-Host "  ✔ [PASS] [$Id] $Description" -ForegroundColor Green
    } catch {
        $script:FailedTests++
        Write-Host "  ✖ [FAIL] [$Id] $Description" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "    TERMINAL AI AOT HTTP CLIENT & TIMEOUT TEST SUITE (CYCLE 8) " -ForegroundColor Cyan
Write-Host "===============================================================`n" -ForegroundColor Cyan

# FIX-HC-01: StripThinking removes <think>...</think> tags cleanly
Assert-AotFixture "FIX-HC-01" "StripThinking strips thinking block from deepseek/qwen responses" {
    $raw = "<think>`nAnalyzing user query...`nNeed to find large files.`n</think>`nGet-ChildItem -Path C:\ -File | Sort-Object Length -Descending"
    $stripped = [TerminalAI.Aot.OllamaClient]::StripThinking($raw)

    if ($stripped.Contains("<think>") -or $stripped.Contains("</think>")) {
        throw "Thinking tags were not stripped"
    }
    if ($stripped -ne "Get-ChildItem -Path C:\ -File | Sort-Object Length -Descending") {
        throw "Stripped output mismatch: '$stripped'"
    }
}

Assert-AotFixture "FIX-HC-02" "CleanOutput removes markdown code blocks and backticks" {
    $markdown = @'
```powershell
Get-Service | Where-Object Status -eq 'Running'
```
'@
    $cleaned = [TerminalAI.Aot.OllamaClient]::CleanOutput($markdown)

    if ($cleaned -ne "Get-Service | Where-Object Status -eq 'Running'") {
        throw "Markdown fences were not removed: '$cleaned'"
    }

    $backticked = '`Get-Process`'
    $cleaned2 = [TerminalAI.Aot.OllamaClient]::CleanOutput($backticked)
    if ($cleaned2 -ne "Get-Process") {
        throw "Backticks were not stripped: '$cleaned2'"
    }
}

# FIX-HC-03: Connection refused produces friendly diagnostic message with Ollama hint (English)
Assert-AotFixture "FIX-HC-03" "Connection refused produces friendly error message in English" {
    $caught = $false
    try {
        # Port 11439 is not running Ollama
        [TerminalAI.Aot.OllamaClient]::GenerateAsync("http://127.0.0.1:11439", "fake-model", "test", "test", 0.1, 10, $false).GetAwaiter().GetResult()
    } catch {
        $caught = $true
        $msg = $_.Exception.ToString()
        if (-not ($msg.Contains("Cannot connect to Ollama service") -or $msg.Contains("ollama serve"))) {
            throw "Error message should contain friendly connection advice, got: '$msg'"
        }
    }
    if (-not $caught) { throw "Expected exception for unreachable connection" }
}

# FIX-HC-04: Connection errors remain English when the Ukrainian response-language setting is active
Assert-AotFixture "FIX-HC-04" "Connection refused produces an English error with the Ukrainian response-language setting" {
    $caught = $false
    try {
        [TerminalAI.Aot.OllamaClient]::GenerateAsync("http://127.0.0.1:11439", "fake-model", "test", "test", 0.1, 10, $true).GetAwaiter().GetResult()
    } catch {
        $caught = $true
        $msg = $_.Exception.ToString()
        if (-not ($msg.Contains("Cannot connect to Ollama service") -or $msg.Contains("ollama serve"))) {
            throw "Error message should contain English connection advice, got: '$msg'"
        }
    }
    if (-not $caught) { throw "Expected exception for unreachable connection" }
}

# FIX-HC-05: CancellationToken cancels request immediately
Assert-AotFixture "FIX-HC-05" "CancellationToken cancels request immediately when triggered" {
    $cts = [System.Threading.CancellationTokenSource]::new()
    $cts.Cancel() # Already canceled
    $caught = $false
    try {
        [TerminalAI.Aot.OllamaClient]::GenerateAsync("http://127.0.0.1:11434", "qwen2.5-coder:7b", "test", "test", 0.1, 60, $false, $cts.Token).GetAwaiter().GetResult()
    } catch {
        $caught = $true
        if (-not ($_.Exception -is [System.OperationCanceledException] -or $_.Exception.InnerException -is [System.OperationCanceledException])) {
            throw "Expected OperationCanceledException, got: $($_.Exception.GetType().FullName)"
        }
    }
    if (-not $caught) { throw "Expected request cancellation" }
}

# FIX-HC-06: GetModelsAsync handles unreachable endpoint safely without throwing
Assert-AotFixture "FIX-HC-06" "GetModelsAsync handles unreachable endpoint without throwing unhandled crash" {
    $models = [TerminalAI.Aot.OllamaClient]::GetModelsAsync("http://127.0.0.1:11439", 2, $false).GetAwaiter().GetResult()
    if ($null -eq $models) { throw "Result should be empty list, not null" }
    if ($models.Count -ne 0) { throw "Models count should be 0 for unreachable host" }
}

# FIX-HC-07: Respects custom timeout and throws TimeoutException
Assert-AotFixture "FIX-HC-07" "Throws TimeoutException when server does not respond within timeoutSeconds" {
    # Set up a local listener that accepts connection but delays response to trigger timeout
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $serverUrl = "http://127.0.0.1:$port"

    $serverTask = [System.Threading.Tasks.Task]::Run([Action]{
        try {
            $client = $listener.AcceptTcpClient()
            Start-Sleep -Seconds 3 # Delay past timeout
            $client.Dispose()
        } catch { }
    })

    $caught = $false
    try {
        # Call with 1-second timeout
        [TerminalAI.Aot.OllamaClient]::GenerateAsync($serverUrl, "test-model", "test", "test", 0.1, 1, $false).GetAwaiter().GetResult()
    } catch {
        $caught = $true
        $msg = $_.Exception.ToString()
        if (-not ($msg.Contains("timed out") -or $msg.Contains("TimeoutException"))) {
            throw "Expected TimeoutException, got: '$msg'"
        }
    } finally {
        $listener.Stop()
    }

    if (-not $caught) { throw "Expected timeout exception" }
}

# FIX-HC-08: Timeout errors remain English when the Ukrainian response-language setting is active
Assert-AotFixture "FIX-HC-08" "TimeoutException stays English with the Ukrainian response-language setting" {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $serverUrl = "http://127.0.0.1:$port"

    $serverTask = [System.Threading.Tasks.Task]::Run([Action]{
        try {
            $client = $listener.AcceptTcpClient()
            Start-Sleep -Seconds 3
            $client.Dispose()
        } catch { }
    })

    $caught = $false
    try {
        [TerminalAI.Aot.OllamaClient]::GenerateAsync($serverUrl, "test-model", "test", "test", 0.1, 1, $true).GetAwaiter().GetResult()
    } catch {
        $caught = $true
        $msg = $_.Exception.ToString()
        if (-not ($msg.Contains("timed out") -or $msg.Contains("TimeoutSeconds"))) {
            throw "Expected Ukrainian timeout message, got: '$msg'"
        }
    } finally {
        $listener.Stop()
    }

    if (-not $caught) { throw "Expected timeout exception" }
}

# FIX-HC-09: Model 404 produces helpful pull advice
Assert-AotFixture "FIX-HC-09" "HTTP 404 response produces model pull recommendation" {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $client = $stream = $null
    $caught = $false
    try {
        $listener.Start()
        $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
        $acceptTask = $listener.AcceptTcpClientAsync()
        $requestTask = [TerminalAI.Aot.OllamaClient]::GenerateAsync("http://127.0.0.1:$port", "nonexistent-model-xyz", "test", "test", 0.1, 10, $false)
        if (-not $acceptTask.Wait(5000)) { throw "Mock server did not receive the request" }
        $client = $acceptTask.GetAwaiter().GetResult()
        $stream = $client.GetStream()
        $response = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
        $stream.Write($response, 0, $response.Length)
        $stream.Flush()
        $requestTask.GetAwaiter().GetResult()
    } catch {
        $caught = $true
        $msg = $_.Exception.ToString()
        if (-not ($msg.Contains("was not found in Ollama") -or $msg.Contains("ollama pull"))) {
            throw "Expected 404 model pull recommendation, got: '$msg'"
        }
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Dispose() }
        $listener.Stop()
    }
    if (-not $caught) { throw "Expected exception for 404 model" }
}

# FIX-HC-10: AiConfig loads default 120s and allows custom TimeoutSeconds
Assert-AotFixture "FIX-HC-10" "AiConfig supports custom TimeoutSeconds configuration" {
    $cfg = [TerminalAI.Aot.AiConfig]::new()
    if ($cfg.TimeoutSeconds -ne 120) {
        throw "Default TimeoutSeconds should be 120, got: $($cfg.TimeoutSeconds)"
    }
    $cfg.TimeoutSeconds = 45
    if ($cfg.TimeoutSeconds -ne 45) {
        throw "Custom TimeoutSeconds was not retained"
    }
}

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "Results: $script:PassedTests / $script:TotalTests passed ($script:FailedTests failed) • 100% Target" -ForegroundColor $(if ($script:FailedTests -eq 0) { "Green" } else { "Red" })
Write-Host "===============================================================`n" -ForegroundColor Cyan

if ($script:FailedTests -gt 0) {
    exit 1
}
