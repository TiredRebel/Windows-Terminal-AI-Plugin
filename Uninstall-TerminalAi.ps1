# Uninstall-TerminalAi.ps1 - Деінсталятор розширення TerminalAI

[CmdletBinding()]
param(
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",

    [switch]$PurgeConfig,
    [string]$CustomProfilePath,
    [string]$CustomModulePath,
    [string]$CustomFragmentPath
)

$ErrorActionPreference = "Continue"

Write-Host "`nВидалення розширення TerminalAI ($Scope)..." -ForegroundColor Yellow

if ($Scope -eq "AllUsers") {
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    if (-not $isAdmin) {
        Write-Error "[TerminalAI] Видалення для всіх користувачів (-Scope AllUsers) вимагає прав адміністратора (Run as Administrator)."
        return
    }
}

# 1. Видалення модуля з PSModulePath
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

foreach ($baseRoot in $candidateRoots) {
    $destModuleDir = Join-Path $baseRoot "TerminalAI"
    if (Test-Path $destModuleDir) {
        Remove-Item -Path $destModuleDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "✔ Каталог модуля видалено: $destModuleDir" -ForegroundColor Green
    }
}

# 2. Очищення $PROFILE від маркованого блоку
$targetProfile = if ($CustomProfilePath) {
    $CustomProfilePath
} elseif ($Scope -eq "AllUsers") {
    if ($PROFILE.AllUsersAllHosts) { $PROFILE.AllUsersAllHosts } else { $PROFILE.AllUsersCurrentHost }
} else {
    if ($PROFILE.CurrentUserCurrentHost) { $PROFILE.CurrentUserCurrentHost } else { $PROFILE }
}

if ($targetProfile -and (Test-Path $targetProfile)) {
    $profileContent = try {
        [System.IO.File]::ReadAllText($targetProfile, [System.Text.Encoding]::UTF8)
    } catch {
        Get-Content -Path $targetProfile -Raw -ErrorAction SilentlyContinue
    }

    if ($profileContent) {
        $backupFile = "$targetProfile.bak." + (Get-Date -Format "yyyyMMdd_HHmmss")
        try {
            Copy-Item -Path $targetProfile -Destination $backupFile -Force
            Write-Host "✔ Створено резервну копію профілю перед деінсталяцією: $backupFile" -ForegroundColor DarkGray
        } catch { }

        $cleanContent = [regex]::Replace($profileContent, '(?ms)\r?\n?# >>> TerminalAI Initialization >>>.*?# <<< TerminalAI Initialization <<<\r?\n?', '')
        $cleanContent = [regex]::Replace($cleanContent, '(?ms)\r?\n?# TerminalAI[^\r\n]*\r?\n?Import-Module\s+TerminalAI[^\r\n]*\r?\n?', '')

        if ($cleanContent -ne $profileContent) {
            $enc = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($targetProfile, $cleanContent.TrimEnd() + "`n", $enc)
            Write-Host "✔ Видалено блок ініціалізації TerminalAI з $targetProfile" -ForegroundColor Green
        }
    }
}

# 3. Очищення дій Windows Terminal у settings.json (якщо вони були додані)
$wtSettingsCandidates = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
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
$fragDir = if ($CustomFragmentPath) {
    $CustomFragmentPath
} elseif ($Scope -eq "AllUsers") {
    "$env:ProgramData\Microsoft\Windows Terminal\Fragments\TerminalAI"
} else {
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\TerminalAI"
}

if (Test-Path $fragDir) {
    Remove-Item -Path $fragDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✔ Видалено Fragment Extension з $fragDir" -ForegroundColor Green
}

# 5. Очищення або збереження каталогу конфігурації
$cfgDir = if ($env:TERMINAL_AI_CONFIG_DIR) { $env:TERMINAL_AI_CONFIG_DIR } else { Join-Path $HOME ".terminal-ai" }
if ($PurgeConfig) {
    if (Test-Path $cfgDir) {
        Remove-Item -Path $cfgDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "✔ Видалено директорію конфігурації: $cfgDir" -ForegroundColor Green
    }
} else {
    if (Test-Path $cfgDir) {
        Write-Host "ℹ Конфігурацію збережено у $cfgDir (використовуйте -PurgeConfig для повного видалення)." -ForegroundColor DarkCyan
    }
}

Write-Host "Деінсталяцію завершено.`n" -ForegroundColor Green
