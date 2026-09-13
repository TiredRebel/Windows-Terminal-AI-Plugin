# tests/P0-SecurityGate.Tests.ps1 - P0 AST analyzer and execution gate tests

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "     Running P0 Security Gate & Preview Engine tests (Cycle 4) " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Import TerminalAI
Import-Module (Join-Path $PSScriptRoot "..\TerminalAI.psd1") -Force

$total = 0
$passed = 0
$failed = 0

function Assert-Fixture {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$TestBlock
    )
    $script:total++
    Write-Host "[$Id] $Description ... " -NoNewline -ForegroundColor White
    try {
        $res = & $TestBlock
        if ($res -eq $true) {
            $script:passed++
            Write-Host "PASSED" -ForegroundColor Green
        } else {
            $script:failed++
            Write-Host "FAILED (condition not met)" -ForegroundColor Red
        }
    } catch {
        $script:failed++
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# FIX-01: ReadOnly cmdlet
Assert-Fixture "FIX-01" "Safe read (Get-Process -Name explorer)" {
    $r = Test-AiCommandAst -Command "Get-Process -Name explorer"
    return ($r.IsValid -and $r.OverallRisk -eq "Low" -and $r.OverallCategory -eq "ReadOnly" -and $r.Targets -contains "explorer")
}

# FIX-02: Multi-cmdlet Pipeline
Assert-Fixture "FIX-02" "Pipeline with multiple cmdlets (Get-Process | Where-Object { `$_.CPU -gt 10 })" {
    $r = Test-AiCommandAst -Command 'Get-Process | Where-Object { $_.CPU -gt 10 }'
    return ($r.IsValid -and $r.OverallRisk -eq "Low" -and $r.Commands.Count -ge 2)
}

# FIX-03: Nested Invocation (Dynamic target)
Assert-Fixture "FIX-03" "Nested command invocation (Get-Service -Name `$(Get-Content .\svc.txt))" {
    $r = Test-AiCommandAst -Command 'Get-Service -Name $(Get-Content .\svc.txt)'
    return ($r.IsValid -and ($r.Targets -contains "Unknown target" -or $r.HasDynamicTarget))
}

# FIX-04: Nonexistent Cmdlet
Assert-Fixture "FIX-04" "Unknown cmdlet (Invoke-FakeNonExistentCmdlet -Path C:\)" {
    $r = Test-AiCommandAst -Command "Invoke-FakeNonExistentCmdlet -Path C:\"
    return ($r.Commands[0].CommandType -eq "Unknown" -and $r.OverallRisk -in @("High", "Unknown"))
}

# FIX-05: Invalid Parameter
Assert-Fixture "FIX-05" "Cmdlet with an invalid parameter (Get-Process -InvalidParam123 'test')" {
    $r = Test-AiCommandAst -Command "Get-Process -InvalidParam123 'test'"
    return ($r.Commands[0].InvalidParameters -contains "InvalidParam123" -and -not [string]::IsNullOrEmpty($r.Commands[0].InvalidParameters))
}

# FIX-06: Alias Resolution
Assert-Fixture "FIX-06" "Alias recognition (gps | ? CPU -gt 10)" {
    $r = Test-AiCommandAst -Command "gps | ? CPU -gt 10"
    $c0 = $r.Commands[0]
    return ($c0.ResolvedTarget -eq "Get-Process" -and $r.OverallRisk -eq "Low")
}

# FIX-07: External Binary
Assert-Fixture "FIX-07" "External binary (git status)" {
    $r = Test-AiCommandAst -Command "git status"
    return ($r.Commands[0].CommandType -eq "ExternalProgram" -and -not $r.Commands[0].SupportsWhatIf)
}

# FIX-08: Deletion
Assert-Fixture "FIX-08" "File deletion (Remove-Item -Path C:\temp\test.txt -Force)" {
    $r = Test-AiCommandAst -Command "Remove-Item -Path C:\temp\test.txt -Force"
    return ($r.OverallCategory -eq "Deletion" -and $r.OverallRisk -eq "High" -and $r.Targets -contains "C:\temp\test.txt")
}

# FIX-09: Process Termination
Assert-Fixture "FIX-09" "Process termination (Stop-Process -Name notepad -Force)" {
    $r = Test-AiCommandAst -Command "Stop-Process -Name notepad -Force"
    return ($r.OverallCategory -eq "ServiceOrProcess" -and $r.OverallRisk -eq "High" -and $r.Targets -contains "notepad")
}

# FIX-10: Registry Operation
Assert-Fixture "FIX-10" "Registry operation (Set-ItemProperty -Path 'HKCU:\Software\Test' -Name 'Val' -Value 1)" {
    $r = Test-AiCommandAst -Command "Set-ItemProperty -Path 'HKCU:\Software\Test' -Name 'Val' -Value 1"
    return ($r.OverallCategory -eq "Registry" -and $r.OverallRisk -eq "High")
}

# FIX-11: Disk / Partition
Assert-Fixture "FIX-11" "Disk operation (Initialize-Disk -Number 2)" {
    $r = Test-AiCommandAst -Command "Initialize-Disk -Number 2"
    return ($r.OverallCategory -eq "DiskOrPartition" -and $r.OverallRisk -in @("High", "Critical"))
}

# FIX-12: Network Modification
Assert-Fixture "FIX-12" "Network change (Set-NetIPAddress -InterfaceIndex 1 -IPAddress 192.168.1.1)" {
    $r = Test-AiCommandAst -Command "Set-NetIPAddress -InterfaceIndex 1 -IPAddress 192.168.1.1"
    return ($r.OverallCategory -eq "NetworkChange" -and $r.OverallRisk -eq "High")
}

# FIX-13: Dynamic Invocation
Assert-Fixture "FIX-13" "Dynamic invocation (& `$dynamicCmd -Arg1 `$val)" {
    $r = Test-AiCommandAst -Command '& $dynamicCmd -Arg1 $val'
    return ($r.HasDynamicInvocation -and $r.OverallRisk -in @("High", "Unknown"))
}

# FIX-14: Splatting
Assert-Fixture "FIX-14" "Splatting (Get-ChildItem @splatParams)" {
    $r = Test-AiCommandAst -Command 'Get-ChildItem @splatParams'
    return ($r.HasSplatting)
}

# FIX-15: Syntax Error
Assert-Fixture "FIX-15" "Invalid syntax (Get-Process -Name {)" {
    $r = Test-AiCommandAst -Command "Get-Process -Name {"
    return (-not $r.IsValid -and $r.ParseErrors.Count -gt 0)
}

# FIX-16: Literal Path Target
Assert-Fixture "FIX-16" "Literal target extraction (Remove-Item 'E:\data\file.log')" {
    $r = Test-AiCommandAst -Command "Remove-Item 'E:\data\file.log'"
    return ($r.Targets -contains "E:\data\file.log")
}

# FIX-17: Undetermined Dynamic Target
Assert-Fixture "FIX-17" "Unresolved dynamic target (Remove-Item `$someVar)" {
    $r = Test-AiCommandAst -Command 'Remove-Item $someVar'
    return ($r.Targets -contains "Unknown target" -or $r.HasDynamicTarget)
}

# FIX-18: Execution Gate blocks syntax error without executing
Assert-Fixture "FIX-18" "Execution gate blocks syntax errors" {
    $res = Invoke-AiExecutionGate -Command "Get-Process -Name {" -PassThru
    return ($res.Executed -eq $false -and $res.Status -eq "SyntaxError" -and $res.Analysis.ParseErrors.Count -gt 0)
}

# FIX-19: Execution Gate blocks High risk command when user denies
Assert-Fixture "FIX-19" "Execution gate blocks a dangerous command when denied" {
    $res = Invoke-AiExecutionGate -Command "Remove-Item -Path 'C:\fake_test_123.txt' -Force" -ConfirmInput "n" -PassThru
    return ($res.Executed -eq $false -and $res.Status -eq "Denied" -and $res.Analysis.OverallRisk -eq "High")
}

# FIX-20: Execution Gate executes Low risk command with -AutoConfirm directly
Assert-Fixture "FIX-20" "Execution gate runs a low-risk command with AutoConfirm" {
    $res = Invoke-AiExecutionGate -Command "Write-Output 'P0_GATE_TEST_SUCCESS'" -AutoConfirm -PassThru -ReturnOutput
    return ($res.Executed -eq $true -and $res.Status -eq "Executed" -and $res.Output -eq "P0_GATE_TEST_SUCCESS")
}

# FIX-21: Execution Gate requires confirmation for High risk command even with -AutoConfirm
Assert-Fixture "FIX-21" "Execution gate never silently runs a high-risk command with AutoConfirm" {
    $res = Invoke-AiExecutionGate -Command "Stop-Process -Name fake_proc -Force" -AutoConfirm -ConfirmInput "n" -PassThru
    return ($res.Executed -eq $false -and $res.Status -eq "Denied")
}

# FIX-22: Execution Gate executes High risk command when explicitly confirmed
Assert-Fixture "FIX-22" "Execution gate runs a command after explicit confirmation" {
    $res = Invoke-AiExecutionGate -Command "Write-Output 'CONFIRMED_TEST'" -ConfirmInput "y" -PassThru -ReturnOutput
    return ($res.Executed -eq $true -and $res.Status -eq "Executed" -and $res.Output -eq "CONFIRMED_TEST")
}

# FIX-23: Execution Gate with -ReturnOutput returns pipeline output correctly
Assert-Fixture "FIX-23" "Execution gate returns pipeline output with ReturnOutput" {
    $out = Invoke-AiExecutionGate -Command "Get-Process -Id $PID | Select-Object -ExpandProperty ProcessName" -AutoConfirm -ReturnOutput
    return (-not [string]::IsNullOrWhiteSpace($out) -and $out -in @("pwsh", "powershell"))
}

# FIX-24: Dynamic invocation requires confirmation even with -AutoConfirm
Assert-Fixture "FIX-24" "Dynamic invocation requires confirmation even with AutoConfirm" {
    $res = Invoke-AiExecutionGate -Command '& $cmd -Arg 1' -AutoConfirm -ConfirmInput "n" -PassThru
    return ($res.Executed -eq $false -and $res.Status -eq "Denied" -and $res.Analysis.HasDynamicInvocation)
}

# FIX-25: Dynamic target requires confirmation even with -AutoConfirm
Assert-Fixture "FIX-25" "Dynamic targets require confirmation even with AutoConfirm" {
    $res = Invoke-AiExecutionGate -Command 'Remove-Item $targetPath' -AutoConfirm -ConfirmInput "n" -PassThru
    return ($res.Executed -eq $false -and $res.Status -eq "Denied" -and ($res.Analysis.HasDynamicTarget -or $res.Analysis.Targets -contains "Unknown target"))
}

# FIX-26: Command supporting WhatIf has CanPreview = $true
Assert-Fixture "FIX-26" "SupportsShouldProcess permits preview" {
    $r = Test-AiCommandAst -Command "Stop-Process -Name dummy_proc -Force"
    return ($r.CanPreview -eq $true -and $r.Commands[0].SupportsWhatIf -eq $true)
}

# FIX-27: External program has CanPreview = $false
Assert-Fixture "FIX-27" "External programs disable automatic WhatIf preview" {
    $r = Test-AiCommandAst -Command "git status"
    return ($r.CanPreview -eq $false -and -not [string]::IsNullOrWhiteSpace($r.PreviewUnavailableReason))
}

# FIX-28: Multi-stage pipeline with ReadOnly + WhatIf cmdlet
Assert-Fixture "FIX-28" "ReadOnly plus WhatIf pipeline supports preview" {
    $r = Test-AiCommandAst -Command "Get-Process | Stop-Process"
    return ($r.CanPreview -eq $true)
}

# FIX-29: Execution Gate safely previews command when CanPreview is $true
Assert-Fixture "FIX-29" "Execution gate returns Previewed for a supported command" {
    $res = Invoke-AiExecutionGate -Command "Stop-Process -Id $PID" -WhatIf -PassThru
    return ($res.Executed -eq $true -and $res.Status -eq "Previewed")
}

# FIX-30: Execution Gate blocks WhatIf when CanPreview is $false
Assert-Fixture "FIX-30" "Execution gate blocks WhatIf for external commands" {
    $res = Invoke-AiExecutionGate -Command "git checkout main" -WhatIf -PassThru
    return ($res.Executed -eq $false -and $res.Status -eq "PreviewUnavailable")
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Results: $passed / $total passed ($failed failed)" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

if ($failed -gt 0) { exit 1 } else { exit 0 }
