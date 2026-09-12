# Install-TerminalAi.ps1 - Installer for TerminalAI extension (Windows Terminal & Ollama)
# Multi-user installer supporting -Scope CurrentUser (default) and -Scope AllUsers
# English is primary default language; Ukrainian on demand via -Language uk

[CmdletBinding()]
param(
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",

    [ValidateSet("en", "uk")]
    [string]$Language = "en",

    [switch]$SkipTerminalConfig,
    [switch]$SkipOllamaCheck,
    [string]$PreferredModel,
    [switch]$AutoConfirm,
    [switch]$ModifySettingsJson,
    [string]$CustomProfilePath,
    [string]$CustomModulePath,
    [string]$CustomFragmentPath
)

$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey('Language') -and $env:TERMINAL_AI_LANG -in @("uk", "ua")) {
    $Language = "uk"
}
$isUk = ($Language -eq "uk")

if ($Scope -eq "AllUsers") {
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    if (-not $isAdmin) {
        $msgAdmin = if ($isUk) { "[TerminalAI] Встановлення для всіх користувачів (-Scope AllUsers) вимагає прав адміністратора (Run as Administrator)." } else { "[TerminalAI] Installation for all users (-Scope AllUsers) requires Administrator privileges (Run as Administrator)." }
        Write-Error $msgAdmin
        return
    }
}

function Show-SpinnerWait {
    param(
        [string]$Message,
        [scriptblock]$Condition,
        [int]$TimeoutSec = 20,
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

$title = if ($isUk) { "   Встановлення TerminalAI (Windows Terminal & Ollama AI)   " } else { "   Installing TerminalAI (Windows Terminal & Ollama AI)   " }
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host $title -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# 1. Project directory check
$projectDir = $PSScriptRoot
if (-not $projectDir) { $projectDir = Get-Location }

$manifestPath = Join-Path $projectDir "TerminalAI.psd1"
if (-not (Test-Path $manifestPath)) {
    $msgNoPsd = if ($isUk) { "Не знайдено TerminalAI.psd1 у $projectDir" } else { "TerminalAI.psd1 not found in $projectDir" }
    Write-Error $msgNoPsd
    return
}

# 2. Ollama availability & installation
$step1 = if ($isUk) { "1. Перевірка Ollama в системі..." } else { "1. Checking Ollama in system..." }
Write-Host $step1 -ForegroundColor Yellow
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
$ollamaExeCandidates = @(
    "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
    "${env:ProgramFiles}\Ollama\ollama.exe"
)

if (-not $ollamaCmd) {
    foreach ($candidate in $ollamaExeCandidates) {
        if (Test-Path $candidate) {
            $ollamaDir = Split-Path -Parent $candidate
            $env:Path = "$ollamaDir;" + $env:Path
            $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
            break
        }
    }
}

if (-not $ollamaCmd) {
    $msgNoOllama = if ($isUk) { "   ⚠ Ollama не знайдено на вашому комп'ютері." } else { "   ⚠ Ollama was not found on your system." }
    Write-Host $msgNoOllama -ForegroundColor DarkYellow
    $shouldInstall = $false
    if ($AutoConfirm) {
        $shouldInstall = $true
    } elseif (-not [Console]::IsInputRedirected) {
        $promptInstall = if ($isUk) { "   Бажаєте встановити Ollama автоматично зараз? [Y/n]" } else { "   Do you want to install Ollama automatically now? [Y/n]" }
        $ans = Read-Host $promptInstall
        $shouldInstall = ($ans -match '^(y|yes|так|т|$)' -or [string]::IsNullOrWhiteSpace($ans))
    }

    if ($shouldInstall) {
        $msgStartInstall = if ($isUk) { "   ▶ Початок встановлення Ollama..." } else { "   ▶ Starting Ollama installation..." }
        Write-Host $msgStartInstall -ForegroundColor Cyan
        $installedViaWinget = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $msgWinget = if ($isUk) { "   • Встановлення через winget з таймером та прогресом..." } else { "   • Installing via winget..." }
            Write-Host $msgWinget -ForegroundColor DarkGray
            try {
                & winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -eq 0) { $installedViaWinget = $true }
            } catch { }
        }

        if (-not $installedViaWinget) {
            $installerUrl = "https://ollama.com/download/OllamaSetup.exe"
            $installerPath = Join-Path $env:TEMP "OllamaSetup.exe"
            $msgDownload = if ($isUk) { "   • Завантаження інсталятора з $installerUrl..." } else { "   • Downloading installer from $installerUrl..." }
            Write-Host $msgDownload -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
            $msgSilent = if ($isUk) { "   • Запуск тихого встановлення Ollama..." } else { "   • Launching silent Ollama installation..." }
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
        $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
        if ($ollamaCmd) {
            $msgInstalled = if ($isUk) { "   ✔ Ollama успішно встановлена!" } else { "   ✔ Ollama installed successfully!" }
            Write-Host $msgInstalled -ForegroundColor Green
        } else {
            $msgNotPath = if ($isUk) { "   ⚠ Встановлення завершено, але ollama.exe не знайдено в PATH." } else { "   ⚠ Installation finished, but ollama.exe was not found in PATH." }
            Write-Host $msgNotPath -ForegroundColor DarkYellow
        }
    } else {
        $msgSkipped = if ($isUk) { "   ⚠ Встановлення Ollama пропущено користувачем." } else { "   ⚠ Ollama installation skipped by user." }
        Write-Host $msgSkipped -ForegroundColor DarkGray
    }
} else {
    $msgFound = if ($isUk) { "   ✔ Ollama знайдена: $($ollamaCmd.Source)" } else { "   ✔ Ollama found: $($ollamaCmd.Source)" }
    Write-Host $msgFound -ForegroundColor Green
}

$ollamaUrl = "http://localhost:11434"
$installedModels = @()

# API readiness check
$isApiReady = $false
if (-not $SkipOllamaCheck) {
    foreach ($candUrl in @("http://127.0.0.1:11434", "http://localhost:11434")) {
        try {
            $tags = Invoke-RestMethod -Uri "$candUrl/api/tags" -TimeoutSec 1 -ErrorAction Stop
            $installedModels = @($tags.models.name)
            $isApiReady = $true
            $ollamaUrl = $candUrl
            break
        } catch { }
    }

    if (-not $isApiReady -and (Get-Command ollama -ErrorAction SilentlyContinue)) {
        $msgServeStart = if ($isUk) { "   • Служба Ollama не активна. Запуск фонового процесу..." } else { "   • Ollama service is inactive. Starting background process..." }
        Write-Host $msgServeStart -ForegroundColor DarkYellow
        Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue

        $spinnerMsg = if ($isUk) { "Очікування запуску локальної служби Ollama" } else { "Waiting for local Ollama service to start" }
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
}

if ($isApiReady) {
    $msgActive = if ($isUk) { "   ✔ Служба Ollama активна! Встановлено моделей: $($installedModels.Count)" } else { "   ✔ Ollama service is active! Installed models: $($installedModels.Count)" }
    Write-Host $msgActive -ForegroundColor Green
} else {
    $msgNotResp = if ($isUk) { "   ⚠ Ollama не відповідає на $ollamaUrl. Переконайтеся, що вона запущена ('ollama serve')." } else { "   ⚠ Ollama is not responding at $ollamaUrl. Make sure it is running ('ollama serve')." }
    Write-Host $msgNotResp -ForegroundColor DarkYellow
}

# 3. Hardware analysis & model recommendation
$step2 = if ($isUk) { "`n2. Аналіз конфігурації комп'ютера..." } else { "`n2. Analyzing system hardware configuration..." }
Write-Host $step2 -ForegroundColor Yellow
$ramGb = 16
$gpuName = if ($isUk) { "Не визначено" } else { "Not detected" }
try {
    $ramGb = [Math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB), 1)
    $gpuList = @(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name | Where-Object { $_ -notmatch 'Virtual|Remote|Basic' })
    if ($gpuList.Count -gt 0) { $gpuName = $gpuList[0] }
} catch { }

$lblRam = if ($isUk) { "   • Оперативна пам'ять (RAM):" } else { "   • Physical RAM:" }
$lblGpu = if ($isUk) { "   • Графічний адаптер (GPU): " } else { "   • Graphics Adapter (GPU): " }
Write-Host "$lblRam $ramGb GB" -ForegroundColor White
Write-Host "$lblGpu $gpuName" -ForegroundColor White

$recommendedModel = if ($ramGb -ge 16 -or $gpuName -match 'RTX|Radeon RX') {
    "qwen2.5-coder:7b"
} elseif ($ramGb -ge 12) {
    "qwen2.5-coder:3b"
} else {
    "qwen2.5-coder:1.5b"
}

$lblRec = if ($isUk) { "   💡 Рекомендована модель для вашої конфігурації: " } else { "   💡 Recommended model for your configuration: " }
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
if (-not $SkipOllamaCheck -and $installedModels -notcontains $selectedModel -and (Get-Command ollama -ErrorAction SilentlyContinue)) {
    $msgMissing = if ($isUk) { "`n   ⚠ Модель '$selectedModel' ще не завантажена в Ollama." } else { "`n   ⚠ Model '$selectedModel' is not yet downloaded in Ollama." }
    Write-Host $msgMissing -ForegroundColor DarkYellow
    $shouldPull = $false
    if ($AutoConfirm) {
        $shouldPull = $true
    } elseif (-not [Console]::IsInputRedirected) {
        $promptPull = if ($isUk) { "   Завантажити '$selectedModel' зараз через 'ollama pull'? [Y/n] (або введіть іншу назву моделі)" } else { "   Download '$selectedModel' now via 'ollama pull'? [Y/n] (or enter custom model name)" }
        $pullChoice = Read-Host $promptPull
        if ($pullChoice -match '^(y|yes|так|т|$)' -or [string]::IsNullOrWhiteSpace($pullChoice)) {
            $shouldPull = $true
        } elseif ($pullChoice -notmatch '^(n|no|ні|н)$') {
            $selectedModel = $pullChoice.Trim()
            $shouldPull = $true
        }
    }

    if ($shouldPull) {
        $msgPulling = if ($isUk) { "   ▶ Завантаження моделі '$selectedModel' (з нативним індикатором прогресу Ollama)..." } else { "   ▶ Downloading model '$selectedModel' (with native Ollama progress)..." }
        Write-Host $msgPulling -ForegroundColor Cyan
        & ollama pull $selectedModel
        if ($LASTEXITCODE -eq 0) {
            $msgPulled = if ($isUk) { "   ✔ Модель '$selectedModel' успішно завантажена!" } else { "   ✔ Model '$selectedModel' downloaded successfully!" }
            Write-Host $msgPulled -ForegroundColor Green
        }
    }
}

$lblSelected = if ($isUk) { "   Вибрана активна модель:" } else { "   Selected active model:" }
Write-Host "$lblSelected $selectedModel" -ForegroundColor Cyan

# 4. Module installation in PSModulePath
$step3 = if ($isUk) { "`n3. Реєстрація модуля PowerShell ($Scope)..." } else { "`n3. Registering PowerShell module ($Scope)..." }
Write-Host $step3 -ForegroundColor Yellow

$candidateRoots = @()
if ($CustomModulePath) {
    $candidateRoots = @($CustomModulePath)
} elseif ($Scope -eq "AllUsers") {
    $candidateRoots = @(
        "$env:ProgramFiles\PowerShell\Modules",
        "${env:ProgramFiles}\WindowsPowerShell\Modules"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
} else {
    $docsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $candidateRoots = @(
        (Join-Path $docsPath "PowerShell\Modules"),
        (Join-Path $docsPath "WindowsPowerShell\Modules")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
}

$destModuleDir = $null
foreach ($userModuleBase in $candidateRoots) {
    if (-not (Test-Path $userModuleBase)) {
        New-Item -ItemType Directory -Path $userModuleBase -Force | Out-Null
    }

    $destModuleDir = Join-Path $userModuleBase "TerminalAI"
    if (-not (Test-Path $destModuleDir)) {
        New-Item -ItemType Directory -Path $destModuleDir -Force | Out-Null
    }

    # Copy module files
    Copy-Item -Path (Join-Path $projectDir "TerminalAI.psd1") -Destination $destModuleDir -Force
    Copy-Item -Path (Join-Path $projectDir "TerminalAI.psm1") -Destination $destModuleDir -Force
    Copy-Item -Path (Join-Path $projectDir "TerminalAiConfig.ps1") -Destination $destModuleDir -Force
    Copy-Item -Path (Join-Path $projectDir "TerminalAiAssistant.ps1") -Destination $destModuleDir -Force
    Copy-Item -Path (Join-Path $projectDir "TerminalAiAgent.ps1") -Destination $destModuleDir -Force

    $aotDllPath = Join-Path $projectDir "TerminalAI.Aot.dll"
    if (-not (Test-Path $aotDllPath)) {
        $aotDllPath = Join-Path $projectDir "AOT\bin\Release\net10.0\TerminalAI.Aot.dll"
    }
    if (Test-Path $aotDllPath) {
        try {
            Copy-Item -Path $aotDllPath -Destination $destModuleDir -Force -ErrorAction Stop
        } catch { }
    }
    $aotHelpPath = Join-Path $projectDir "TerminalAI.Aot.dll-Help.xml"
    if (-not (Test-Path $aotHelpPath)) {
        $aotHelpPath = Join-Path $projectDir "AOT\TerminalAI.Aot.dll-Help.xml"
    }
    if (Test-Path $aotHelpPath) {
        try {
            Copy-Item -Path $aotHelpPath -Destination $destModuleDir -Force -ErrorAction Stop
        } catch { }
    }

    $msgSynced = if ($isUk) { "   ✔ Модуль успішно синхронізовано з: $destModuleDir" } else { "   ✔ Module successfully synchronized to: $destModuleDir" }
    Write-Host $msgSynced -ForegroundColor Green
}

# 5. Add delimited initialization block to $PROFILE
$targetProfile = if ($CustomProfilePath) {
    $CustomProfilePath
} elseif ($Scope -eq "AllUsers") {
    if ($PROFILE.AllUsersAllHosts) { $PROFILE.AllUsersAllHosts } else { $PROFILE.AllUsersCurrentHost }
} else {
    if ($PROFILE.CurrentUserCurrentHost) { $PROFILE.CurrentUserCurrentHost } else { $PROFILE }
}

$step4 = if ($isUk) { "`n4. Оновлення профілю PowerShell ($targetProfile)..." } else { "`n4. Updating PowerShell profile ($targetProfile)..." }
Write-Host $step4 -ForegroundColor Yellow

$startMarker = "# >>> TerminalAI Initialization >>>"
$endMarker = "# <<< TerminalAI Initialization <<<"
$blockContent = @"
$startMarker
# TerminalAI - Windows Terminal AI Extension for Ollama
if (Get-Module -ListAvailable -Name TerminalAI) {
    Import-Module TerminalAI -ErrorAction SilentlyContinue
}
$endMarker
"@

$profileDir = Split-Path -Parent $targetProfile
if ($profileDir -and -not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$profileExists = Test-Path $targetProfile
if ($profileExists) {
    $backupFile = "$targetProfile.bak." + (Get-Date -Format "yyyyMMdd_HHmmss")
    try {
        Copy-Item -Path $targetProfile -Destination $backupFile -Force
        $msgBak = if ($isUk) { "   ✔ Створено резервну копію профілю: $backupFile" } else { "   ✔ Created profile backup: $backupFile" }
        Write-Host $msgBak -ForegroundColor DarkGray
    } catch { }

    $profileContent = try {
        [System.IO.File]::ReadAllText($targetProfile, [System.Text.Encoding]::UTF8)
    } catch {
        Get-Content -Path $targetProfile -Raw -ErrorAction SilentlyContinue
    }
    if ($null -eq $profileContent) { $profileContent = "" }

    if ($profileContent -match '(?ms)# >>> TerminalAI Initialization >>>.*?# <<< TerminalAI Initialization <<<') {
        $newProfileContent = [regex]::Replace($profileContent, '(?ms)# >>> TerminalAI Initialization >>>.*?# <<< TerminalAI Initialization <<<', $blockContent)
        $msgUpdBlock = if ($isUk) { "   ✔ Оновлено наявний блок TerminalAI у $targetProfile" } else { "   ✔ Updated existing TerminalAI block in $targetProfile" }
        Write-Host $msgUpdBlock -ForegroundColor DarkGreen
    } elseif ($profileContent -match '(?ms)\r?\n?# TerminalAI[^\r\n]*\r?\n?Import-Module\s+TerminalAI[^\r\n]*') {
        $newProfileContent = [regex]::Replace($profileContent, '(?ms)\r?\n?# TerminalAI[^\r\n]*\r?\n?Import-Module\s+TerminalAI[^\r\n]*', "`n$blockContent")
        $msgLegacyUpd = if ($isUk) { "   ✔ Оновлено застарілий виклик Import-Module на маркований блок у $targetProfile" } else { "   ✔ Updated legacy Import-Module call to marked block in $targetProfile" }
        Write-Host $msgLegacyUpd -ForegroundColor Green
    } else {
        $separator = if ($profileContent.Length -gt 0 -and -not $profileContent.EndsWith("`n")) { "`n`n" } else { "`n" }
        $newProfileContent = $profileContent + $separator + $blockContent
        $msgAddBlock = if ($isUk) { "   ✔ Додано маркований блок TerminalAI у $targetProfile" } else { "   ✔ Added marked TerminalAI block to $targetProfile" }
        Write-Host $msgAddBlock -ForegroundColor Green
    }
} else {
    $newProfileContent = $blockContent
    $msgNewProf = if ($isUk) { "   ✔ Створено новий профіль з маркованим блоком: $targetProfile" } else { "   ✔ Created new profile with marked block: $targetProfile" }
    Write-Host $msgNewProf -ForegroundColor Green
}

$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($targetProfile, $newProfileContent, $enc)

# Initialize configuration
. (Join-Path $projectDir "TerminalAiConfig.ps1")
Set-TerminalAiConfig -Model $selectedModel -OllamaUrl $ollamaUrl -Language $Language | Out-Null

# 6. Windows Terminal Integration
if (-not $SkipTerminalConfig) {
    $step5 = if ($isUk) { "`n5. Налаштування Windows Terminal (Fragments & Actions)..." } else { "`n5. Configuring Windows Terminal (Fragments & Actions)..." }
    Write-Host $step5 -ForegroundColor Yellow

    # Register JSON Fragment Extension
    $fragDir = if ($CustomFragmentPath) {
        $CustomFragmentPath
    } elseif ($Scope -eq "AllUsers") {
        "$env:ProgramData\Microsoft\Windows Terminal\Fragments\TerminalAI"
    } else {
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\TerminalAI"
    }

    try {
        if (-not (Test-Path $fragDir)) {
            New-Item -ItemType Directory -Path $fragDir -Force | Out-Null
        }
        $fragSource = Join-Path $projectDir "terminalai.json"
        if (Test-Path $fragSource) {
            Copy-Item -Path $fragSource -Destination (Join-Path $fragDir "terminalai.json") -Force
            $msgFragReg = if ($isUk) { "   ✔ Зареєстровано Windows Terminal Fragment Extension ($Scope): $fragDir" } else { "   ✔ Registered Windows Terminal Fragment Extension ($Scope): $fragDir" }
            Write-Host $msgFragReg -ForegroundColor Green
        }
    } catch {
        $warnFrag = if ($isUk) { "   Не вдалося створити Fragment Extension: $($_.Exception.Message)" } else { "   Failed to create Fragment Extension: $($_.Exception.Message)" }
        Write-Warning $warnFrag
    }

    if ($ModifySettingsJson) {
        $msgLegacyWt = if ($isUk) { "   • Оновлення налаштувань actions у settings.json (legacy mode)..." } else { "   • Updating actions in settings.json (legacy mode)..." }
        Write-Host $msgLegacyWt -ForegroundColor DarkGray
        $wtSettingsCandidates = @(
            "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
            "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
            "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
        )

        $wtSettingsFile = $null
        foreach ($candidate in $wtSettingsCandidates) {
            if (Test-Path $candidate) {
                $wtSettingsFile = $candidate
                break
            }
        }

        if ($wtSettingsFile) {
            try {
                $backupFile = "$wtSettingsFile.terminalai.backup.json"
                Copy-Item -Path $wtSettingsFile -Destination $backupFile -Force
                $msgBakWt = if ($isUk) { "   ✔ Створено резервну копію: $backupFile" } else { "   ✔ Created backup: $backupFile" }
                Write-Host $msgBakWt -ForegroundColor DarkGray

                $wtJson = Get-Content -Path $wtSettingsFile -Raw | ConvertFrom-Json

                if ($null -eq $wtJson.actions) {
                    $wtJson | Add-Member -MemberType NoteProperty -Name "actions" -Value @()
                }

                $assistantScriptPath = if ($destModuleDir) { Join-Path $destModuleDir "TerminalAiAssistant.ps1" } else { Join-Path $projectDir "TerminalAiAssistant.ps1" }

                $actionAskName = if ($isUk) { "AI: Запитати Ollama (ai)" } else { "AI: Ask Ollama (ai)" }
                $actionFixName = if ($isUk) { "AI: Виправити останню помилку (ai-fix)" } else { "AI: Fix last error (ai-fix)" }
                $actionScriptName = if ($isUk) { "AI: Згенерувати сценарій (ai-script)" } else { "AI: Generate script (ai-script)" }
                $actionSplitName = if ($isUk) { "AI: Відкрити асистента у спліт-панелі" } else { "AI: Open assistant in split pane" }

                $aiActions = @(
                    [ordered]@{
                        name = $actionAskName
                        command = [ordered]@{
                            action = "sendInput"
                            input = "ai `""
                        }
                    },
                    [ordered]@{
                        name = $actionFixName
                        command = [ordered]@{
                            action = "sendInput"
                            input = "ai-fix`r"
                        }
                    },
                    [ordered]@{
                        name = $actionScriptName
                        command = [ordered]@{
                            action = "sendInput"
                            input = "ai-script `""
                        }
                    },
                    [ordered]@{
                        name = $actionSplitName
                        command = [ordered]@{
                            action = "splitPane"
                            split = "vertical"
                            size = 0.4
                            commandline = "pwsh.exe -NoExit -File `"$($assistantScriptPath -replace '\\', '\\')`""
                        }
                    }
                )

                $existingNames = $wtJson.actions | ForEach-Object { $_.name }
                $addedCount = 0

                $newActionsList = [System.Collections.Generic.List[object]]::new()
                if ($wtJson.actions) {
                    foreach ($a in $wtJson.actions) { $newActionsList.Add($a) }
                }

                foreach ($action in $aiActions) {
                    if ($existingNames -notcontains $action.name) {
                        $newActionsList.Add($action)
                        $addedCount++
                    }
                }

                $wtJson.actions = $newActionsList.ToArray()
                $newSettingsJson = $wtJson | ConvertTo-Json -Depth 10
                Set-Content -Path $wtSettingsFile -Value $newSettingsJson -Encoding UTF8
                $msgAddedActions = if ($isUk) { "   ✔ Додано дій Windows Terminal: $addedCount (файл: $wtSettingsFile)" } else { "   ✔ Added Windows Terminal actions: $addedCount (file: $wtSettingsFile)" }
                Write-Host $msgAddedActions -ForegroundColor Green
            }
            catch {
                $warnModWt = if ($isUk) { "   Не вдалося модифікувати налаштування Windows Terminal: $($_.Exception.Message)" } else { "   Failed to modify Windows Terminal settings: $($_.Exception.Message)" }
                Write-Warning $warnModWt
            }
        }
    } else {
        $msgFragClean = if ($isUk) { "   ℹ Windows Terminal Fragment Extension активовано (неінвазивний режим, settings.json залишено чистим)." } else { "   ℹ Windows Terminal Fragment Extension active (non-invasive mode, settings.json left untouched)." }
        Write-Host $msgFragClean -ForegroundColor DarkCyan
    }
}

if ($isUk) {
    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "             Встановлення завершено успішно!                  " -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Як почати користуватися прямо зараз:" -ForegroundColor Yellow
    Write-Host "  1. Перезавантажте сесію або виконайте:  . `$PROFILE" -ForegroundColor White
    Write-Host "  2. Спробуйте в терміналі:" -ForegroundColor White
    Write-Host "     • ai знайти всі великі файли в поточній папці" -ForegroundColor DarkCyan
    Write-Host "     • ai-fix   (якщо попередня команда викликала помилку)" -ForegroundColor DarkCyan
    Write-Host "     • ai-script `"архівація та логування`"" -ForegroundColor DarkCyan
    Write-Host "     • Напишіть у рядку '# створити zip архів' і натисніть Ctrl+Alt+A" -ForegroundColor DarkCyan
    Write-Host "  3. У Windows Terminal натисніть Ctrl+Shift+P і шукайте 'AI:'`n" -ForegroundColor White
} else {
    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "             Installation completed successfully!              " -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "How to get started right now:" -ForegroundColor Yellow
    Write-Host "  1. Reload session or run:  . `$PROFILE" -ForegroundColor White
    Write-Host "  2. Try in terminal:" -ForegroundColor White
    Write-Host "     • ai find all large files in current directory" -ForegroundColor DarkCyan
    Write-Host "     • ai-fix   (if previous command threw an error)" -ForegroundColor DarkCyan
    Write-Host "     • ai-script `"backup and logging`"" -ForegroundColor DarkCyan
    Write-Host "     • Type '# create zip archive' and press Ctrl+Alt+A" -ForegroundColor DarkCyan
    Write-Host "  3. In Windows Terminal press Ctrl+Shift+P and search for 'AI:'`n" -ForegroundColor White
}
