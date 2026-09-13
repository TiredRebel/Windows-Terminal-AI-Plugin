# Install-TerminalAi.ps1 - Orchestrator for the TerminalAI product installers.
# Multi-user installer supporting -Scope CurrentUser (default) and -Scope AllUsers.
# English is primary default language; Ukrainian on demand via -Language uk.
#
# TerminalAI installs as four independent products:
#   Core             PowerShell module (ai, ai-fix, ai-script, ai-chat, ai-doctor). Required.
#   Ollama           Detects/installs Ollama, analyzes hardware, pulls a model.
#   Aot              Compiled C# accelerator module (aif / ai-fast). Needs PowerShell 7+ / .NET 10.
#   WindowsTerminal  Fragment extension, profiles, and command-palette actions.
#
# By default this script installs all four, exactly like earlier versions of
# the installer did. Use -Products to pick a subset:
#   .\Install-TerminalAi.ps1 -Products Core,Ollama
#   .\Install-TerminalAi.ps1 -Products Core -Language uk
#
# Each product also ships as a standalone script under .\installers\, so a
# single product can be (re)installed later without running the whole bundle:
#   .\installers\Install-Core.ps1
#   .\installers\Install-Ollama.ps1
#   .\installers\Install-Aot.ps1
#   .\installers\Install-WindowsTerminal.ps1

[CmdletBinding()]
param(
    [ValidateSet("Core", "Ollama", "Aot", "WindowsTerminal", "All")]
    [string[]]$Products = @("All"),

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

$projectDir = $PSScriptRoot
if (-not $projectDir) { $projectDir = Get-Location }
$installersDir = Join-Path $projectDir "installers"

. (Join-Path $installersDir "InstallerCommon.ps1")

$title = if ($isUk) { "   Встановлення TerminalAI (Windows Terminal & Ollama AI)   " } else { "   Installing TerminalAI (Windows Terminal & Ollama AI)   " }
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host $title -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Resolve the requested product set. -SkipOllamaCheck / -SkipTerminalConfig are
# kept for backward compatibility with existing automation and, on an "All" run,
# drop those two products just like they always skipped those steps before.
# Combine -Products with them explicitly for the same effect going forward.
$requestedAll = $Products -contains "All"
$basis = if ($requestedAll) { @("Core", "Ollama", "Aot", "WindowsTerminal") } else { @($Products) }

$excluded = @()
if ($SkipOllamaCheck) { $excluded += "Ollama" }
if ($SkipTerminalConfig) { $excluded += "WindowsTerminal" }

$orderedProducts = @("Core", "Ollama", "Aot", "WindowsTerminal") | Where-Object {
    $basis -contains $_ -and $excluded -notcontains $_
}

if (-not $orderedProducts) {
    $msgNothing = if ($isUk) { "Не вибрано жодного продукту для встановлення (-Products)." } else { "No product selected for installation (-Products)." }
    Write-Warning $msgNothing
    return
}

# One admin check up front, covering every product that writes to a
# scope-dependent, machine-wide location under -Scope AllUsers.
$needsAdminCheck = @("Core", "Aot", "WindowsTerminal") | Where-Object { $orderedProducts -contains $_ }
if ($needsAdminCheck -and -not (Assert-TerminalAiScopeAdmin -Scope $Scope -IsUkrainian $isUk)) {
    return
}

$lblPlan = if ($isUk) { "Продукти для встановлення: " } else { "Products to install: " }
Write-Host "$lblPlan$($orderedProducts -join ', ')`n" -ForegroundColor DarkCyan

foreach ($product in $orderedProducts) {
    switch ($product) {
        "Core" {
            & (Join-Path $installersDir "Install-Core.ps1") `
                -Scope $Scope -Language $Language `
                -CustomProfilePath $CustomProfilePath -CustomModulePath $CustomModulePath
        }
        "Ollama" {
            & (Join-Path $installersDir "Install-Ollama.ps1") `
                -Language $Language -PreferredModel $PreferredModel -AutoConfirm:$AutoConfirm
        }
        "Aot" {
            & (Join-Path $installersDir "Install-Aot.ps1") `
                -Scope $Scope -Language $Language -CustomModulePath $CustomModulePath
        }
        "WindowsTerminal" {
            & (Join-Path $installersDir "Install-WindowsTerminal.ps1") `
                -Scope $Scope -Language $Language -ModifySettingsJson:$ModifySettingsJson `
                -CustomFragmentPath $CustomFragmentPath -CustomModulePath $CustomModulePath
        }
    }
    Write-Host ""
}

if ($orderedProducts -contains "Core") {
    if ($isUk) {
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "             Встановлення завершено успішно!                  " -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "Як почати користуватися прямо зараз:" -ForegroundColor Yellow
        Write-Host "  1. Перезавантажте сесію або виконайте:  . `$PROFILE" -ForegroundColor White
        Write-Host "  2. Спробуйте в терміналі:" -ForegroundColor White
        Write-Host "     • ai знайти всі великі файли в поточній папці" -ForegroundColor DarkCyan
        Write-Host "     • ai-fix   (якщо попередня команда викликала помилку)" -ForegroundColor DarkCyan
        Write-Host "     • ai-script `"архівація та логування`"" -ForegroundColor DarkCyan
        Write-Host "     • Напишіть у рядку '# створити zip архів' і натисніть Ctrl+Alt+A" -ForegroundColor DarkCyan
        if ($orderedProducts -contains "WindowsTerminal") {
            Write-Host "  3. У Windows Terminal натисніть Ctrl+Shift+P і шукайте 'AI:'`n" -ForegroundColor White
        } else {
            Write-Host "" -ForegroundColor White
        }
    } else {
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "             Installation completed successfully!              " -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "How to get started right now:" -ForegroundColor Yellow
        Write-Host "  1. Reload session or run:  . `$PROFILE" -ForegroundColor White
        Write-Host "  2. Try in terminal:" -ForegroundColor White
        Write-Host "     • ai find all large files in current directory" -ForegroundColor DarkCyan
        Write-Host "     • ai-fix   (if previous command threw an error)" -ForegroundColor DarkCyan
        Write-Host "     • ai-script `"backup and logging`"" -ForegroundColor DarkCyan
        Write-Host "     • Type '# create zip archive' and press Ctrl+Alt+A" -ForegroundColor DarkCyan
        if ($orderedProducts -contains "WindowsTerminal") {
            Write-Host "  3. In Windows Terminal press Ctrl+Shift+P and search for 'AI:'`n" -ForegroundColor White
        } else {
            Write-Host "" -ForegroundColor White
        }
    }
} else {
    $msgDone = if ($isUk) { "✔ Продукт(и) встановлено: $($orderedProducts -join ', ')`n" } else { "✔ Installed product(s): $($orderedProducts -join ', ')`n" }
    Write-Host $msgDone -ForegroundColor Green
}
