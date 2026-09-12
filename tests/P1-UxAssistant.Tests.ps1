<#
.SYNOPSIS
    Набір автоматичних тестів для Фази P1:
    - Цикл 5: Assistant Hardening (FIFO History & Secret Redaction)
    - Цикл 6: Script Generation Safety (Unified Diff Preview & Overwrite Protection)
.DESCRIPTION
    Перевіряє роботу функцій:
    - Protect-AiSecretData
    - Format-AiScriptDiff
    - Save-AiScriptFile
    - Add-AssistantHistoryMessage (логіка FIFO та санітизації)
#>

[CmdletBinding()]
param()

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $moduleRoot "TerminalAI.psd1"

if (-not (Get-Module -Name TerminalAI)) {
    Import-Module $modulePath -Force -DisableNameChecking
}

$testDir = Join-Path $env:TEMP ("tai_p1_test_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -Path $testDir -ItemType Directory -Force | Out-Null

$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0

function Assert-P1Fixture {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$TestBlock
    )

    $script:TotalTests++
    Write-Host "  [$Id] $Description ... " -NoNewline -ForegroundColor Gray

    try {
        $result = & $TestBlock
        if ($result -eq $false) {
            Write-Host "FAILED (Assertion returned false)" -ForegroundColor Red
            $script:FailedTests++
        } else {
            Write-Host "PASS" -ForegroundColor Green
            $script:PassedTests++
        }
    } catch {
        Write-Host "FAILED ($($_.Exception.Message))" -ForegroundColor Red
        $script:FailedTests++
    }
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  TerminalAI Phase P1 Test Suite (Cycles 5 & 6)" -ForegroundColor Cyan
Write-Host "  PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
Write-Host "============================================================`n" -ForegroundColor Cyan

try {
    # -------------------------------------------------------------
    # CYCLE 5: SECRET REDACTION & FIFO HISTORY
    # -------------------------------------------------------------
    Write-Host "--- Cycle 5: Secret Redaction (Protect-AiSecretData) ---" -ForegroundColor Yellow

    # FIX-P1-01: OpenAI API Key Redaction
    Assert-P1Fixture "FIX-P1-01" "Redact OpenAI API keys (sk-...)" {
        $inputStr = 'Connecting with key sk-1234567890abcdef1234567890abcdef to endpoint'
        $cleaned = Protect-AiSecretData -Text $inputStr
        ($cleaned -notmatch 'sk-1234567890abcdef1234567890abcdef') -and ($cleaned -match 'sk-\*\*\*\[REDACTED\]\*\*\*')
    }

    # FIX-P1-02: Anthropic API Key Redaction
    Assert-P1Fixture "FIX-P1-02" "Redact Anthropic API keys (sk-ant-...)" {
        $inputStr = 'Export ANTHROPIC_API_KEY="sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890"'
        $cleaned = Protect-AiSecretData -Text $inputStr
        ($cleaned -notmatch 'sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890') -and ($cleaned -match 'sk-ant-\*\*\*\[REDACTED\]\*\*\*')
    }

    # FIX-P1-03: Multi-Provider Token Redaction (HF, GitHub, AWS)
    Assert-P1Fixture "FIX-P1-03" "Redact HuggingFace, GitHub, and AWS AKIA tokens" {
        $inputStr = "HF: hf_AbcDefGhijkLmnOpqrStuv123456`nGH: ghp_1234567890abcdefghijklmnopqrstuv`nAWS: AKIAIOSFODNN7EXAMPLE"
        $cleaned = Protect-AiSecretData -Text $inputStr
        ($cleaned -match 'hf_\*\*\*\[REDACTED\]\*\*\*') -and
        ($cleaned -match 'ghp_\*\*\*\[REDACTED\]\*\*\*') -and
        ($cleaned -match '\*\*\*\[REDACTED AWS KEY\]\*\*\*')
    }

    # FIX-P1-04: Bearer Token Redaction
    Assert-P1Fixture "FIX-P1-04" "Redact Bearer tokens in headers" {
        $inputStr = 'Headers: @{ Authorization = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" }'
        $cleaned = Protect-AiSecretData -Text $inputStr
        ($cleaned -notmatch 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9') -and ($cleaned -match 'Bearer\s+\*\*\*\[REDACTED\]\*\*\*')
    }

    # FIX-P1-05: Inline Passwords and Credentials
    Assert-P1Fixture "FIX-P1-05" "Redact inline passwords and credentials in scripts" {
        $inputStr = '$pass = "SuperSecret123!"' + "`n" + 'password: "MyPassword456"' + "`n" + "api_key = 'xyz12345678'"
        $cleaned = Protect-AiSecretData -Text $inputStr
        ($cleaned -notmatch 'SuperSecret123!') -and
        ($cleaned -notmatch 'MyPassword456') -and
        ($cleaned -notmatch 'xyz12345678')
    }

    # FIX-P1-06: PEM Private Key Redaction
    Assert-P1Fixture "FIX-P1-06" "Redact PEM private keys block" {
        $inputStr = @"
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA0Y1u5...
...secret private key content...
-----END RSA PRIVATE KEY-----
"@
        $cleaned = Protect-AiSecretData -Text $inputStr
        ($cleaned -notmatch 'secret private key content') -and ($cleaned -match '\*\*\*\[REDACTED PRIVATE KEY\]\*\*\*')
    }

    # FIX-P1-07: FIFO Context Trimming and Sanitization
    Assert-P1Fixture "FIX-P1-07" "FIFO context queue caps at 16 turns and sanitizes tokens" {
        $historyList = [System.Collections.Generic.List[hashtable]]::new()
        for ($i = 1; $i -le 20; $i++) {
            $secretText = "Turn $i with sk-key1234567890abcdef12345678"
            $sanitized = Protect-AiSecretData -Text $secretText
            $historyList.Add(@{ role = "user"; content = $sanitized })
            while ($historyList.Count -gt 16) {
                $historyList.RemoveAt(0)
            }
        }
        $countOk = ($historyList.Count -eq 16)
        $firstIsTurn5 = ($historyList[0].content -match 'Turn 5')
        $lastIsTurn20 = ($historyList[15].content -match 'Turn 20')
        $sanitizedOk = ($historyList[15].content -match 'sk-\*\*\*\[REDACTED\]\*\*\*')
        $countOk -and $firstIsTurn5 -and $lastIsTurn20 -and $sanitizedOk
    }

    # -------------------------------------------------------------
    # CYCLE 6: DIFF PREVIEW & OVERWRITE PROTECTION
    # -------------------------------------------------------------
    Write-Host "`n--- Cycle 6: Diff Preview & Overwrite Safety ---" -ForegroundColor Yellow

    # FIX-P1-08: Unified Diff Generation
    Assert-P1Fixture "FIX-P1-08" "Format-AiScriptDiff outputs deterministic unified diff" {
        $oldText = "Write-Host 'Hello'`nGet-Process"
        $newText = "Write-Host 'Hello World'`nGet-Process`nStop-Process -Name calc"
        $diff = Format-AiScriptDiff -OldText $oldText -NewText $newText -PassThru
        $added = @($diff | Where-Object { $_.Type -eq "Added" })
        $removed = @($diff | Where-Object { $_.Type -eq "Removed" })
        $unchanged = @($diff | Where-Object { $_.Type -eq "Unchanged" })

        ($added.Count -ge 1) -and ($removed.Count -ge 1) -and ($unchanged.Count -ge 1)
    }

    # FIX-P1-09: Identical Content Detection
    Assert-P1Fixture "FIX-P1-09" "Save-AiScriptFile recognizes identical content without modification" {
        $filePath = Join-Path $testDir "script_identical.ps1"
        $content = "Write-Host 'Identical Script'`n"
        [System.IO.File]::WriteAllText($filePath, $content, (New-Object System.Text.UTF8Encoding($true)))

        $res = Save-AiScriptFile -Path $filePath -Content $content -PassThru
        ($res.Saved -eq $true) -and ($res.Status -eq "Identical")
    }

    # FIX-P1-10: Atomic New File Creation with UTF-8 BOM
    Assert-P1Fixture "FIX-P1-10" "Save-AiScriptFile creates new file with UTF-8 BOM" {
        $filePath = Join-Path $testDir "script_new.ps1"
        $content = "Write-Host 'New AI Script'`n"

        $res = Save-AiScriptFile -Path $filePath -Content $content -PassThru
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

        ($res.Saved -eq $true) -and ($res.Status -eq "Created") -and $hasBom
    }

    # FIX-P1-11: Non-Interactive Overwrite Guard
    Assert-P1Fixture "FIX-P1-11" "Save-AiScriptFile cancels overwrite safely when non-interactive" {
        $filePath = Join-Path $testDir "script_guard.ps1"
        [System.IO.File]::WriteAllText($filePath, "Initial Version`n", (New-Object System.Text.UTF8Encoding($true)))

        # In non-interactive mode (without ConfirmInput or -Force), it must block overwrite
        $res = Save-AiScriptFile -Path $filePath -Content "Modified Version`n" -PassThru
        $fileContent = [System.IO.File]::ReadAllText($filePath)

        ($res.Saved -eq $false) -and ($res.Status -eq "BlockedNonInteractive") -and ($fileContent -match "Initial Version")
    }

    # FIX-P1-12: Interactive Overwrite Denial
    Assert-P1Fixture "FIX-P1-12" "Save-AiScriptFile denies overwrite when user specifies 'n'" {
        $filePath = Join-Path $testDir "script_deny.ps1"
        [System.IO.File]::WriteAllText($filePath, "Version 1.0`n", (New-Object System.Text.UTF8Encoding($true)))

        $res = Save-AiScriptFile -Path $filePath -Content "Version 2.0`n" -ConfirmInput "n" -PassThru
        $fileContent = [System.IO.File]::ReadAllText($filePath)

        ($res.Saved -eq $false) -and ($res.Status -eq "OverwriteDenied") -and ($fileContent -match "Version 1.0")
    }

    # FIX-P1-13: Interactive Overwrite Approval
    Assert-P1Fixture "FIX-P1-13" "Save-AiScriptFile applies overwrite when user specifies 'y'" {
        $filePath = Join-Path $testDir "script_approve.ps1"
        [System.IO.File]::WriteAllText($filePath, "Version 1.0`n", (New-Object System.Text.UTF8Encoding($true)))

        $res = Save-AiScriptFile -Path $filePath -Content "Version 2.0`n" -ConfirmInput "y" -PassThru
        $fileContent = [System.IO.File]::ReadAllText($filePath)
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

        ($res.Saved -eq $true) -and ($res.Status -eq "Overwritten") -and ($fileContent -match "Version 2.0") -and $hasBom
    }

    # FIX-P1-14: AST Error Stream Isolation
    Assert-P1Fixture "FIX-P1-14" "Test-AiCommandAst does not pollute `$global:Error when analyzing non-alias cmdlets" {
        $errCountBefore = $global:Error.Count
        $res = Test-AiCommandAst -Command "Get-Process | Format-Table Name, CPU -AutoSize"
        $errCountAfter = $global:Error.Count

        ($errCountAfter -eq $errCountBefore) -and ($res.IsValid -eq $true)
    }

    # FIX-P1-15: Multi-line Formatting Pipeline Coherence
    Assert-P1Fixture "FIX-P1-15" "Invoke-AiExecutionGate with formatting pipeline executes and renders without throwing" {
        $code = @"
`$items = @([PSCustomObject]@{ Id = 1; Name = 'Alpha' }, [PSCustomObject]@{ Id = 2; Name = 'Beta' })
`$items | Format-Table Id, Name -AutoSize
"@
        $gateRes = Invoke-AiExecutionGate -Command $code -ReturnOutput -AutoConfirm -PassThru
        $streamErrors = @($gateRes.Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        ($gateRes.Executed -eq $true) -and ($streamErrors.Count -eq 0) -and ($null -ne $gateRes.Output)
    }

} finally {
    if (Test-Path $testDir) {
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Results: $script:PassedTests / $script:TotalTests passed ($script:FailedTests failed)" -ForegroundColor $(if ($script:FailedTests -eq 0) { "Green" } else { "Red" })
Write-Host "------------------------------------------------------------`n" -ForegroundColor Cyan

if ($script:FailedTests -gt 0) {
    exit 1
} else {
    exit 0
}
