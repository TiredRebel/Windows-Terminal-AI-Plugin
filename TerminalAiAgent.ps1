# TerminalAiAgent.ps1 - Claude Code Agent Mode Integration for TerminalAI
# Encapsulates preflight discovery, workspace trust gating, environment isolation, and process orchestration.

function Find-ClaudeCodeExecutable {
    <#
    .SYNOPSIS
        Locates the Claude Code executable across custom config, PATH, and standard Windows install locations.
    #>
    [CmdletBinding()]
    param(
        [string]$CustomPath
    )

    # 1. Custom path from configuration or parameter
    if ($CustomPath) {
        if (Test-Path $CustomPath) {
            return (Resolve-Path $CustomPath).Path
        }
        return $null
    }

    # 2. Check PATH via Get-Command
    try {
        $cmd = Get-Command "claude" -ErrorAction SilentlyContinue
        if ($cmd) {
            $src = if ($cmd.Source) { $cmd.Source } else { $cmd.Path }
            if ($src -and (Test-Path $src)) {
                return (Resolve-Path $src).Path
            }
        }
    } catch { }

    # 3. Standard fallback locations on Windows
    $candidates = @(
        (Join-Path $HOME ".local\bin\claude.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\claude\claude.exe"),
        (Join-Path $env:APPDATA "npm\claude.cmd"),
        (Join-Path $env:ProgramFiles "Claude Code\claude.exe")
    )
    foreach ($cand in $candidates) {
        if ($cand -and (Test-Path $cand)) {
            return (Resolve-Path $cand).Path
        }
    }

    return $null
}

function Get-ClaudeCodeVersion {
    <#
    .SYNOPSIS
        Retrieves the version of Claude Code by executing 'claude --version'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClaudePath
    )

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ClaudePath
        $psi.Arguments = "--version"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $output = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit(3000) | Out-Null
        if ($output -match '(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        return $output.Trim()
    } catch {
        return "Unknown"
    }
}

function Test-AiAgentReadiness {
    <#
    .SYNOPSIS
        Inspects preflight readiness for Claude Code Agent Mode.
    .DESCRIPTION
        Probes Claude Code CLI installation, Ollama service reachability, model presence,
        and tool-calling capabilities.
    .PARAMETER Model
        Target model to inspect.
    .PARAMETER WorkingDir
        Target workspace directory.
    .PARAMETER ClaudePath
        Explicit path to Claude executable.
    .PARAMETER PassThru
        Returns a structured PSCustomObject with readiness details.
    .EXAMPLE
        Test-AiAgentReadiness
    .EXAMPLE
        Test-AiAgentReadiness -PassThru
    #>
    [CmdletBinding()]
    param(
        [string]$Model,
        [string]$WorkingDir,
        [string]$ClaudePath,
        [switch]$PassThru
    )

    $cfg = try { Get-TerminalAiConfig } catch { $null }
    $isUk = ($cfg -and $cfg.Language -in @("uk", "ua"))

    $ollamaUrl = if ($cfg -and $cfg.OllamaUrl) { $cfg.OllamaUrl } else { "http://localhost:11434" }
    $targetModel = if ($Model) {
        $Model
    } elseif ($cfg -and $cfg.AgentModel) {
        $cfg.AgentModel
    } elseif ($cfg -and $cfg.Model) {
        $cfg.Model
    } else {
        "qwen2.5-coder:7b"
    }

    $targetDir = if ($WorkingDir) {
        if (Test-Path $WorkingDir) { (Resolve-Path $WorkingDir).Path } else { $WorkingDir }
    } else {
        $PWD.Path
    }

    # 1. Inspect Claude executable
    $customExecutable = if ($ClaudePath) { $ClaudePath } elseif ($cfg) { $cfg.ClaudeExecutable } else { $null }
    $resolvedClaude = Find-ClaudeCodeExecutable -CustomPath $customExecutable
    $claudeReady = ($null -ne $resolvedClaude)
    $claudeVer = if ($claudeReady) { Get-ClaudeCodeVersion -ClaudePath $resolvedClaude } else { $null }

    # 2. Inspect Ollama service
    $ollamaReady = $false
    $installedModels = @()
    foreach ($cand in @($ollamaUrl, "http://127.0.0.1:11434", "http://localhost:11434")) {
        try {
            $tagsUri = "$($cand.TrimEnd('/'))/api/tags"
            $res = Invoke-RestMethod -Uri $tagsUri -TimeoutSec 2 -ErrorAction Stop
            $installedModels = @($res.models.name)
            $ollamaReady = $true
            $ollamaUrl = $cand
            break
        } catch { }
    }

    # 3. Inspect Model and tool capability
    $modelPresent = ($installedModels -contains $targetModel)
    $toolsSupported = $false
    if ($ollamaReady -and $modelPresent) {
        try {
            $showUri = "$($ollamaUrl.TrimEnd('/'))/api/show"
            $payload = @{ name = $targetModel } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $showRes = Invoke-RestMethod -Uri $showUri -Method Post -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 3 -ErrorAction Stop
            $tmpl = if ($showRes.template) { $showRes.template } else { "" }
            $caps = if ($showRes.capabilities) { "$($showRes.capabilities)" } else { "" }
            if ($caps -match 'tools' -or $tmpl -match 'tool_call|\.Tools|\[TOOLS\]|<tools>|\.tools') {
                $toolsSupported = $true
            } else {
                if ($targetModel -match 'coder|qwen|granite|hermes|command-r') {
                    $toolsSupported = $true
                }
            }
        } catch {
            if ($targetModel -match 'coder|qwen|granite|hermes|command-r') {
                $toolsSupported = $true
            }
        }
    }

    # 4. Workspace validation
    $dirValid = (Test-Path $targetDir -PathType Container)

    $overallReady = ($claudeReady -and $ollamaReady -and $modelPresent -and $dirValid)

    $statusObj = [PSCustomObject]@{
        Ready           = $overallReady
        ClaudeReady     = $claudeReady
        ClaudePath      = $resolvedClaude
        ClaudeVersion   = $claudeVer
        OllamaReady     = $ollamaReady
        OllamaUrl       = $ollamaUrl
        Model           = $targetModel
        ModelPresent    = $modelPresent
        ToolsSupported  = $toolsSupported
        WorkingDir      = $targetDir
        WorkingDirValid = $dirValid
    }

    if ($PassThru) {
        return $statusObj
    }

    # Display human-friendly status
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "         ✦ TERMINAL AI: AGENT MODE READINESS CHECK ✦           " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

    Write-Host "  1. Claude Code CLI:      " -NoNewline -ForegroundColor DarkGray
    if ($claudeReady) {
        Write-Host "✔ Found at $resolvedClaude (v$claudeVer)" -ForegroundColor Green
    } else {
        Write-Host "✖ Not found in PATH or standard directories" -ForegroundColor Red
        if ($isUk) {
            Write-Host "     Встановіть Claude Code: npm install -g @anthropic-ai/claude-code" -ForegroundColor DarkYellow
        } else {
            Write-Host "     Install Claude Code: npm install -g @anthropic-ai/claude-code" -ForegroundColor DarkYellow
        }
    }

    Write-Host "  2. Ollama Backend:       " -NoNewline -ForegroundColor DarkGray
    if ($ollamaReady) {
        Write-Host "✔ Responding at $ollamaUrl (Anthropic API /v1/messages)" -ForegroundColor Green
    } else {
        Write-Host "✖ Service unreachable at $ollamaUrl" -ForegroundColor Red
        if ($isUk) {
            Write-Host "     Запустіть службу Ollama: ollama serve" -ForegroundColor DarkYellow
        } else {
            Write-Host "     Start Ollama service: ollama serve" -ForegroundColor DarkYellow
        }
    }

    Write-Host "  3. Agent Model:          " -NoNewline -ForegroundColor DarkGray
    if ($modelPresent) {
        $toolTag = if ($toolsSupported) { "[tools supported]" } else { "[warning: tool calling unverified]" }
        $toolColor = if ($toolsSupported) { "Green" } else { "Yellow" }
        Write-Host "✔ '$targetModel' installed $toolTag" -ForegroundColor $toolColor
    } elseif ($ollamaReady) {
        Write-Host "✖ '$targetModel' not found in Ollama" -ForegroundColor Red
        if ($isUk) {
            Write-Host "     Завантажте модель: ollama pull $targetModel" -ForegroundColor DarkYellow
        } else {
            Write-Host "     Download model: ollama pull $targetModel" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "⚠ Cannot verify model (Ollama offline)" -ForegroundColor DarkYellow
    }

    Write-Host "  4. Target Workspace:     " -NoNewline -ForegroundColor DarkGray
    if ($dirValid) {
        Write-Host "✔ $targetDir" -ForegroundColor Green
    } else {
        Write-Host "✖ Invalid directory: $targetDir" -ForegroundColor Red
    }

    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    if ($overallReady) {
        if ($isUk) {
            Write-Host "  ✦ Усе готово для автономного запуску 'ai-agent'! ✦" -ForegroundColor Green
        } else {
            Write-Host "  ✦ All agent prerequisites are met. Ready for 'ai-agent'! ✦" -ForegroundColor Green
        }
    } else {
        if ($isUk) {
            Write-Host "  ⚠ Одне або декілька налаштувань потребують уваги. Дивіться вище." -ForegroundColor Yellow
        } else {
            Write-Host "  ⚠ One or more prerequisites are missing. See instructions above." -ForegroundColor Yellow
        }
    }
    Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

    return $statusObj
}

function Invoke-AiAgent {
    <#
    .SYNOPSIS
        Launches Claude Code in optional Agent Mode, backed by local Ollama.
    .DESCRIPTION
        Executes Claude Code as an isolated child process connected to Ollama's
        Anthropic-compatible Messages API. Keeps configuration in ~/.terminal-ai/claude
        and isolates ambient cloud credentials.
    .PARAMETER Prompt
        Optional task prompt or instructions to pass to Claude Code.
    .PARAMETER Model
        Model to use. Defaults to AgentModel in configuration (or 'qwen2.5-coder:7b').
    .PARAMETER WorkingDir
        Target directory for the agent. Defaults to current directory ($PWD).
    .PARAMETER Resume
        Resumes previous conversation session in the directory (--resume).
    .PARAMETER Print
        Runs in non-interactive print mode (-p).
    .PARAMETER ConfirmTrust
        Confirms workspace trust and skips the interactive confirmation prompt.
    .PARAMETER Force
        Alias for ConfirmTrust.
    .PARAMETER CheckOnly
        Performs preflight checks and outputs readiness status without launching Claude.
    .EXAMPLE
        ai-agent "inspect git status and explain unstaged changes"
    .EXAMPLE
        ai-agent -Resume
    .EXAMPLE
        ai-agent -CheckOnly
    #>
    [CmdletBinding()]
    [Alias("ai-agent")]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Prompt,

        [string]$Model,
        [string]$WorkingDir,
        [switch]$Resume,
        [switch]$Print,
        [Alias("Force", "y", "Yes")]
        [switch]$ConfirmTrust,
        [switch]$CheckOnly
    )

    $cfg = try { Get-TerminalAiConfig } catch { $null }
    $isUk = ($cfg -and $cfg.Language -in @("uk", "ua"))

    $targetModel = if ($Model) {
        $Model
    } elseif ($cfg -and $cfg.AgentModel) {
        $cfg.AgentModel
    } elseif ($cfg -and $cfg.Model) {
        $cfg.Model
    } else {
        "qwen2.5-coder:7b"
    }

    $targetDir = if ($WorkingDir) {
        if (Test-Path $WorkingDir) { (Resolve-Path $WorkingDir).Path } else { $WorkingDir }
    } else {
        $PWD.Path
    }

    # 1. Preflight readiness inspection
    $readiness = Test-AiAgentReadiness -Model $targetModel -WorkingDir $targetDir -PassThru

    if ($CheckOnly) {
        Test-AiAgentReadiness -Model $targetModel -WorkingDir $targetDir | Out-Null
        return $readiness
    }

    if (-not $readiness.Ready) {
        Test-AiAgentReadiness -Model $targetModel -WorkingDir $targetDir | Out-Null
        $failMsg = if ($isUk) {
            "Неможливо запустити Claude Code агента: не виконано передумови вище."
        } else {
            "Cannot launch Claude Code agent: prerequisites above were not met."
        }
        Write-Error "[TerminalAI] $failMsg"
        return 1
    }

    # 2. Workspace Trust & Permission Confirmation
    if (-not $ConfirmTrust) {
        $isInteractive = $true
        try {
            if ([Console]::IsInputRedirected) { $isInteractive = $false }
        } catch { }

        if ($isInteractive) {
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "        ✦ TERMINAL AI: CLAUDE CODE AGENT MODE LAUNCH ✦         " -ForegroundColor Cyan
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  Workspace:    " -NoNewline -ForegroundColor DarkGray
            Write-Host "$targetDir" -ForegroundColor Yellow
            Write-Host "  Backend:      " -NoNewline -ForegroundColor DarkGray
            Write-Host "Ollama ($($readiness.OllamaUrl))" -ForegroundColor Green
            Write-Host "  Agent Model:  " -NoNewline -ForegroundColor DarkGray
            Write-Host "$targetModel" -ForegroundColor Green
            Write-Host "  Permissions:  " -NoNewline -ForegroundColor DarkGray
            Write-Host "Standard (Native interactive tool approval active)" -ForegroundColor Green
            Write-Host "  Privacy:      " -NoNewline -ForegroundColor DarkGray
            Write-Host "Local-only (Telemetry & external traffic disabled)" -ForegroundColor Green
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

            $promptMsg = if ($isUk) {
                "Launch Claude Code agent in this folder? [Y/n]: "
            } else {
                "Launch Claude Code agent in this folder? [Y/n]: "
            }
            Write-Host $promptMsg -NoNewline -ForegroundColor Cyan
            $ans = [Console]::ReadLine()
            if ($ans -and $ans.Trim() -match '^[nN]') {
                $cancelMsg = if ($isUk) {
                    "Запуск агента скасовано користувачем."
                } else {
                    "Agent launch cancelled by user."
                }
                Write-Host "ℹ [TerminalAI] $cancelMsg" -ForegroundColor Yellow
                return 0
            }
        }
    }

    # 3. Environment & Directory Setup
    $agentConfigDir = if ($cfg -and $cfg.AgentDataDirectory) {
        $cfg.AgentDataDirectory
    } else {
        Join-Path $HOME ".terminal-ai\claude"
    }
    if (-not (Test-Path $agentConfigDir)) {
        New-Item -ItemType Directory -Path $agentConfigDir -Force | Out-Null
    }

    # 4. Construct Argument List
    $argList = [System.Collections.Generic.List[string]]::new()
    $argList.Add("--model")
    $argList.Add($targetModel)

    if ($Resume) {
        $argList.Add("--resume")
    }

    if ($Print) {
        $argList.Add("-p")
    }

    if ($Prompt -and $Prompt.Count -gt 0) {
        $fullPrompt = ($Prompt -join " ").Trim()
        if (-not [string]::IsNullOrWhiteSpace($fullPrompt)) {
            $argList.Add($fullPrompt)
        }
    }

    # Format arguments for Windows process
    $escapedArgs = @()
    foreach ($a in $argList) {
        if ($a -match '[\s"]') {
            $escapedArgs += "`"$($a.Replace('"', '\"'))`""
        } else {
            $escapedArgs += $a
        }
    }
    $argString = ($escapedArgs -join " ")

    # 5. ProcessStartInfo with Direct Console Inheritance & Isolated Env
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $readiness.ClaudePath
    $psi.Arguments = $argString
    $psi.WorkingDirectory = $targetDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false

    # Set process-scoped local endpoint variables
    $psi.EnvironmentVariables["ANTHROPIC_BASE_URL"] = $readiness.OllamaUrl.TrimEnd('/')
    $psi.EnvironmentVariables["ANTHROPIC_AUTH_TOKEN"] = "ollama"
    $psi.EnvironmentVariables["ANTHROPIC_API_KEY"] = "ollama"
    $psi.EnvironmentVariables["CLAUDE_CONFIG_DIR"] = $agentConfigDir
    $psi.EnvironmentVariables["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"

    # Ambient key neutralization
    foreach ($k in @("OPENAI_API_KEY", "GEMINI_API_KEY", "DEEPSEEK_API_KEY")) {
        if ($psi.EnvironmentVariables.ContainsKey($k)) {
            $psi.EnvironmentVariables.Remove($k)
        }
    }

    Write-Host "⚡ [TerminalAI] Starting Claude Code agent (Model: $targetModel)..." -ForegroundColor Cyan

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
        if ($exitCode -ne 0) {
            Write-Host "`nℹ [TerminalAI] Claude Code exited with code $exitCode" -ForegroundColor DarkYellow
        }
        return $exitCode
    }
    catch {
        Write-Error "[TerminalAI] Failed to start Claude Code agent: $($_.Exception.Message)"
        return 1
    }
}
