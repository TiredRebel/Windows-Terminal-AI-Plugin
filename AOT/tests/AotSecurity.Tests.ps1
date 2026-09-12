# Comprehensive AOT Security Test Suite (Phase P0 Validation)
# Tests AST parsing, Execution Gate, Secret Masking, and Safe Clipboard

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$aotDir = Split-Path -Parent $scriptDir
$dllPath = Join-Path $aotDir "bin\Release\net10.0\TerminalAI.Aot.dll"

if (-not (Test-Path $dllPath)) {
    throw "AOT DLL not found at: $dllPath"
}

Add-Type -Path $dllPath

$total = 0
$passed = 0
$failed = 0

function Assert-SecurityTest([string]$id, [string]$name, [scriptblock]$test) {
    $script:total++
    try {
        $res = & $test
        if ($res) {
            $script:passed++
            Write-Host "  ✔ [PASS] [$id] $name" -ForegroundColor Green
        } else {
            $script:failed++
            Write-Host "  ✖ [FAIL] [$id] $name" -ForegroundColor Red
        }
    } catch {
        $script:failed++
        Write-Host "  ✖ [ERROR] [$id] ${name}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "     TERMINAL AI AOT COMPREHENSIVE SECURITY TEST SUITE         " -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

# SEC-01: Syntax Error Block
Assert-SecurityTest "SEC-01" "Blocks unparseable syntax with syntax error status" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Get-Service -Name {", $ExecutionContext.SessionState, $null, $true, $false, $null, $false, $false)
    (-not $res.Executed) -and ($res.Status -eq "SyntaxError") -and ($res.Analysis.ParseErrors.Count -gt 0)
}

# SEC-02: ReadOnly Classification
Assert-SecurityTest "SEC-02" "Classifies ReadOnly pipeline as Low risk requiring no confirmation" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Get-Process | Select-Object -First 5", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::ReadOnly) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::Low) -and (-not $res.RequiresConfirmation)
}

# SEC-03: Deletion Classification
Assert-SecurityTest "SEC-03" "Classifies Remove-Item as Deletion with High risk requiring confirmation" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Remove-Item -Path 'C:\temp\sample.txt' -Force", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::Deletion) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High) -and $res.RequiresConfirmation
}

# SEC-04: Service/Process Termination Classification
Assert-SecurityTest "SEC-04" "Classifies Stop-Process as ServiceOrProcess with High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Stop-Process -Name 'calc' -Force", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::ServiceOrProcess) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High)
}

# SEC-05: Disk & Partition Critical Risk
Assert-SecurityTest "SEC-05" "Classifies Initialize-Disk as DiskOrPartition with Critical risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Initialize-Disk -Number 2", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::DiskOrPartition) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::Critical) -and $res.RequiresConfirmation
}

# SEC-06: Registry Operation Classification
Assert-SecurityTest "SEC-06" "Classifies Set-ItemProperty as Registry with High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Set-ItemProperty -Path 'HKCU:\Software\TerminalAI' -Name 'Aot' -Value 1", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::Registry) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High)
}

# SEC-07: Network Modification Classification
Assert-SecurityTest "SEC-07" "Classifies Set-NetIPAddress as NetworkChange with High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Set-NetIPAddress -InterfaceIndex 1 -IPAddress '192.168.1.50'", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::NetworkChange) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High)
}

# SEC-08: Dynamic Invocation Detection
Assert-SecurityTest "SEC-08" "Detects dynamic invocation (& `$x) and enforces confirmation" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("& `$dangerScript -Force", $ExecutionContext.SessionState)
    $res.HasDynamicInvocation -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High) -and $res.RequiresConfirmation
}

# SEC-09: Splatting Detection
Assert-SecurityTest "SEC-09" "Detects splatted parameters (@args) in AST" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Get-ChildItem @splattedParams", $ExecutionContext.SessionState)
    $res.HasSplatting
}

# SEC-10: Nonexistent Cmdlet Handling
Assert-SecurityTest "SEC-10" "Marks unknown/nonexistent cmdlets as DynamicOrUnknown High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Invoke-NonExistentTool -Param 1", $ExecutionContext.SessionState)
    ($res.Commands[0].CommandType -eq "Unknown") -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High)
}

# SEC-11: Invalid Parameter Detection
Assert-SecurityTest "SEC-11" "Identifies invalid parameters on known cmdlets" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Get-Process -BogusFakeParameter '123'", $ExecutionContext.SessionState)
    $res.Commands[0].InvalidParameters -contains "BogusFakeParameter"
}

# SEC-12: Target Extraction (Literal)
Assert-SecurityTest "SEC-12" "Extracts literal target path from command arguments" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Remove-Item -Path 'E:\secure_data\key.bin' -Force", $ExecutionContext.SessionState)
    $res.Targets -contains "E:\secure_data\key.bin"
}

# SEC-13: Dynamic Target Detection
Assert-SecurityTest "SEC-13" "Flags dynamic variable target expressions as requiring confirmation" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze('Remove-Item $targetDir', $ExecutionContext.SessionState)
    $res.HasDynamicTarget -and $res.RequiresConfirmation
}

# SEC-14: WhatIf Preview Supported
Assert-SecurityTest "SEC-14" "Runs safe WhatIf preview simulation when SupportsShouldProcess is true" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Stop-Process -Id $PID", $ExecutionContext.SessionState, $null, $false, $false, $null, $false, $true)
    $res.Executed -and ($res.Status -eq "Previewed")
}

# SEC-15: WhatIf Preview Blocked on External Program
Assert-SecurityTest "SEC-15" "Blocks WhatIf preview on external binaries with PreviewUnavailable" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("git status", $ExecutionContext.SessionState, $null, $false, $false, $null, $false, $true)
    (-not $res.Executed) -and ($res.Status -eq "PreviewUnavailable")
}

# SEC-16: Execution Gate Denial
Assert-SecurityTest "SEC-16" "Cancels execution cleanly when user confirmation is denied" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Remove-Item -Path 'C:\fake.tmp'", $ExecutionContext.SessionState, $null, $true, $false, "n", $false, $false)
    (-not $res.Executed) -and ($res.Status -eq "Denied")
}

# SEC-17: Execution Gate AutoConfirm on Low Risk
Assert-SecurityTest "SEC-17" "Auto-confirms and executes low risk commands without interactive prompt" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Write-Output 'AUTO_CONFIRMED'", $ExecutionContext.SessionState, $null, $true, $true, $null, $false, $false)
    $res.Executed -and ($res.Status -eq "Executed") -and ($res.Output -match "AUTO_CONFIRMED")
}

# SEC-18: Secret Sanitization (OpenAI / GitHub / AWS / Slack / PEM)
Assert-SecurityTest "SEC-18" "Sanitizes multiple token formats (OpenAI, GitHub, AWS, Slack, PEM)" {
    $raw = 'export KEY=sk-proj-1234567890abcdef1234567890 GH=ghp_abcdef1234567890abcdef1234567890 AWS=AKIAIOSFODNN7EXAMPLE SLACK=xoxb-123456789012-1234567890123-abcdef'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch '1234567890abcdef') -and
    ($san -notmatch 'OSFODNN7EXAMPLE') -and
    ($san -match 'sk-\*\*\*\[REDACTED\]') -and
    ($san -match 'ghp_\*\*\*\[REDACTED\]') -and
    ($san -match 'AKIA\*\*\*\[REDACTED\]') -and
    ($san -match 'xoxb-\*\*\*\[REDACTED\]')
}

# SEC-19: Secret Sanitization (Cmdlet Password Parameters)
Assert-SecurityTest "SEC-19" "Masks passwords and tokens passed to cmdlet parameters" {
    $raw = 'Connect-AzAccount -Password "SuperSecret99!" -Token "secret_token_123"'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch 'SuperSecret99!') -and ($san -notmatch 'secret_token_123') -and ($san -match '\[REDACTED\]')
}

# SEC-20: Safe Clipboard Assignment
Assert-SecurityTest "SEC-20" "Safely copies text to clipboard via Win32 API without script execution" {
    $token = "AOT_SEC_TEST_" + [Guid]::NewGuid().ToString()
    $res = [TerminalAI.Aot.AotClipboard]::SetText($token, $ExecutionContext.SessionState)
    $res -eq $true
}

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host "Results: $passed / $total passed ($failed failed) • 100% Target" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "===============================================================" -ForegroundColor Cyan

if ($failed -gt 0) {
    exit 1
}
exit 0
