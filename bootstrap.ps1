# bootstrap.ps1 - Universal One-Command Portable Bootstrapper for TerminalAI
# Run locally or execute via web one-liner:
#   irm https://raw.githubusercontent.com/TiredRebel/Windows-Terminal-AI-Plugin/main/bootstrap.ps1 | iex

[CmdletBinding()]
param(
    [ValidateSet("Auto", "Portable", "Install")]
    [string]$Mode = "Auto",

    [ValidateSet("en", "uk")]
    [string]$Language,

    [string]$Model = "qwen2.5-coder:7b",
    [switch]$SkipOllama,
    [switch]$NonInteractive,
    [switch]$AutoConfirm
)

$ErrorActionPreference = "Stop"

# 1. Language resolution
if (-not $Language) {
    if ($env:TERMINAL_AI_LANG -in @("uk", "ua")) {
        $Language = "uk"
    } else {
        $Language = "en"
    }
}
$isUk = ($Language -eq "uk")

# 2. Spinner helper
function Show-BootstrapSpinner {
    param(
        [string]$Message,
        [scriptblock]$Condition,
        [int]$TimeoutSec = 15,
        [bool]$IsUkrainian = $false
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $chars = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
    $i = 0
    $doneLabel = if ($IsUkrainian) { "готово!" } else { "ready!" }
    $timeoutLabel = if ($IsUkrainian) { "Час очікування вичерпано." } else { "Wait timeout elapsed." }
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if (& $Condition) {
            Write-Host "`r   ✔ $Message - $doneLabel ($([Math]::Round($sw.Elapsed.TotalSeconds, 1))s)          " -ForegroundColor Green
            return $true
        }
        $c = $chars[$i % $chars.Count]
        $i++
        $elapsed = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        Write-Host -NoNewline "`r   $c $Message (${elapsed}s / ${TimeoutSec}s)... "
        Start-Sleep -Milliseconds 250
    }
    Write-Host "`n   ⚠ $timeoutLabel" -ForegroundColor DarkYellow
    return $false
}

$hdrTitle = if ($isUk) { "   TerminalAI • Однокомандний Portable Bootstrapper   " } else { "   TerminalAI • One-Command Portable Bootstrapper   " }
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host $hdrTitle -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# 3. Check for PowerShell 7 upgrade if running in Windows PowerShell 5.1
$isPwsh = ($PSVersionTable.PSEdition -eq 'Core')
if (-not $isPwsh) {
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $candidatePwsh = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
    )
    $foundPwsh = if ($pwshCmd) { $pwshCmd.Source } else {
        $candidatePwsh | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if ($foundPwsh -and -not [Console]::IsInputRedirected -and -not $NonInteractive) {
        $msgRelaunchPrompt = if ($isUk) {
            "Знайдено PowerShell 7 ($foundPwsh). Бажаєте перезапустити в PS 7 для скомпільованого модуля .NET 10? [Y/n]"
        } else {
            "PowerShell 7 detected ($foundPwsh). Relaunch in PS 7 for compiled .NET 10 helper? [Y/n]"
        }
        $ans = Read-Host "   $msgRelaunchPrompt"
        if ($ans -match '^(y|yes|так|т|$)' -or [string]::IsNullOrWhiteSpace($ans)) {
            $scriptPath = $MyInvocation.MyCommand.Path
            if ($scriptPath -and (Test-Path $scriptPath)) {
                Start-Process -FilePath $foundPwsh -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"", "-Mode", $Mode, "-Language", $Language
                return
            }
        }
    }
}

# 4. Ollama detection and service check
if (-not $SkipOllama) {
    $stepOllama = if ($isUk) { "1. Перевірка локального рушія Ollama..." } else { "1. Checking local Ollama engine..." }
    Write-Host $stepOllama -ForegroundColor Yellow

    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    $ollamaExeCandidates = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "${env:ProgramFiles}\Ollama\ollama.exe"
    )
    if (-not $ollamaCmd) {
        foreach ($cand in $ollamaExeCandidates) {
            if (Test-Path $cand) {
                $env:Path = (Split-Path -Parent $cand) + ";" + $env:Path
                $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
                break
            }
        }
    }

    if (-not $ollamaCmd) {
        $msgNoOllama = if ($isUk) { "   ⚠ Ollama не знайдено на комп'ютері." } else { "   ⚠ Ollama is not installed on this system." }
        Write-Host $msgNoOllama -ForegroundColor DarkYellow

        $shouldInstall = $AutoConfirm
        if (-not $shouldInstall -and -not [Console]::IsInputRedirected -and -not $NonInteractive) {
            $promptInstall = if ($isUk) { "   Встановити Ollama автоматично зараз? [Y/n]" } else { "   Install Ollama automatically now? [Y/n]" }
            $ans = Read-Host $promptInstall
            $shouldInstall = ($ans -match '^(y|yes|так|т|$)' -or [string]::IsNullOrWhiteSpace($ans))
        }

        if ($shouldInstall) {
            $installedViaWinget = $false
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                try {
                    Write-Host "   • Installing Ollama via winget..." -ForegroundColor DarkGray
                    & winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements
                    if ($LASTEXITCODE -eq 0) { $installedViaWinget = $true }
                } catch { }
            }

            if (-not $installedViaWinget) {
                $installerUrl = "https://ollama.com/download/OllamaSetup.exe"
                $installerPath = Join-Path $env:TEMP "OllamaSetup.exe"
                Write-Host "   • Downloading installer from $installerUrl..." -ForegroundColor DarkGray
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
                Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait
            }

            # Refresh PATH
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
            foreach ($cand in $ollamaExeCandidates) {
                if (Test-Path $cand) {
                    $env:Path = (Split-Path -Parent $cand) + ";" + $env:Path
                    break
                }
            }
            $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
        }
    }

    # Verify service connectivity
    $isApiReady = $false
    $candidateUrls = @("http://127.0.0.1:11434", "http://localhost:11434")
    $activeUrl = $candidateUrls[0]
    $installedModels = @()

    foreach ($url in $candidateUrls) {
        try {
            $t = Invoke-RestMethod -Uri "$url/api/tags" -TimeoutSec 1 -ErrorAction Stop
            $installedModels = @($t.models.name)
            $isApiReady = $true
            $activeUrl = $url
            break
        } catch { }
    }

    if (-not $isApiReady -and $ollamaCmd) {
        Write-Host "   • Ollama service is inactive. Starting background daemon..." -ForegroundColor DarkYellow
        Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue
        $spinnerLabel = if ($isUk) { "Очікування запуску Ollama" } else { "Waiting for Ollama service to start" }
        $isApiReady = Show-BootstrapSpinner -Message $spinnerLabel -TimeoutSec 12 -IsUkrainian $isUk -Condition {
            foreach ($url in $candidateUrls) {
                try {
                    $res = Invoke-RestMethod -Uri "$url/api/tags" -TimeoutSec 1 -ErrorAction Stop
                    $script:installedModels = @($res.models.name)
                    $script:activeUrl = $url
                    return $true
                } catch { }
            }
            return $false
        }
    }

    if ($isApiReady) {
        Write-Host "   ✔ Ollama online at $activeUrl ($($installedModels.Count) models available)." -ForegroundColor Green
        
        # Check active model
        if ($installedModels -notcontains $Model) {
            $msgPull = if ($isUk) { "Рекомендовану модель '$Model' не знайдено. Завантажити зараз? [Y/n]" } else { "Recommended model '$Model' is not installed. Download now? [Y/n]" }
            $shouldPull = $AutoConfirm
            if (-not $shouldPull -and -not [Console]::IsInputRedirected -and -not $NonInteractive) {
                $ansPull = Read-Host "   $msgPull"
                $shouldPull = ($ansPull -match '^(y|yes|так|т|$)' -or [string]::IsNullOrWhiteSpace($ansPull))
            }
            if ($shouldPull -and $ollamaCmd) {
                Write-Host "   ▶ Pulling model '$Model' (this may take a couple of minutes)..." -ForegroundColor Cyan
                & ollama pull $Model
            }
        }
    } else {
        Write-Warning "Ollama service could not be contacted at http://127.0.0.1:11434. Start it with 'ollama serve'."
    }
}

# 5. Resolve Mode (Portable vs Install)
if ($Mode -eq "Auto") {
    if ($env:TERMINAL_AI_MODE -in @("Portable", "Install")) {
        $Mode = $env:TERMINAL_AI_MODE
    } elseif ([Console]::IsInputRedirected -or $NonInteractive) {
        $Mode = "Portable"
    } else {
        $promptMode = if ($isUk) {
            "Оберіть режим запуску:`n  [1] Portable  - Швидкий запуск у поточній сесії (нульовий слід, без зміни `$PROFILE)`n  [2] Install   - Повне встановлення з інтеграцією у Windows Terminal`nВаш вибір [1/2] (за замовчуванням 1):"
        } else {
            "Choose execution mode:`n  [1] Portable  - Run directly in current session (zero system footprint, leaves `$PROFILE untouched)`n  [2] Install   - Full installation with Windows Terminal integration`nYour choice [1/2] (default 1):"
        }
        Write-Host "`n$promptMode " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host
        if ($choice -match '^(2|install|i)$') {
            $Mode = "Install"
        } else {
            $Mode = "Portable"
        }
    }
}

# 6. Locate or stage TerminalAI runtime files
$localRoot = $PSScriptRoot
if (-not $localRoot) { $localRoot = Get-Location }
$hasLocalManifest = (Test-Path (Join-Path $localRoot "TerminalAI.psd1"))

$runtimeDir = $null
if ($hasLocalManifest) {
    $runtimeDir = (Resolve-Path $localRoot).Path
} else {
    # Web download mode: fetch release zip from GitHub
    $releaseUrl = "https://github.com/TiredRebel/Windows-Terminal-AI-Plugin/releases/download/v0.1.0-preview1/TerminalAI-v0.1.0-preview1-win-x64.zip"
    $targetTemp = Join-Path $env:TEMP "TerminalAI_Runtime_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $zipPath = Join-Path $env:TEMP "TerminalAI-v0.1.0-preview1-win-x64.zip"

    Write-Host "`n• Downloading TerminalAI release package..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $releaseUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $targetTemp -Force
        $runtimeDir = $targetTemp
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Could not download GitHub release package ($($_.Exception.Message)). Falling back to current directory."
        $runtimeDir = (Get-Location).Path
    }
}

# 7. Execute selected mode
if ($Mode -eq "Install") {
    $installerScript = Join-Path $runtimeDir "Install-TerminalAi.ps1"
    if (Test-Path $installerScript) {
        Write-Host "`n▶ Launching full TerminalAI installer..." -ForegroundColor Cyan
        & $installerScript -Language $Language
    } else {
        Write-Error "Installer script not found: $installerScript"
    }
} else {
    # Mode: Portable (Ephemeral, Zero-Footprint)
    Write-Host "`n▶ Initializing portable session (zero-footprint)..." -ForegroundColor Cyan
    $psd1 = Join-Path $runtimeDir "TerminalAI.psd1"
    if (-not (Test-Path $psd1)) {
        throw "Module manifest not found at: $psd1"
    }

    Import-Module $psd1 -Force -ErrorAction Stop

    # Set session language
    if ($Language) {
        Set-TerminalAiLanguage -Language $Language -ErrorAction SilentlyContinue
    }

    # Register inline hotkey (F2)
    if (Get-Command Register-TerminalAiKeyHandler -ErrorAction SilentlyContinue) {
        Register-TerminalAiKeyHandler
    }

    # Show stylish welcome banner
    if (Get-Command Show-TerminalAiWelcome -ErrorAction SilentlyContinue) {
        Show-TerminalAiWelcome
    }

    $msgActive = if ($isUk) {
        "✔ TerminalAI успішно активовано у поточній сесії (нульовий слід у системі).`n  Спробуйте: ai `"знайти великі файли`" або натисніть F2 у рядку введення!`n"
    } else {
        "✔ TerminalAI successfully loaded in current session (zero system footprint).`n  Try: ai `"find large files`" or press F2 inline!`n"
    }
    Write-Host $msgActive -ForegroundColor Green
}
