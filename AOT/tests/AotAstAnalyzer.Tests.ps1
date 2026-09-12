# AOT AST Analyzer Test Suite
# Tests for TerminalAI.Aot.AotCommandAstAnalyzer

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

function Assert-AstTest([string]$name, [scriptblock]$test) {
    $script:total++
    try {
        $res = & $test
        if ($res) {
            $script:passed++
            Write-Host "  ✔ [PASS] $name" -ForegroundColor Green
        } else {
            $script:failed++
            Write-Host "  ✖ [FAIL] $name" -ForegroundColor Red
        }
    } catch {
        $script:failed++
        Write-Host "  ✖ [ERROR] ${name}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== AOT AST Analyzer Verification ===" -ForegroundColor Cyan

# 1. Syntax Error Detection
Assert-AstTest "Blocks invalid syntax with ParseErrors" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Get-Process -Name {", $ExecutionContext.SessionState)
    (-not $res.IsValid) -and ($res.ParseErrors.Count -gt 0) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High)
}

# 2. ReadOnly Classification
Assert-AstTest "Classifies Get-Process as ReadOnly / Low risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Get-Process | Select-Object -First 5", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::ReadOnly) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::Low) -and (-not $res.RequiresConfirmation)
}

# 3. Deletion Classification
Assert-AstTest "Classifies Remove-Item as Deletion / High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Remove-Item -Path 'C:\temp\file.txt' -Force", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::Deletion) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High) -and $res.RequiresConfirmation
}

# 4. ServiceOrProcess Classification
Assert-AstTest "Classifies Stop-Process as ServiceOrProcess / High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Stop-Process -Name 'calc' -Force", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::ServiceOrProcess) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High)
}

# 5. Registry Classification
Assert-AstTest "Classifies Set-ItemProperty as Registry / High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Set-ItemProperty -Path 'HKCU:\Software\Test' -Name 'Val' -Value 1", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::Registry) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High)
}

# 6. DiskOrPartition Classification
Assert-AstTest "Classifies Initialize-Disk as DiskOrPartition / Critical risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Initialize-Disk -Number 2", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::DiskOrPartition) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::Critical) -and $res.RequiresConfirmation
}

# 7. NetworkChange Classification
Assert-AstTest "Classifies Set-NetIPAddress as NetworkChange / High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Set-NetIPAddress -InterfaceIndex 1 -IPAddress '192.168.1.1'", $ExecutionContext.SessionState)
    $res.IsValid -and ($res.OverallCategory -eq [TerminalAI.Aot.CommandCategory]::NetworkChange) -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High)
}

# 8. Dynamic Invocation
Assert-AstTest "Detects dynamic invocation (& `$cmd) as High risk" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("& `$dynamicCmd -Arg 1", $ExecutionContext.SessionState)
    $res.HasDynamicInvocation -and ($res.OverallRisk -eq [TerminalAI.Aot.CommandRiskLevel]::High) -and $res.RequiresConfirmation
}

# 9. Target Extraction
Assert-AstTest "Extracts literal targets from command" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Remove-Item -Path 'E:\data\log.txt' -Force", $ExecutionContext.SessionState)
    $res.Targets -contains "E:\data\log.txt"
}

# 10. Dynamic Target Detection
Assert-AstTest "Flags dynamic target expression as requiring confirmation" {
    $res = [TerminalAI.Aot.AotCommandAstAnalyzer]::Analyze("Remove-Item `$targetFile", $ExecutionContext.SessionState)
    $res.HasDynamicTarget -and $res.RequiresConfirmation
}

Write-Host "`nResults: $passed / $total passed ($failed failed)" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) {
    exit 1
}
exit 0
