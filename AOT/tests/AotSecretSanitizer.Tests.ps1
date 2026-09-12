# AOT Secret Sanitizer & Safe Clipboard Test Suite
# Tests for TerminalAI.Aot.AotSecretSanitizer and TerminalAI.Aot.AotClipboard

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

function Assert-SanitizerTest([string]$name, [scriptblock]$test) {
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

Write-Host "`n=== AOT Secret Sanitizer & Clipboard Verification ===" -ForegroundColor Cyan

# 1. OpenAI Key Masking
Assert-SanitizerTest "Masks OpenAI / AI api keys" {
    $raw = 'Invoke-RestMethod -Headers @{ Authorization = "Bearer sk-proj-1234567890abcdef1234567890" }'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch '1234567890abcdef1234567890') -and ($san -match 'sk-\*\*\*\[REDACTED\]')
}

# 2. GitHub PAT Masking
Assert-SanitizerTest "Masks classic GitHub tokens (ghp_...)" {
    $raw = 'git clone https://ghp_abcdef1234567890abcdef1234567890@github.com/org/repo.git'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch 'abcdef1234567890abcdef1234567890') -and ($san -match 'ghp_\*\*\*\[REDACTED\]')
}

# 3. GitHub Fine-Grained Token Masking
Assert-SanitizerTest "Masks GitHub fine-grained PAT (github_pat_...)" {
    $raw = 'export GH_TOKEN=github_pat_11ABCDEF1234567890_9876543210fedcba'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch '11ABCDEF1234567890_9876543210fedcba') -and ($san -match 'github_pat_\*\*\*\[REDACTED\]')
}

# 4. AWS Access Key Masking
Assert-SanitizerTest "Masks AWS Access Key ID" {
    $raw = 'aws configure set aws_access_key_id AKIAIOSFODNN7EXAMPLE'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch 'OSFODNN7EXAMPLE') -and ($san -match 'AKIA\*\*\*\[REDACTED\]')
}

# 5. Slack Token Masking
Assert-SanitizerTest "Masks Slack API token" {
    $raw = 'curl -H "token: xoxb-123456789012-1234567890123-456789abcdef"'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch '456789abcdef') -and ($san -match 'xoxb-\*\*\*\[REDACTED\]')
}

# 6. PEM Private Key Masking
Assert-SanitizerTest "Masks PEM private key blocks" {
    $raw = @"
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA0Y1+abcdefghijklmnopqrstuvwxyz0123456789==
-----END RSA PRIVATE KEY-----
"@
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch 'MIIEowIBAAKCAQEA0Y1') -and ($san -match '\[REDACTED PRIVATE KEY\]')
}

# 7. Cmdlet Parameter Secret Masking
Assert-SanitizerTest "Masks sensitive cmdlet parameter values (-Password, -Token, -Secret)" {
    $raw = 'Connect-Service -Password "SuperSecretP@ssw0rd!" -Token "myToken12345"'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch 'SuperSecretP@ssw0rd!') -and ($san -notmatch 'myToken12345') -and ($san -match '\[REDACTED\]')
}

# 8. Key-Value Assignment Masking
Assert-SanitizerTest "Masks key-value secret assignments" {
    $raw = '$apiKey = "live_secret_key_999999"'
    $san = [TerminalAI.Aot.AotSecretSanitizer]::Sanitize($raw)
    ($san -notmatch 'live_secret_key_999999') -and ($san -match '\[REDACTED\]')
}

# 9. ContainsSecret Detection
Assert-SanitizerTest "Detects presence of secrets accurately" {
    $hasSec1 = [TerminalAI.Aot.AotSecretSanitizer]::ContainsSecret('git status')
    $hasSec2 = [TerminalAI.Aot.AotSecretSanitizer]::ContainsSecret('export KEY=sk-proj-1234567890abcdef1234567890')
    (-not $hasSec1) -and $hasSec2
}

# 10. Safe Clipboard Assignment
Assert-SanitizerTest "Sets clipboard content safely without script execution" {
    $testStr = "AOT_CLIPBOARD_TEST_" + [Guid]::NewGuid().ToString()
    $res = [TerminalAI.Aot.AotClipboard]::SetText($testStr, $ExecutionContext.SessionState)
    $res -eq $true
}

Write-Host "`nResults: $passed / $total passed ($failed failed)" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) {
    exit 1
}
exit 0
