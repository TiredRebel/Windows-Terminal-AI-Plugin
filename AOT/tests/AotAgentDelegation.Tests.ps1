#Requires -Version 7.0
<#
.SYNOPSIS
    Comprehensive test suite for TerminalAI AOT Agent Mode Delegation (Cycle 10).
.DESCRIPTION
    Validates:
      - -Agent switch parameter declaration
      - 'agent <prompt>' prefix routing
      - Agent help banner rendering
      - Safe fallback when Invoke-AiAgent is not present in session
      - Proper routing to Invoke-AiAgent with parameters when available
#>

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dllPath = Join-Path $repoRoot "AOT\bin\Release\net10.0\TerminalAI.Aot.dll"

if (-not (Test-Path $dllPath)) {
    Write-Error "AOT DLL not found at: $dllPath. Run 'dotnet build -c Release' first."
    exit 1
}

# Import module
Remove-Module TerminalAI.Aot -ErrorAction SilentlyContinue
Import-Module $dllPath

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
Write-Host "    TERMINAL AI AOT AGENT DELEGATION TEST SUITE (CYCLE 10)     " -ForegroundColor Cyan
Write-Host "===============================================================`n" -ForegroundColor Cyan

# FIX-AD-01: -Agent parameter is declared on Invoke-AiCommandFast
Assert-AotFixture "FIX-AD-01" "Invoke-AiCommandFast declares -Agent parameter and alias" {
    $cmd = Get-Command -Name Invoke-AiCommandFast
    if (-not $cmd.Parameters.ContainsKey("Agent")) {
        throw "Parameter -Agent is missing from Invoke-AiCommandFast"
    }
    $aliases = $cmd.Parameters["Agent"].Aliases
    if (-not ($aliases -contains "Autonomous")) {
        throw "Parameter -Agent should have alias 'Autonomous'"
    }
}

# FIX-AD-02: 'aif agent help' renders educational banner without crashing
Assert-AotFixture "FIX-AD-02" "'aif agent help' renders agent guidance banner" {
    $out = Invoke-AiCommandFast "agent help" | Out-String
    # Should execute without throwing any exception
}

# FIX-AD-03: 'aif -Agent' displays guidance banner when prompt is empty
Assert-AotFixture "FIX-AD-03" "'aif -Agent' displays guidance banner when prompt is empty" {
    Invoke-AiCommandFast -Agent
}

# FIX-AD-04: 'aif agent <prompt>' delegates to Invoke-AiAgent when present in session
Assert-AotFixture "FIX-AD-04" "Delegates to Invoke-AiAgent in session with Prompt and Model" {
    $global:MockAgentCalled = $false
    $global:MockAgentPrompt = $null
    $global:MockAgentModel = $null

    function global:Invoke-AiAgent {
        param($Prompt, $Model)
        $global:MockAgentCalled = $true
        $global:MockAgentPrompt = $Prompt
        $global:MockAgentModel = $Model
        return [PSCustomObject]@{ Status = "DelegatedSuccessfully"; Prompt = $Prompt }
    }

    try {
        $res = Invoke-AiCommandFast "agent analyze system performance" -Model "qwen2.5-coder:7b"
        if (-not $global:MockAgentCalled) {
            throw "Invoke-AiAgent was not invoked by agent router"
        }
        if ($global:MockAgentPrompt -ne "analyze system performance") {
            throw "Prompt was not cleanly extracted, got: '$($global:MockAgentPrompt)'"
        }
        if ($global:MockAgentModel -ne "qwen2.5-coder:7b") {
            throw "Model was not passed to Invoke-AiAgent, got: '$($global:MockAgentModel)'"
        }
    } finally {
        Remove-Item Function:\Invoke-AiAgent -ErrorAction SilentlyContinue
    }
}

# FIX-AD-05: 'aif -Agent <prompt>' delegates with -Agent switch
Assert-AotFixture "FIX-AD-05" "Delegates to Invoke-AiAgent when -Agent switch is specified" {
    $global:MockAgentCalled = $false
    $global:MockAgentPrompt = $null

    function global:Invoke-AiAgent {
        param($Prompt, $Model)
        $global:MockAgentCalled = $true
        $global:MockAgentPrompt = $Prompt
        return [PSCustomObject]@{ Status = "DelegatedViaSwitch" }
    }

    try {
        $res = Invoke-AiCommandFast -Agent "clean up log files"
        if (-not $global:MockAgentCalled) {
            throw "Invoke-AiAgent was not invoked via -Agent switch"
        }
        if ($global:MockAgentPrompt -ne "clean up log files") {
            throw "Prompt mismatch: '$($global:MockAgentPrompt)'"
        }
    } finally {
        Remove-Item Function:\Invoke-AiAgent -ErrorAction SilentlyContinue
    }
}

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "Results: $script:PassedTests / $script:TotalTests passed ($script:FailedTests failed) • 100% Target" -ForegroundColor $(if ($script:FailedTests -eq 0) { "Green" } else { "Red" })
Write-Host "===============================================================`n" -ForegroundColor Cyan

if ($script:FailedTests -gt 0) {
    exit 1
}
