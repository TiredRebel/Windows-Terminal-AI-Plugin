# Install-Ollama.ps1 - Detects or installs Ollama, analyzes local hardware, and
# pulls a recommended model. Optional product: the Core module still works
# against any Ollama-compatible endpoint you configure by hand with
# Set-TerminalAiConfig -OllamaUrl, so this script is only needed when you want
# the installer to set Ollama up for you on this machine.
#
# Can be run standalone:
#   pwsh -ExecutionPolicy Bypass -File .\installers\Install-Ollama.ps1
# or invoked from the orchestrator, ..\Install-TerminalAi.ps1.

[CmdletBinding()]
param(
    [ValidateSet("en", "uk")]
    [string]$Language = "en",

    [string]$PreferredModel,
    [switch]$AutoConfirm
)

$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey('Language') -and $env:TERMINAL_AI_LANG -in @("uk", "ua")) {
    $Language = "uk"
}
$isUk = ($Language -eq "uk")

. (Join-Path $PSScriptRoot "InstallerCommon.ps1")

$step1 = "▶ Checking Ollama in system..."
Write-Host $step1 -ForegroundColor Yellow
$ollamaCmd = Get-Command ollama -ErrorAction Ignore
$ollamaExeCandidates = @(
    "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
    "${env:ProgramFiles}\Ollama\ollama.exe"
)

if (-not $ollamaCmd) {
    foreach ($candidate in $ollamaExeCandidates) {
        if (Test-Path $candidate) {
            $ollamaDir = Split-Path -Parent $candidate
            $env:Path = "$ollamaDir;" + $env:Path
            $ollamaCmd = Get-Command ollama -ErrorAction Ignore
            break
        }
    }
}

if (-not $ollamaCmd) {
    $msgNoOllama = "   ⚠ Ollama was not found on your system."
    Write-Host $msgNoOllama -ForegroundColor DarkYellow
    $shouldInstall = $false
    if ($AutoConfirm) {
        $shouldInstall = $true
    } elseif (-not [Console]::IsInputRedirected) {
        $promptInstall = "   Do you want to install Ollama automatically now? [Y/n]"
        $ans = Read-Host $promptInstall
        $shouldInstall = ($ans -match '^(y|yes|$)' -or [string]::IsNullOrWhiteSpace($ans))
    }

    if ($shouldInstall) {
        $msgStartInstall = "   ▶ Starting Ollama installation..."
        Write-Host $msgStartInstall -ForegroundColor Cyan
        $installedViaWinget = $false
        if (Get-Command winget -ErrorAction Ignore) {
            $msgWinget = "   • Installing via winget..."
            Write-Host $msgWinget -ForegroundColor DarkGray
            try {
                & winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -eq 0) { $installedViaWinget = $true }
            } catch { }
        }

        if (-not $installedViaWinget) {
            $installerUrl = "https://ollama.com/download/OllamaSetup.exe"
            $installerPath = Join-Path $env:TEMP "OllamaSetup.exe"
            $msgDownload = "   • Downloading installer from $installerUrl..."
            Write-Host $msgDownload -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
            $msgSilent = "   • Launching silent Ollama installation..."
            Write-Host $msgSilent -ForegroundColor DarkGray
            Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait
        }

        # Refresh PATH
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        foreach ($candidate in $ollamaExeCandidates) {
            if (Test-Path $candidate) {
                $env:Path = (Split-Path -Parent $candidate) + ";" + $env:Path
                break
            }
        }
        $ollamaCmd = Get-Command ollama -ErrorAction Ignore
        if ($ollamaCmd) {
            $msgInstalled = "   ✔ Ollama installed successfully!"
            Write-Host $msgInstalled -ForegroundColor Green
        } else {
            $msgNotPath = "   ⚠ Installation finished, but ollama.exe was not found in PATH."
            Write-Host $msgNotPath -ForegroundColor DarkYellow
        }
    } else {
        $msgSkipped = "   ⚠ Ollama installation skipped by user."
        Write-Host $msgSkipped -ForegroundColor DarkGray
    }
} else {
    $msgFound = "   ✔ Ollama found: $($ollamaCmd.Source)"
    Write-Host $msgFound -ForegroundColor Green
}

$ollamaUrl = "http://localhost:11434"
$installedModels = @()

# API readiness check
$isApiReady = $false
foreach ($candUrl in @("http://127.0.0.1:11434", "http://localhost:11434")) {
    try {
        $tags = Invoke-RestMethod -Uri "$candUrl/api/tags" -TimeoutSec 1 -ErrorAction Stop
        $installedModels = @($tags.models.name)
        $isApiReady = $true
        $ollamaUrl = $candUrl
        break
    } catch { }
}

if (-not $isApiReady -and (Get-Command ollama -ErrorAction Ignore)) {
    $msgServeStart = "   • Ollama service is inactive. Starting background process..."
    Write-Host $msgServeStart -ForegroundColor DarkYellow
    Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue

    $spinnerMsg = "Waiting for local Ollama service to start"
    $isApiReady = Show-SpinnerWait -Message $spinnerMsg -TimeoutSec 10 -IsUkrainian $isUk -Condition {
        foreach ($candUrl in @("http://127.0.0.1:11434", "http://localhost:11434")) {
            try {
                $t = Invoke-RestMethod -Uri "$candUrl/api/tags" -TimeoutSec 1 -ErrorAction Stop
                $script:installedModels = @($t.models.name)
                $script:ollamaUrl = $candUrl
                return $true
            } catch { }
        }
        return $false
    }
    if ($script:installedModels) { $installedModels = $script:installedModels }
}

if ($isApiReady) {
    $msgActive = "   ✔ Ollama service is active! Installed models: $($installedModels.Count)"
    Write-Host $msgActive -ForegroundColor Green
} else {
    $msgNotResp = "   ⚠ Ollama is not responding at $ollamaUrl. Make sure it is running ('ollama serve')."
    Write-Host $msgNotResp -ForegroundColor DarkYellow
}

# Hardware analysis & model recommendation
$step2 = "`n▶ Analyzing system hardware configuration..."
Write-Host $step2 -ForegroundColor Yellow
$ramGb = 16
$gpuName = "Not detected"
try {
    $ramGb = [Math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB), 1)
    $gpuList = @(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name | Where-Object { $_ -notmatch 'Virtual|Remote|Basic' })
    if ($gpuList.Count -gt 0) { $gpuName = $gpuList[0] }
} catch { }

$lblRam = "   • Physical RAM:"
$lblGpu = "   • Graphics Adapter (GPU): "
Write-Host "$lblRam $ramGb GB" -ForegroundColor White
Write-Host "$lblGpu $gpuName" -ForegroundColor White

$recommendedModel = if ($ramGb -ge 16 -or $gpuName -match 'RTX|Radeon RX') {
    "qwen2.5-coder:7b"
} elseif ($ramGb -ge 12) {
    "qwen2.5-coder:3b"
} else {
    "qwen2.5-coder:1.5b"
}

$lblRec = "   💡 Recommended model for your configuration: "
Write-Host $lblRec -NoNewline -ForegroundColor Cyan
Write-Host "$recommendedModel" -ForegroundColor Green

$selectedModel = $recommendedModel
if ($PreferredModel) {
    $selectedModel = $PreferredModel
} elseif ($installedModels.Count -gt 0) {
    $candidates = @("qwen2.5-coder:7b", "qwen2.5-coder:3b", "qwen2.5-coder:1.5b", "qwen3.5-coder:9b", "granite4.2:8b", "qwen3.5:9b")
    foreach ($cand in $candidates) {
        if ($installedModels -contains $cand) {
            $selectedModel = $cand
            break
        }
    }
}

# Pull model if missing
if ($installedModels -notcontains $selectedModel -and (Get-Command ollama -ErrorAction Ignore)) {
    $msgMissing = "`n   ⚠ Model '$selectedModel' is not yet downloaded in Ollama."
    Write-Host $msgMissing -ForegroundColor DarkYellow
    $shouldPull = $false
    if ($AutoConfirm) {
        $shouldPull = $true
    } elseif (-not [Console]::IsInputRedirected) {
        $promptPull = "   Download '$selectedModel' now via 'ollama pull'? [Y/n] (or enter custom model name)"
        $pullChoice = Read-Host $promptPull
        if ($pullChoice -match '^(y|yes|$)' -or [string]::IsNullOrWhiteSpace($pullChoice)) {
            $shouldPull = $true
        } elseif ($pullChoice -notmatch '^(n|no)$') {
            $selectedModel = $pullChoice.Trim()
            $shouldPull = $true
        }
    }

    if ($shouldPull) {
        $msgPulling = "   ▶ Downloading model '$selectedModel' (with native Ollama progress)..."
        Write-Host $msgPulling -ForegroundColor Cyan
        & ollama pull $selectedModel
        if ($LASTEXITCODE -eq 0) {
            $msgPulled = "   ✔ Model '$selectedModel' downloaded successfully!"
            Write-Host $msgPulled -ForegroundColor Green
        }
    }
}

$lblSelected = "   Selected active model:"
Write-Host "$lblSelected $selectedModel" -ForegroundColor Cyan

# Persist the resolved model / endpoint, if the Core product's config script is
# available next to this repo (it may not have run yet, and that's fine: the
# defaults in TerminalAiConfig.ps1 already match what this script would set).
$projectDir = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Get-Location }
$configScript = Join-Path $projectDir "TerminalAiConfig.ps1"
if (Test-Path $configScript) {
    . $configScript
    Set-TerminalAiConfig -Model $selectedModel -OllamaUrl $ollamaUrl | Out-Null
}
