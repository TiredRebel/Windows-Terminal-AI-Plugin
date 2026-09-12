# AOT Execution Gate Test Suite
# Tests for TerminalAI.Aot.AotExecutionGate

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

function Assert-GateTest([string]$name, [scriptblock]$test) {
    $script:total++
    try {
        $res = & $test
        if ($res) {
            $script:passed++
            Write-Host "  ✔ [PASS] ${name}" -ForegroundColor Green
        } else {
            $script:failed++
            Write-Host "  ✖ [FAIL] ${name}" -ForegroundColor Red
        }
    } catch {
        $script:failed++
        Write-Host "  ✖ [ERROR] ${name}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== AOT Execution Gate Verification ===" -ForegroundColor Cyan

# 1. Empty Command Handling
Assert-GateTest "Handles empty command safely" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("", $ExecutionContext.SessionState, $null, $false, $false, $null, $false, $false)
    (-not $res.Executed) -and ($res.Status -eq "EmptyCommand")
}

# 2. Syntax Error Blocking
Assert-GateTest "Blocks execution on syntax error" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Get-Process -Name {", $ExecutionContext.SessionState, $null, $false, $false, $null, $false, $false)
    (-not $res.Executed) -and ($res.Status -eq "SyntaxError") -and ($res.Analysis.ParseErrors.Count -gt 0)
}

# 3. Low-Risk AutoConfirm Execution
Assert-GateTest "Executes low-risk command silently when autoConfirm is true" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Write-Output 'LOW_RISK_TEST'", $ExecutionContext.SessionState, $null, $true, $true, $null, $false, $false)
    $res.Executed -and ($res.Status -eq "Executed")
}

# 4. High-Risk AutoConfirm Enforcement (Cannot bypass without explicit confirmation)
Assert-GateTest "High-risk command refuses execution when autoConfirm is true but confirmation is denied" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Stop-Process -Name dummy_proc -Force", $ExecutionContext.SessionState, $null, $true, $false, "n", $false, $false)
    (-not $res.Executed) -and ($res.Status -eq "Denied")
}

# 5. Explicit User Confirmation
Assert-GateTest "Executes high-risk command when explicitly confirmed with 'y'" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Write-Output 'CONFIRMED_HIGH'", $ExecutionContext.SessionState, $null, $false, $true, "y", $false, $false)
    $res.Executed -and ($res.Status -eq "Executed")
}

# 6. WhatIf Preview for Supported Cmdlet
Assert-GateTest "Runs safe WhatIf simulation for cmdlet with SupportsShouldProcess" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Stop-Process -Id $PID", $ExecutionContext.SessionState, $null, $false, $false, $null, $false, $true)
    $res.Executed -and ($res.Status -eq "Previewed")
}

# 7. WhatIf Unavailable for External Programs
Assert-GateTest "Blocks WhatIf preview for external binary programs" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("git status", $ExecutionContext.SessionState, $null, $false, $false, $null, $false, $true)
    (-not $res.Executed) -and ($res.Status -eq "PreviewUnavailable")
}

# 8. Dynamic Invocation Enforcement
Assert-GateTest "Dynamic invocation (& `$cmd) is blocked when denied" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore('& $cmd -Arg 1', $ExecutionContext.SessionState, $null, $true, $false, "n", $false, $false)
    (-not $res.Executed) -and ($res.Status -eq "Denied") -and $res.Analysis.HasDynamicInvocation
}

# 9. Dynamic Target Enforcement
Assert-GateTest "Dynamic target expression requires confirmation even with autoConfirm" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore('Remove-Item $targetPath', $ExecutionContext.SessionState, $null, $true, $false, "n", $false, $false)
    (-not $res.Executed) -and ($res.Status -eq "Denied") -and $res.Analysis.HasDynamicTarget
}

# 10. Output Return Mode
Assert-GateTest "Returns captured pipeline output when returnOutput is true" {
    $res = [TerminalAI.Aot.AotExecutionGate]::ExecuteCore("Write-Output 'AOT_GATE_SUCCESS'", $ExecutionContext.SessionState, $null, $true, $true, $null, $false, $false)
    $res.Executed -and ($res.Status -eq "Executed") -and ($res.Output -match "AOT_GATE_SUCCESS")
}

Write-Host "`nResults: $passed / $total passed ($failed failed)" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) {
    exit 1
}
exit 0
