# Install-Core.ps1 - Installs the TerminalAI PowerShell module (required product).
# Registers TerminalAI.psm1 and its script files in a PSModulePath location and
# wires up a marked auto-import block in $PROFILE. This is the only product the
# other three (Ollama, Aot, WindowsTerminal) assume is already installed.
#
# Can be run standalone:
#   pwsh -ExecutionPolicy Bypass -File .\installers\Install-Core.ps1
# or invoked from the orchestrator, ..\Install-TerminalAi.ps1.

[CmdletBinding()]
param(
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",

    [ValidateSet("en", "uk")]
    [string]$Language = "en",

    [string]$CustomProfilePath,
    [string]$CustomModulePath
)

$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey('Language') -and $env:TERMINAL_AI_LANG -in @("uk", "ua")) {
    $Language = "uk"
}
$isUk = ($Language -eq "uk")

. (Join-Path $PSScriptRoot "InstallerCommon.ps1")

if (-not (Assert-TerminalAiScopeAdmin -Scope $Scope -IsUkrainian $isUk)) { return }

$projectDir = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Get-Location }

$manifestPath = Join-Path $projectDir "TerminalAI.psd1"
if (-not (Test-Path $manifestPath)) {
    $msgNoPsd = if ($isUk) { "Не знайдено TerminalAI.psd1 у $projectDir" } else { "TerminalAI.psd1 not found in $projectDir" }
    Write-Error $msgNoPsd
    return
}

$step = if ($isUk) { "▶ Реєстрація модуля PowerShell ($Scope)..." } else { "▶ Registering PowerShell module ($Scope)..." }
Write-Host $step -ForegroundColor Yellow

$moduleDestinations = Get-TerminalAiModuleDestinations -Scope $Scope -CustomModulePath $CustomModulePath

foreach ($destModuleDir in $moduleDestinations) {
    if (-not (Test-Path $destModuleDir)) {
        New-Item -ItemType Directory -Path $destModuleDir -Force | Out-Null
    }

    $coreFiles = @("TerminalAI.psd1", "TerminalAI.psm1", "TerminalAiConfig.ps1", "TerminalAiAssistant.ps1", "TerminalAiAgent.ps1")
    foreach ($file in $coreFiles) {
        $srcPath = Join-Path $projectDir $file
        if (Test-Path $srcPath) {
            Copy-Item -Path $srcPath -Destination $destModuleDir -Force -ErrorAction Ignore
        }
    }

    $msgSynced = if ($isUk) { "   ✔ Модуль успішно синхронізовано з: $destModuleDir" } else { "   ✔ Module successfully synchronized to: $destModuleDir" }
    Write-Host $msgSynced -ForegroundColor Green
}

# Add or update the delimited initialization block in $PROFILE
$targetProfile = if ($CustomProfilePath) {
    $CustomProfilePath
} elseif ($Scope -eq "AllUsers") {
    if ($PROFILE.AllUsersAllHosts) { $PROFILE.AllUsersAllHosts } else { $PROFILE.AllUsersCurrentHost }
} else {
    if ($PROFILE.CurrentUserCurrentHost) { $PROFILE.CurrentUserCurrentHost } else { $PROFILE }
}

$stepProfile = if ($isUk) { "▶ Оновлення профілю PowerShell ($targetProfile)..." } else { "▶ Updating PowerShell profile ($targetProfile)..." }
Write-Host $stepProfile -ForegroundColor Yellow

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

# Make sure a configuration file exists and carries the selected language.
# Model / OllamaUrl are left untouched here; the Ollama product sets those.
$configScript = Join-Path $projectDir "TerminalAiConfig.ps1"
if (Test-Path $configScript) {
    . $configScript
    Set-TerminalAiConfig -Language $Language | Out-Null
}
