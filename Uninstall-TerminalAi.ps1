# Uninstall-TerminalAi.ps1 - Деінсталятор розширення TerminalAI

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

Write-Host "`nВидалення розширення TerminalAI..." -ForegroundColor Yellow

# 1. Видалення модуля з PSModulePath
$docsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
$candidateRoots = @(
    ($env:PSModulePath -split ';')[0],
    (Join-Path $docsPath "PowerShell\Modules"),
    (Join-Path $docsPath "WindowsPowerShell\Modules")
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

foreach ($baseRoot in $candidateRoots) {
    $destModuleDir = Join-Path $baseRoot "TerminalAI"
    if (Test-Path $destModuleDir) {
        Remove-Item -Path $destModuleDir -Recurse -Force
        Write-Host "✔ Каталог модуля видалено: $destModuleDir" -ForegroundColor Green
    }
}

# 2. Очищення $PROFILE
if (Test-Path $PROFILE) {
    $content = Get-Content -Path $PROFILE -Raw
    $newContent = $content -replace "(?ms)\r?\n# TerminalAI - Windows Terminal AI Extension for Ollama\r?\nImport-Module TerminalAI -ErrorAction SilentlyContinue\r?\n?", ""
    if ($content -ne $newContent) {
        Set-Content -Path $PROFILE -Value $newContent -Encoding UTF8
        Write-Host "✔ Видалено згадки TerminalAI з $PROFILE" -ForegroundColor Green
    }
}

# 3. Очищення дій Windows Terminal
$wtSettingsCandidates = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

foreach ($wtSettingsFile in $wtSettingsCandidates) {
    if (Test-Path $wtSettingsFile) {
        try {
            $wtJson = Get-Content -Path $wtSettingsFile -Raw | ConvertFrom-Json
            if ($wtJson.actions) {
                $filteredActions = $wtJson.actions | Where-Object { $_.name -notmatch '^AI:' }
                $wtJson.actions = @($filteredActions)
                $newSettingsJson = $wtJson | ConvertTo-Json -Depth 10
                Set-Content -Path $wtSettingsFile -Value $newSettingsJson -Encoding UTF8
                Write-Host "✔ Очищено дії AI з $wtSettingsFile" -ForegroundColor Green
            }
        } catch {
            Write-Warning "Помилка при очищенні ${wtSettingsFile}: $_"
        }
    }
}

# 4. Очищення JSON Fragment Extension
$fragDir = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\TerminalAI"
if (Test-Path $fragDir) {
    Remove-Item -Path $fragDir -Recurse -Force
    Write-Host "✔ Видалено Fragment Extension з $fragDir" -ForegroundColor Green
}

Write-Host "Деінсталяцію завершено.`n" -ForegroundColor Green
