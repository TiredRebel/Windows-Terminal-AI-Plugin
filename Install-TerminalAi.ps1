[CmdletBinding()]
param(
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",

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

if ($Scope -eq "AllUsers") {
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    if (-not $isAdmin) {
        Write-Error "[TerminalAI] Встановлення для всіх користувачів (-Scope AllUsers) вимагає прав адміністратора (Run as Administrator)."
        return
    }
}

function Show-SpinnerWait {
    param(
        [string]$Message,
        [scriptblock]$Condition,
        [int]$TimeoutSec = 20
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $chars = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
    $i = 0
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if (& $Condition) {
            Write-Host "`r   ✔ $Message - готово! ($([Math]::Round($sw.Elapsed.TotalSeconds, 1))с)          " -ForegroundColor Green
            return $true
        }
        $c = $chars[$i % $chars.Count]
        $i++
        $elapsed = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        Write-Host -NoNewline "`r   $c $Message (${elapsed}с / ${TimeoutSec}с)... "
        Start-Sleep -Milliseconds 250
    }
    Write-Host "`n   ⚠ Час очікування вичерпано." -ForegroundColor DarkYellow
    return $false
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Встановлення TerminalAI (Windows Terminal & Ollama AI)   " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# 1. Перевірка директорії проєкту
$projectDir = $PSScriptRoot
if (-not $projectDir) { $projectDir = Get-Location }

$manifestPath = Join-Path $projectDir "TerminalAI.psd1"
if (-not (Test-Path $manifestPath)) {
    Write-Error "Не знайдено TerminalAI.psd1 у $projectDir"
    return
}

# 2. Перевірка наявності та встановлення Ollama
Write-Host "1. Перевірка Ollama в системі..." -ForegroundColor Yellow
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
    Write-Host "   ⚠ Ollama не знайдено на вашому комп'ютері." -ForegroundColor DarkYellow
    $shouldInstall = $false
    if ($AutoConfirm) {
        $shouldInstall = $true
    } elseif (-not [Console]::IsInputRedirected) {
        $ans = Read-Host "   Бажаєте встановити Ollama автоматично зараз? [Y/n]"
        $shouldInstall = ($ans -match '^(y|yes|так|т|$)' -or [string]::IsNullOrWhiteSpace($ans))
    }

    if ($shouldInstall) {
        Write-Host "   ▶ Початок встановлення Ollama..." -ForegroundColor Cyan
        $installedViaWinget = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "   • Встановлення через winget з таймером та прогресом..." -ForegroundColor DarkGray
            try {
                & winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -eq 0) { $installedViaWinget = $true }
            } catch { }
        }

        if (-not $installedViaWinget) {
            $installerUrl = "https://ollama.com/download/OllamaSetup.exe"
            $installerPath = Join-Path $env:TEMP "OllamaSetup.exe"
            Write-Host "   • Завантаження інсталятора з $installerUrl..." -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
            Write-Host "   • Запуск тихого встановлення Ollama..." -ForegroundColor DarkGray
            Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait
        }

        # Оновлюємо PATH після встановлення
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        foreach ($candidate in $ollamaExeCandidates) {
            if (Test-Path $candidate) {
                $env:Path = (Split-Path -Parent $candidate) + ";" + $env:Path
                break
            }
        }
        $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
        if ($ollamaCmd) {
            Write-Host "   ✔ Ollama успішно встановлена!" -ForegroundColor Green
        } else {
            Write-Host "   ⚠ Встановлення завершено, але ollama.exe не знайдено в PATH." -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "   ⚠ Встановлення Ollama пропущено користувачем." -ForegroundColor DarkGray
    }
} else {
    Write-Host "   ✔ Ollama знайдена: $($ollamaCmd.Source)" -ForegroundColor Green
}

$ollamaUrl = "http://localhost:11434"
$installedModels = @()

# Перевірка доступності API (перевіряємо прямий IPv4 127.0.0.1, потім localhost)
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
        Write-Host "   • Служба Ollama не активна. Запуск фонового процесу..." -ForegroundColor DarkYellow
        Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue

        $isApiReady = Show-SpinnerWait -Message "Очікування запуску локальної служби Ollama" -TimeoutSec 10 -Condition {
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
    Write-Host "   ✔ Служба Ollama активна! Встановлено моделей: $($installedModels.Count)" -ForegroundColor Green
} else {
    Write-Host "   ⚠ Ollama не відповідає на $ollamaUrl. Переконайтеся, що вона запущена ('ollama serve')." -ForegroundColor DarkYellow
}

# 3. Аналіз апаратного забезпечення та підбір моделі
Write-Host "`n2. Аналіз конфігурації комп'ютера..." -ForegroundColor Yellow
$ramGb = 16
$gpuName = "Не визначено"
try {
    $ramGb = [Math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB), 1)
    $gpuList = @(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name | Where-Object { $_ -notmatch 'Virtual|Remote|Basic' })
    if ($gpuList.Count -gt 0) { $gpuName = $gpuList[0] }
} catch { }

Write-Host "   • Оперативна пам'ять (RAM): $ramGb GB" -ForegroundColor White
Write-Host "   • Графічний адаптер (GPU):  $gpuName" -ForegroundColor White

# Визначаємо оптимальну рекомендовану модель за апаратними характеристиками
$recommendedModel = if ($ramGb -ge 16 -or $gpuName -match 'RTX|Radeon RX') {
    "qwen2.5-coder:7b"
} elseif ($ramGb -ge 12) {
    "qwen2.5-coder:3b"
} else {
    "qwen2.5-coder:1.5b"
}

Write-Host "   💡 Рекомендована модель для вашої конфігурації: " -NoNewline -ForegroundColor Cyan
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

# Якщо рекомендованої/обраної моделі ще немає серед встановлених
if (-not $SkipOllamaCheck -and $installedModels -notcontains $selectedModel -and (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Host "`n   ⚠ Модель '$selectedModel' ще не завантажена в Ollama." -ForegroundColor DarkYellow
    $shouldPull = $false
    if ($AutoConfirm) {
        $shouldPull = $true
    } elseif (-not [Console]::IsInputRedirected) {
        $pullChoice = Read-Host "   Завантажити '$selectedModel' зараз через 'ollama pull'? [Y/n] (або введіть іншу назву моделі)"
        if ($pullChoice -match '^(y|yes|так|т|$)' -or [string]::IsNullOrWhiteSpace($pullChoice)) {
            $shouldPull = $true
        } elseif ($pullChoice -notmatch '^(n|no|ні|н)$') {
            $selectedModel = $pullChoice.Trim()
            $shouldPull = $true
        }
    }

    if ($shouldPull) {
        Write-Host "   ▶ Завантаження моделі '$selectedModel' (з нативним індикатором прогресу Ollama)..." -ForegroundColor Cyan
        & ollama pull $selectedModel
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✔ Модель '$selectedModel' успішно завантажена!" -ForegroundColor Green
        }
    }
}

Write-Host "   Вибрана активна модель: $selectedModel" -ForegroundColor Cyan

# 4. Встановлення модуля у PSModulePath (CurrentUser або AllUsers)
Write-Host "`n3. Реєстрація модуля PowerShell ($Scope)..." -ForegroundColor Yellow

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

    # Копіюємо оновлені файли модуля
    Copy-Item -Path (Join-Path $projectDir "TerminalAI.psd1") -Destination $destModuleDir -Force
    Copy-Item -Path (Join-Path $projectDir "TerminalAI.psm1") -Destination $destModuleDir -Force
    Copy-Item -Path (Join-Path $projectDir "TerminalAiConfig.ps1") -Destination $destModuleDir -Force
    Copy-Item -Path (Join-Path $projectDir "TerminalAiAssistant.ps1") -Destination $destModuleDir -Force

    $aotDllPath = Join-Path $projectDir "TerminalAI.Aot.dll"
    if (-not (Test-Path $aotDllPath)) {
        $aotDllPath = Join-Path $projectDir "AOT\bin\Release\net10.0\TerminalAI.Aot.dll"
    }
    if (Test-Path $aotDllPath) {
        try {
            Copy-Item -Path $aotDllPath -Destination $destModuleDir -Force -ErrorAction Stop
        } catch {
            Write-Verbose "TerminalAI.Aot.dll наразі заблокована відкритим процесом, залишаємо наявну версію."
        }
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

    Write-Host "   ✔ Модуль успішно синхронізовано з: $destModuleDir" -ForegroundColor Green
}

# 4. Додавання автоімпорту до $PROFILE з чіткими межами блоку
$targetProfile = if ($CustomProfilePath) {
    $CustomProfilePath
} elseif ($Scope -eq "AllUsers") {
    if ($PROFILE.AllUsersAllHosts) { $PROFILE.AllUsersAllHosts } else { $PROFILE.AllUsersCurrentHost }
} else {
    if ($PROFILE.CurrentUserCurrentHost) { $PROFILE.CurrentUserCurrentHost } else { $PROFILE }
}

Write-Host "`n4. Оновлення профілю PowerShell ($targetProfile)..." -ForegroundColor Yellow

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
        Write-Host "   ✔ Створено резервну копію профілю: $backupFile" -ForegroundColor DarkGray
    } catch { }

    $profileContent = try {
        [System.IO.File]::ReadAllText($targetProfile, [System.Text.Encoding]::UTF8)
    } catch {
        Get-Content -Path $targetProfile -Raw -ErrorAction SilentlyContinue
    }
    if ($null -eq $profileContent) { $profileContent = "" }

    if ($profileContent -match '(?ms)# >>> TerminalAI Initialization >>>.*?# <<< TerminalAI Initialization <<<') {
        $newProfileContent = [regex]::Replace($profileContent, '(?ms)# >>> TerminalAI Initialization >>>.*?# <<< TerminalAI Initialization <<<', $blockContent)
        Write-Host "   ✔ Оновлено наявний блок TerminalAI у $targetProfile" -ForegroundColor DarkGreen
    } elseif ($profileContent -match '(?ms)\r?\n?# TerminalAI[^\r\n]*\r?\n?Import-Module\s+TerminalAI[^\r\n]*') {
        $newProfileContent = [regex]::Replace($profileContent, '(?ms)\r?\n?# TerminalAI[^\r\n]*\r?\n?Import-Module\s+TerminalAI[^\r\n]*', "`n$blockContent")
        Write-Host "   ✔ Оновлено застарілий виклик Import-Module на маркований блок у $targetProfile" -ForegroundColor Green
    } else {
        $separator = if ($profileContent.Length -gt 0 -and -not $profileContent.EndsWith("`n")) { "`n`n" } else { "`n" }
        $newProfileContent = $profileContent + $separator + $blockContent
        Write-Host "   ✔ Додано маркований блок TerminalAI у $targetProfile" -ForegroundColor Green
    }
} else {
    $newProfileContent = $blockContent
    Write-Host "   ✔ Створено новий профіль з маркованим блоком: $targetProfile" -ForegroundColor Green
}

$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($targetProfile, $newProfileContent, $enc)

# Ініціалізуємо конфіг
. (Join-Path $projectDir "TerminalAiConfig.ps1")
Set-TerminalAiConfig -Model $selectedModel -OllamaUrl $ollamaUrl | Out-Null

# 5. Інтеграція з Windows Terminal
if (-not $SkipTerminalConfig) {
    Write-Host "`n5. Налаштування Windows Terminal (Fragments & Actions)..." -ForegroundColor Yellow

    # Реєстрація офіційного JSON Fragment Extension у Windows Terminal
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
            Write-Host "   ✔ Зареєстровано Windows Terminal Fragment Extension ($Scope): $fragDir" -ForegroundColor Green
        }
    } catch {
        Write-Warning "   Не вдалося створити Fragment Extension: $($_.Exception.Message)"
    }

    if ($ModifySettingsJson) {
        Write-Host "   • Оновлення налаштувань actions у settings.json (legacy mode)..." -ForegroundColor DarkGray
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
                Write-Host "   ✔ Створено резервну копію: $backupFile" -ForegroundColor DarkGray

                $wtJson = Get-Content -Path $wtSettingsFile -Raw | ConvertFrom-Json

                if ($null -eq $wtJson.actions) {
                    $wtJson | Add-Member -MemberType NoteProperty -Name "actions" -Value @()
                }

                # Створюємо потрібні дії
                $assistantScriptPath = if ($destModuleDir) { Join-Path $destModuleDir "TerminalAiAssistant.ps1" } else { Join-Path $projectDir "TerminalAiAssistant.ps1" }
                $aiActions = @(
                    [ordered]@{
                        name = "AI: Запитати Ollama (ai)"
                        command = [ordered]@{
                            action = "sendInput"
                            input = "ai `""
                        }
                    },
                    [ordered]@{
                        name = "AI: Виправити останню помилку (ai-fix)"
                        command = [ordered]@{
                            action = "sendInput"
                            input = "ai-fix`r"
                        }
                    },
                    [ordered]@{
                        name = "AI: Згенерувати сценарій (ai-script)"
                        command = [ordered]@{
                            action = "sendInput"
                            input = "ai-script `""
                        }
                    },
                    [ordered]@{
                        name = "AI: Відкрити асистента у спліт-панелі"
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
                Write-Host "   ✔ Додано дій Windows Terminal: $addedCount (файл: $wtSettingsFile)" -ForegroundColor Green
            }
            catch {
                Write-Warning "   Не вдалося модифікувати налаштування Windows Terminal: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "   ℹ Windows Terminal Fragment Extension активовано (неінвазивний режим, settings.json залишено чистим)." -ForegroundColor DarkCyan
    }
}

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
Write-Host "  3. У Windows Terminal натисніть Ctrl+Shift+P і шукайте 'AI:'" -ForegroundColor White
Write-Host ""
