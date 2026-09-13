# Install-WindowsTerminal.ps1 - Registers the Windows Terminal Fragment Extension
# (profiles, command-palette actions, split-pane launcher) and, optionally,
# patches the legacy per-user settings.json actions list. Requires Windows
# Terminal 1.18+. Safe to run without the Core product installed, though the
# generated split-pane / legacy actions assume TerminalAI is registered at the
# resolved module path.
#
# Can be run standalone:
#   pwsh -ExecutionPolicy Bypass -File .\installers\Install-WindowsTerminal.ps1
# or invoked from the orchestrator, ..\Install-TerminalAi.ps1.

[CmdletBinding()]
param(
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",

    [ValidateSet("en", "uk")]
    [string]$Language = "en",

    [switch]$ModifySettingsJson,
    [string]$CustomFragmentPath,
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

$step = "▶ Configuring Windows Terminal (Fragments & Actions)..."
Write-Host $step -ForegroundColor Yellow

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
        $msgFragReg = "   ✔ Registered Windows Terminal Fragment Extension ($Scope): $fragDir"
        Write-Host $msgFragReg -ForegroundColor Green
    }
} catch {
    $warnFrag = "   Failed to create Fragment Extension: $($_.Exception.Message)"
    Write-Warning $warnFrag
}

if ($ModifySettingsJson) {
    $msgLegacyWt = "   • Updating actions in settings.json (legacy mode)..."
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
            $msgBakWt = "   ✔ Created backup: $backupFile"
            Write-Host $msgBakWt -ForegroundColor DarkGray

            $wtJson = Get-Content -Path $wtSettingsFile -Raw | ConvertFrom-Json

            if ($null -eq $wtJson.actions) {
                $wtJson | Add-Member -MemberType NoteProperty -Name "actions" -Value @()
            }

            # Matches the module destination the Core installer would use last
            # (the Windows PowerShell 5.1 location), so the launcher path below
            # keeps pointing at a real TerminalAiAssistant.ps1 copy either way.
            $moduleDestinations = Get-TerminalAiModuleDestinations -Scope $Scope -CustomModulePath $CustomModulePath
            $destModuleDir = $moduleDestinations | Select-Object -Last 1
            $assistantScriptPath = if ($destModuleDir) { Join-Path $destModuleDir "TerminalAiAssistant.ps1" } else { Join-Path $projectDir "TerminalAiAssistant.ps1" }

            $actionAskName = "AI: Ask Ollama (ai)"
            $actionFixName = "AI: Fix last error (ai-fix)"
            $actionScriptName = "AI: Generate script (ai-script)"
            $actionSplitName = "AI: Open assistant in split pane"

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
            $msgAddedActions = "   ✔ Added Windows Terminal actions: $addedCount (file: $wtSettingsFile)"
            Write-Host $msgAddedActions -ForegroundColor Green
        }
        catch {
            $warnModWt = "   Failed to modify Windows Terminal settings: $($_.Exception.Message)"
            Write-Warning $warnModWt
        }
    }
} else {
    $msgFragClean = "   ℹ Windows Terminal Fragment Extension active (non-invasive mode, settings.json left untouched)."
    Write-Host $msgFragClean -ForegroundColor DarkCyan
}
