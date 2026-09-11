# Install-TerminalAi.ps1 - Інсталятор розширення TerminalAI для Windows Terminal та PowerShell
[CmdletBinding()]
param(
    [switch]$SkipTerminalConfig,
    [string]$PreferredModel
)

$ErrorActionPreference = "Stop"

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

# 2. Перевірка зв'язку з локальною Ollama
Write-Host "1. Перевірка локальної Ollama..." -ForegroundColor Yellow
$ollamaUrl = "http://localhost:11434"
$installedModels = @()
try {
    $tags = Invoke-RestMethod -Uri "$ollamaUrl/api/tags" -TimeoutSec 4 -ErrorAction Stop
    $installedModels = $tags.models.name
    Write-Host "   ✔ Ollama активна! Знайдено моделей: $($installedModels.Count)" -ForegroundColor Green
} catch {
    Write-Host "   ⚠ Увага: Ollama не відповідає на $ollamaUrl." -ForegroundColor DarkYellow
    Write-Host "     Переконайтеся, що Ollama запущена (виконайте 'ollama serve')." -ForegroundColor DarkGray
}

# Визначаємо найкращу модель
$selectedModel = "qwen2.5-coder:7b"
if ($PreferredModel) {
    $selectedModel = $PreferredModel
} elseif ($installedModels.Count -gt 0) {
    $candidats = @("qwen2.5-coder:7b", "qwen3.5-coder:9b", "granite4.2:8b", "qwen3.5:9b")
    foreach ($cand in $candidats) {
        if ($installedModels -contains $cand) {
            $selectedModel = $cand
            break
        }
    }
}
Write-Host "   Вибрана модель за замовчуванням: $selectedModel" -ForegroundColor Cyan

# 3. Встановлення модуля у PSModulePath
Write-Host "`n2. Реєстрація модуля PowerShell..." -ForegroundColor Yellow
$userModuleBase = ($env:PSModulePath -split ';')[0]
if (-not (Test-Path $userModuleBase)) {
    New-Item -ItemType Directory -Path $userModuleBase -Force | Out-Null
}

$destModuleDir = Join-Path $userModuleBase "TerminalAI"
if (Test-Path $destModuleDir) {
    Remove-Item -Path $destModuleDir -Recurse -Force
}

# Створюємо директорію та копіюємо файли модуля
New-Item -ItemType Directory -Path $destModuleDir -Force | Out-Null
Copy-Item -Path (Join-Path $projectDir "TerminalAI.psd1") -Destination $destModuleDir -Force
Copy-Item -Path (Join-Path $projectDir "TerminalAI.psm1") -Destination $destModuleDir -Force
Copy-Item -Path (Join-Path $projectDir "TerminalAiConfig.ps1") -Destination $destModuleDir -Force
Copy-Item -Path (Join-Path $projectDir "TerminalAiAssistant.ps1") -Destination $destModuleDir -Force

Write-Host "   ✔ Модуль скопійовано до: $destModuleDir" -ForegroundColor Green

# 4. Додавання автоімпорту до $PROFILE
Write-Host "`n3. Оновлення профілю PowerShell ($PROFILE)..." -ForegroundColor Yellow
if (-not (Test-Path $PROFILE)) {
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$profileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileContent -notmatch 'Import-Module\s+TerminalAI') {
    $importSnippet = "`n# TerminalAI - Windows Terminal AI Extension for Ollama`nImport-Module TerminalAI -Force -ErrorAction SilentlyContinue`n"
    Add-Content -Path $PROFILE -Value $importSnippet -Encoding UTF8
    Write-Host "   ✔ Додано 'Import-Module TerminalAI' у $PROFILE" -ForegroundColor Green
} else {
    Write-Host "   ✔ Модуль вже прописано в $PROFILE" -ForegroundColor DarkGreen
}

# Ініціалізуємо конфіг
. (Join-Path $projectDir "TerminalAiConfig.ps1")
Set-TerminalAiConfig -Model $selectedModel -OllamaUrl $ollamaUrl | Out-Null

# 5. Інтеграція з Windows Terminal (settings.json)
if (-not $SkipTerminalConfig) {
    Write-Host "`n4. Налаштування Windows Terminal (actions & palette)..." -ForegroundColor Yellow

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
                        commandline = "pwsh.exe -NoExit -File `"$((Join-Path $destModuleDir 'TerminalAiAssistant.ps1') -replace '\\', '\\')`""
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
    } else {
        Write-Host "   Налаштувань Windows Terminal не знайдено за стандартними шляхами." -ForegroundColor DarkYellow
    }

    # Реєстрація офіційного JSON Fragment Extension у Windows Terminal (вкладка 'Extensions')
    $fragDir = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\TerminalAI"
    try {
        if (-not (Test-Path $fragDir)) {
            New-Item -ItemType Directory -Path $fragDir -Force | Out-Null
        }
        $fragSource = Join-Path $projectDir "terminalai.json"
        if (Test-Path $fragSource) {
            Copy-Item -Path $fragSource -Destination (Join-Path $fragDir "terminalai.json") -Force
            Write-Host "   ✔ Зареєстровано Windows Terminal Fragment Extension у вкладці 'Extensions': $fragDir" -ForegroundColor Green
        }
    } catch {
        Write-Warning "   Не вдалося створити Fragment Extension: $($_.Exception.Message)"
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
