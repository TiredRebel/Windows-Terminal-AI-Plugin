# Uninstall-TerminalAi.ps1 - Uninstaller for TerminalAI extension
# Multi-user uninstaller supporting -Scope CurrentUser (default) and -Scope AllUsers

[CmdletBinding()]
param(
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",

    [ValidateSet("en", "uk")]
    [string]$Language = "en",

    [switch]$PurgeConfig,
    [string]$CustomProfilePath,
    [string]$CustomModulePath,
    [string]$CustomFragmentPath
)

$ErrorActionPreference = "Continue"

if (-not $PSBoundParameters.ContainsKey('Language') -and $env:TERMINAL_AI_LANG -in @("uk", "ua")) {
    $Language = "uk"
}
$isUk = ($Language -eq "uk")

$msgStarting = "`nRemoving TerminalAI extension ($Scope)..."
Write-Host $msgStarting -ForegroundColor Yellow

if ($Scope -eq "AllUsers") {
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    if (-not $isAdmin) {
        $msgAdmin = "[TerminalAI] Uninstallation for all users (-Scope AllUsers) requires Administrator privileges (Run as Administrator)."
        Write-Error $msgAdmin
        return
    }
}

# 1. Module removal from PSModulePath
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
        $terminalAiFiles = @(
            "TerminalAI.psd1", "TerminalAI.psm1", "TerminalAiConfig.ps1",
            "TerminalAiAssistant.ps1", "TerminalAiAgent.ps1",
            "TerminalAI.Aot.dll", "TerminalAI.Aot.dll-Help.xml"
        )
        foreach ($file in $terminalAiFiles) {
            Remove-Item -LiteralPath (Join-Path $destModuleDir $file) -Force -ErrorAction SilentlyContinue
        }
        if (-not (Get-ChildItem -LiteralPath $destModuleDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $destModuleDir -Force -ErrorAction SilentlyContinue
        }
        $msgMod = "✔ TerminalAI module files removed: $destModuleDir"
        Write-Host $msgMod -ForegroundColor Green
    }
}

# 2. Excision of delimited initialization block from $PROFILE
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
            $msgBak = "✔ Profile backup created before uninstallation: $backupFile"
            Write-Host $msgBak -ForegroundColor DarkGray
        } catch { }

        $cleanContent = [regex]::Replace($profileContent, '(?ms)\r?\n?# >>> TerminalAI Initialization >>>.*?# <<< TerminalAI Initialization <<<\r?\n?', '')
        $cleanContent = [regex]::Replace($cleanContent, '(?ms)\r?\n?# TerminalAI[^\r\n]*\r?\n?Import-Module\s+TerminalAI[^\r\n]*\r?\n?', '')

        if ($cleanContent -ne $profileContent) {
            $enc = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($targetProfile, $cleanContent.TrimEnd() + "`n", $enc)
            $msgProfileClean = "✔ Removed TerminalAI initialization block from $targetProfile"
            Write-Host $msgProfileClean -ForegroundColor Green
        }
    }
}

# 3. Clean up Windows Terminal actions in settings.json (if present)
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
                $terminalAiActionNames = @(
                    "AI: Ask Ollama (ai)",
                    "AI: Fix last error (ai-fix)",
                    "AI: Generate script (ai-script)",
                    "AI: Open assistant in split pane"
                )
                $filteredActions = $wtJson.actions | Where-Object { $terminalAiActionNames -notcontains $_.name }
                $wtJson.actions = @($filteredActions)
                $newSettingsJson = $wtJson | ConvertTo-Json -Depth 10
                Set-Content -Path $wtSettingsFile -Value $newSettingsJson -Encoding UTF8
                $msgWt = "✔ Cleaned up AI actions from $wtSettingsFile"
                Write-Host $msgWt -ForegroundColor Green
            }
        } catch {
            $warnWt = "Error cleaning up ${wtSettingsFile}: $_"
            Write-Warning $warnWt
        }
    }
}

# 4. Clean up JSON Fragment Extension
$fragDir = if ($CustomFragmentPath) {
    $CustomFragmentPath
} elseif ($Scope -eq "AllUsers") {
    "$env:ProgramData\Microsoft\Windows Terminal\Fragments\TerminalAI"
} else {
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\TerminalAI"
}

if (Test-Path $fragDir) {
    $fragFile = Join-Path $fragDir "terminalai.json"
    $removedFragment = $false
    if (Test-Path $fragFile) {
        $fragmentContent = Get-Content -LiteralPath $fragFile -Raw -ErrorAction SilentlyContinue
        if ($fragmentContent -match '\{62068dd4-52e9-41f7-9feb-987581e2e117\}') {
            Remove-Item -LiteralPath $fragFile -Force -ErrorAction SilentlyContinue
            $removedFragment = $true
        } else {
            Write-Warning "Preserved unrecognized file at $fragFile; it was not verified as TerminalAI-owned."
        }
    }
    if ($removedFragment -and -not (Get-ChildItem -LiteralPath $fragDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $fragDir -Force -ErrorAction SilentlyContinue
    }
    if ($removedFragment) {
        $msgFrag = "✔ Removed TerminalAI Fragment Extension from $fragDir"
        Write-Host $msgFrag -ForegroundColor Green
    }
}

# 5. Clean up or retain configuration directory
$cfgDir = if ($env:TERMINAL_AI_CONFIG_DIR) { $env:TERMINAL_AI_CONFIG_DIR } else { Join-Path $HOME ".terminal-ai" }
if ($PurgeConfig) {
    $configFile = Join-Path $cfgDir "config.json"
    if (Test-Path $configFile) {
        Remove-Item -LiteralPath $configFile -Force -ErrorAction SilentlyContinue
        $msgCfgDel = "✔ Removed TerminalAI configuration file: $configFile"
        Write-Host $msgCfgDel -ForegroundColor Green
    }
    if ((Test-Path $cfgDir) -and -not (Get-ChildItem -LiteralPath $cfgDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $cfgDir -Force -ErrorAction SilentlyContinue
    }
} else {
    if (Test-Path $cfgDir) {
        $msgCfgPreserved = "ℹ Configuration preserved at $cfgDir (use -PurgeConfig to remove TerminalAI's config.json)."
        Write-Host $msgCfgPreserved -ForegroundColor DarkCyan
    }
}

Write-Host "ℹ Ollama and all Ollama models were preserved because they are shared external dependencies." -ForegroundColor DarkCyan

$msgDone = "Uninstallation complete.`n"
Write-Host $msgDone -ForegroundColor Green
