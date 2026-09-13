# TerminalAiConfig.ps1 - TerminalAI configuration, language, and font management

function Get-TerminalAiConfigPath {
    $configDir = if ($env:TERMINAL_AI_CONFIG_DIR) {
        $env:TERMINAL_AI_CONFIG_DIR
    } else {
        Join-Path $HOME ".terminal-ai"
    }
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    return Join-Path $configDir "config.json"
}

function Get-TerminalAiDefaultConfig {
    return [ordered]@{
        OllamaUrl          = "http://localhost:11434"
        Model              = "qwen2.5-coder:7b"
        Language           = "en" # 'en' for English or 'uk' for Ukrainian
        Font               = "Cascadia Code"
        Temperature        = 0.2
        TimeoutSeconds     = 120
        HotkeyChord        = "Ctrl+Alt+A"
        AutoCopy           = $false
        ShowExplanation    = $true
        UseAliases         = $false
        AgentModel         = "qwen2.5-coder:7b"
        ClaudeExecutable   = ""
        AgentDataDirectory = ""
    }
}


function Get-TerminalAiConfig {
    [CmdletBinding()]
    param()

    $configPath = Get-TerminalAiConfigPath
    $defaultConfig = Get-TerminalAiDefaultConfig

    if (Test-Path $configPath) {
        try {
            $json = Get-Content -Path $configPath -Raw -ErrorAction Stop | ConvertFrom-Json
            # Merge with defaults to support newly added fields
            foreach ($key in $defaultConfig.Keys) {
                if ($null -eq $json.$key) {
                    $json | Add-Member -MemberType NoteProperty -Name $key -Value $defaultConfig[$key]
                }
            }
            # System variable TERMINAL_AI_LANG takes precedence if set, otherwise config, otherwise 'en'
            if ($env:TERMINAL_AI_LANG -in @("uk", "en", "ua")) {
                $json.Language = if ($env:TERMINAL_AI_LANG -in @("ua", "uk")) { "uk" } else { "en" }
            } elseif ($json.Language -notin @("uk", "ua")) {
                $json.Language = "en"
            }
            return $json
        }
        catch {
            Write-Warning "Failed to read configuration ($configPath). Using default settings."
            $fallback = [PSCustomObject]$defaultConfig
            $fallback.Language = if ($env:TERMINAL_AI_LANG -in @("ua", "uk")) { "uk" } else { "en" }
            return $fallback
        }
    }
    else {
        $cfgObj = [PSCustomObject]$defaultConfig
        $cfgObj.Language = if ($env:TERMINAL_AI_LANG -in @("ua", "uk")) { "uk" } else { "en" }
        Save-TerminalAiConfig -Config $cfgObj
        return $cfgObj
    }
}

function Save-TerminalAiConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    $configPath = Get-TerminalAiConfigPath
    $json = $Config | ConvertTo-Json -Depth 5
    Set-Content -Path $configPath -Value $json -Encoding UTF8
}

function Set-TerminalAiConfig {
    [CmdletBinding()]
    param(
        [string]$Model,
        [string]$OllamaUrl,
        [ValidateSet("uk", "en", "ua")]
        [string]$Language,
        [string]$Font,
        [double]$Temperature,
        [int]$TimeoutSeconds,
        [string]$HotkeyChord,
        [bool]$AutoCopy,
        [bool]$ShowExplanation,
        [bool]$UseAliases,
        [string]$AgentModel,
        [string]$ClaudeExecutable,
        [string]$AgentDataDirectory
    )

    $cfg = Get-TerminalAiConfig

    if ($PSBoundParameters.ContainsKey('Model')) { $cfg.Model = $Model }
    if ($PSBoundParameters.ContainsKey('OllamaUrl')) { $cfg.OllamaUrl = $OllamaUrl }
    if ($PSBoundParameters.ContainsKey('Language')) {
        $normLang = if ($Language -in @("ua", "uk")) { "uk" } else { "en" }
        $cfg.Language = $normLang
    }
    if ($PSBoundParameters.ContainsKey('Font')) { $cfg.Font = $Font }
    if ($PSBoundParameters.ContainsKey('Temperature')) { $cfg.Temperature = $Temperature }
    if ($PSBoundParameters.ContainsKey('TimeoutSeconds')) { $cfg.TimeoutSeconds = $TimeoutSeconds }
    if ($PSBoundParameters.ContainsKey('HotkeyChord')) { $cfg.HotkeyChord = $HotkeyChord }
    if ($PSBoundParameters.ContainsKey('AutoCopy')) { $cfg.AutoCopy = $AutoCopy }
    if ($PSBoundParameters.ContainsKey('ShowExplanation')) { $cfg.ShowExplanation = $ShowExplanation }
    if ($PSBoundParameters.ContainsKey('UseAliases')) { $cfg.UseAliases = $UseAliases }
    if ($PSBoundParameters.ContainsKey('AgentModel')) { $cfg.AgentModel = $AgentModel }
    if ($PSBoundParameters.ContainsKey('ClaudeExecutable')) { $cfg.ClaudeExecutable = $ClaudeExecutable }
    if ($PSBoundParameters.ContainsKey('AgentDataDirectory')) { $cfg.AgentDataDirectory = $AgentDataDirectory }

    Save-TerminalAiConfig -Config $cfg
    $msg = if ($cfg.Language -in @("uk", "ua")) {
        "✔ [TerminalAI] Configuration saved to $(Get-TerminalAiConfigPath)"
    } else {
        "✔ [TerminalAI] Configuration successfully saved to $(Get-TerminalAiConfigPath)"
    }
    Write-Host $msg -ForegroundColor Green
    return $cfg
}

function Get-WindowsTerminalSettingsPath {
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) { return $cand }
    }
    return $null
}

function Get-TerminalAiFonts {
    [CmdletBinding()]
    param()

    $activeFont = "Cascadia Code"
    $wtPath = Get-WindowsTerminalSettingsPath
    if ($wtPath) {
        try {
            $wtJson = Get-Content -Path $wtPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($wtJson.profiles.defaults.font.face) {
                $activeFont = $wtJson.profiles.defaults.font.face
            }
        } catch { }
    }

    $fonts = @()
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $installed = [System.Drawing.FontFamily]::Families | Where-Object {
            $_.Name -match 'Mono|Code|Consolas|Courier|Nerd|Lucida Console|Fira|Hack' -and
            $_.Name -notmatch 'Extra|Light|Thin|Semi|Bold|Medium|Corsiva|Lucida Bright|Lucida Calligraphy|Lucida Fax|Lucida Handwriting|Lucida Sans'
        } | Select-Object -ExpandProperty Name | Sort-Object -Unique

        $hasActive = $false
        foreach ($f in $installed) {
            $isActive = ($f -eq $activeFont -or ($f.Replace(" ", "").ToLower() -eq $activeFont.Replace(" ", "").ToLower()))
            if ($isActive) { $hasActive = $true }
            $fonts += [PSCustomObject]@{
                Name     = $f
                IsActive = $isActive
            }
        }

        if (-not $hasActive -and -not [string]::IsNullOrWhiteSpace($activeFont)) {
            $fonts = @([PSCustomObject]@{ Name = $activeFont; IsActive = $true }) + $fonts
        }
    } catch { }

    if ($fonts.Count -eq 0) {
        $defaults = @("Cascadia Code", "Cascadia Mono", "Consolas", "Courier New", "Lucida Console")
        foreach ($d in $defaults) {
            $fonts += [PSCustomObject]@{
                Name     = $d
                IsActive = ($d -eq $activeFont)
            }
        }
    }

    return [PSCustomObject]@{
        ActiveFont = $activeFont
        Fonts      = $fonts
        WtPath     = $wtPath
    }
}

function Show-TerminalAiFonts {
    [CmdletBinding()]
    param()

    $fontInfo = Get-TerminalAiFonts
    $cfg = Get-TerminalAiConfig
    $isUk = ($cfg.Language -in @("uk", "ua"))

    $title = "Installed Monospace Terminal Fonts"
    $activeLabel = "Active"
    $curLabel = "Current"
    $changeHint = "Change font:"
    $orHint = "Or with font size:"

    Write-Host ""
    Write-Host "    ✦ Terminal AI • $title ($($curLabel): $($fontInfo.ActiveFont))" -ForegroundColor Cyan
    Write-Host "    ╭──────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
    Write-Host "    │                                                                  │" -ForegroundColor DarkCyan

    foreach ($f in $fontInfo.Fonts) {
        $prefix = if ($f.IsActive) { "--> * " } else { "      " }
        $color = if ($f.IsActive) { [System.ConsoleColor]::Green } else { [System.ConsoleColor]::White }
        $tag = if ($f.IsActive) { " ($activeLabel)" } else { "" }
        $display = "$prefix$($f.Name)$tag"
        if ($display.Length -gt 64) { $display = $display.Substring(0, 61) + "..." }

        Write-Host "    │ " -NoNewline -ForegroundColor DarkCyan
        Write-Host ("{0,-64}" -f $display) -NoNewline -ForegroundColor $color
        Write-Host " │" -ForegroundColor DarkCyan
    }

    Write-Host "    │                                                                  │" -ForegroundColor DarkCyan
    Write-Host "    ╰──────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "    💡 $changeHint  ai font `"$($fontInfo.ActiveFont)`"" -ForegroundColor DarkGray
    Write-Host "    💡 $orHint  Set-TerminalAiFont -Font `"$($fontInfo.ActiveFont)`" -Size 13`n" -ForegroundColor DarkGray
}

function Set-TerminalAiFont {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Font,

        [int]$Size
    )

    $cfg = Get-TerminalAiConfig
    $isUk = ($cfg.Language -in @("uk", "ua"))

    $wtPath = Get-WindowsTerminalSettingsPath
    if (-not $wtPath) {
        $msgNotFound = "Windows Terminal settings file (settings.json) not found."
        Write-Error " [TerminalAI] $msgNotFound"
        return
    }

    try {
        $wtJson = Get-Content -Path $wtPath -Raw -ErrorAction Stop | ConvertFrom-Json

        if ($null -eq $wtJson.profiles) {
            $wtJson | Add-Member -MemberType NoteProperty -Name "profiles" -Value ([ordered]@{})
        }
        if ($null -eq $wtJson.profiles.defaults) {
            $wtJson.profiles | Add-Member -MemberType NoteProperty -Name "defaults" -Value ([ordered]@{})
        }
        if ($null -eq $wtJson.profiles.defaults.font) {
            $wtJson.profiles.defaults | Add-Member -MemberType NoteProperty -Name "font" -Value ([ordered]@{})
        }

        $wtJson.profiles.defaults.font.face = $Font
        if ($Size -gt 0) {
            $wtJson.profiles.defaults.font.size = $Size
        }

        $newJson = $wtJson | ConvertTo-Json -Depth 20
        Set-Content -Path $wtPath -Value $newJson -Encoding UTF8

        # Save to the TerminalAI configuration
        Set-TerminalAiConfig -Font $Font | Out-Null

        $cfg = Get-TerminalAiConfig
        $isUk = ($cfg.Language -in @("uk", "ua"))
        $msg = if ($isUk) {
            "✔ [TerminalAI] Terminal font changed to '$Font'."
        } else {
            "✔ [TerminalAI] Terminal font successfully changed to '$Font'!"
        }
        Write-Host "`n    $msg" -ForegroundColor Green
        if ($Size -gt 0) {
            $lblSize = "Font size:"
            Write-Host "    $lblSize $Size pt`n" -ForegroundColor DarkCyan
        } else {
            Write-Host ""
        }
    }
    catch {
        $msgErr = if ($isUk) {
            " [TerminalAI] Failed to update the font in $($wtPath): $($_.Exception.Message)"
        } else {
            " [TerminalAI] Failed to update font in $($wtPath): $($_.Exception.Message)"
        }
        Write-Error $msgErr
    }
}

function Set-TerminalAiLanguage {
    <#
    .SYNOPSIS
        Sets and saves the requested language for model-generated prose responses.
    .PARAMETER Language
        Language code: uk or ua for Ukrainian, en for English.
    .PARAMETER Permanent
        Persists the language in config.json and the Windows user environment.
    .EXAMPLE
        ai-lang uk
    .EXAMPLE
        ai-lang uk -Permanent
    .EXAMPLE
        Set-TerminalAiDefaultLanguage uk
    #>
    [CmdletBinding()]
    [Alias("ai-lang")]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateSet("uk", "en", "ua")]
        [string]$Language,

        [Alias("Persist", "Save", "Default")]
        [switch]$Permanent
    )

    $normalizedLang = if ($Language -in @("ua", "uk")) { "uk" } else { "en" }

    # Save to ~/.terminal-ai/config.json
    Set-TerminalAiConfig -Language $normalizedLang | Out-Null

    # Persist in the Windows user environment and current session
    if ($Permanent -and -not $env:TERMINAL_AI_CONFIG_DIR) {
        try {
            [Environment]::SetEnvironmentVariable("TERMINAL_AI_LANG", $normalizedLang, "User")
        } catch { }
    }
    $env:TERMINAL_AI_LANG = $normalizedLang

    # Update the Windows Terminal fragment
    if (-not $env:TERMINAL_AI_CONFIG_DIR) {
        try {
            Update-TerminalAiFragment -Language $normalizedLang
        } catch { }
    }

    $cfgPath = Get-TerminalAiConfigPath
    if ($normalizedLang -eq "uk") {
        Write-Host ""
        if ($Permanent) {
            Write-Host "    ✔ Model response language set permanently to uk (Ukrainian)." -ForegroundColor Green
            Write-Host "      • Saved in configuration: $cfgPath" -ForegroundColor DarkCyan
            Write-Host "      • Saved in the Windows user environment: `$env:TERMINAL_AI_LANG = 'uk'" -ForegroundColor DarkCyan
            Write-Host "      • The setting persists across reboots and terminal sessions.`n" -ForegroundColor DarkGray
        } else {
            Write-Host "    ✔ Model response language changed to Ukrainian." -ForegroundColor Green
            Write-Host "      • Saved in configuration: $cfgPath" -ForegroundColor DarkGray
            Write-Host "      💡 To persist at the system level: ai lang permanent uk`n" -ForegroundColor DarkGray
        }
    } else {
        Write-Host ""
        if ($Permanent) {
            Write-Host "    ✔ Model response language set permanently to en (English)." -ForegroundColor Green
            Write-Host "      • Saved to configuration: $cfgPath" -ForegroundColor DarkCyan
            Write-Host "      • Persisted in Windows user environment: `$env:TERMINAL_AI_LANG = 'en'" -ForegroundColor DarkCyan
            Write-Host "      • Language will persist across reboots and all terminal sessions.`n" -ForegroundColor DarkGray
        } else {
            Write-Host "    ✔ Model response language changed to English." -ForegroundColor Green
            Write-Host "      • Saved to configuration: $cfgPath" -ForegroundColor DarkGray
            Write-Host "      💡 To lock permanently at system level: ai lang permanent en`n" -ForegroundColor DarkGray
        }
    }
}

function Update-TerminalAiFragment {
    [CmdletBinding()]
    param([string]$Language)

    $isEn = ($Language -ne "uk" -and $Language -ne "ua")
    $assistantCommand = "pwsh.exe -NoExit -Command `"Import-Module TerminalAI -ErrorAction SilentlyContinue; Invoke-AiAssistant`""

    $actionAsk = "AI: Ask Ollama (ai)"
    $actionFix = "AI: Fix last error (ai-fix)"
    $actionScript = "AI: Generate script (ai-script)"
    $actionSplit = "AI: Open assistant in split pane"

    $fragmentObj = [ordered]@{
        profiles = @(
            [ordered]@{
                name = "Terminal AI Assistant"
                guid = "{62068dd4-52e9-41f7-9feb-987581e2e117}"
                commandline = $assistantCommand
                icon = "🤖"
                tabTitle = "AI Assistant (Ollama)"
                startingDirectory = "%USERPROFILE%"
            },
            [ordered]@{
                name = "PowerShell with TerminalAI"
                guid = "{7a3b4c5d-6e7f-8a9b-0c1d-2e3f4a5b6c7d}"
                commandline = "pwsh.exe -NoExit -Command `"Import-Module TerminalAI; Clear-Host; Show-TerminalAiWelcome`""
                icon = "⚡"
                tabTitle = "PowerShell (AI)"
                startingDirectory = "%USERPROFILE%"
            }
        )
        actions = @(
            [ordered]@{
                name = $actionAsk
                command = [ordered]@{
                    action = "sendInput"
                    input = "ai `""
                }
            },
            [ordered]@{
                name = $actionFix
                command = [ordered]@{
                    action = "sendInput"
                    input = "ai-fix`r"
                }
            },
            [ordered]@{
                name = $actionScript
                command = [ordered]@{
                    action = "sendInput"
                    input = "ai-script `""
                }
            },
            [ordered]@{
                name = $actionSplit
                command = [ordered]@{
                    action = "splitPane"
                    split = "vertical"
                    size = 0.4
                    commandline = $assistantCommand
                }
            }
        )
    }

    $fragJson = $fragmentObj | ConvertTo-Json -Depth 10

    # Windows Terminal fragments directory
    $destFrag = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\TerminalAI\terminalai.json"
    $destFragDir = Split-Path $destFrag
    if (-not (Test-Path $destFragDir)) {
        New-Item -ItemType Directory -Path $destFragDir -Force | Out-Null
    }
    Set-Content -Path $destFrag -Value $fragJson -Encoding UTF8

    # Project directory when known
    $projectDir = $PSScriptRoot
    if ($projectDir -and (Test-Path (Join-Path $projectDir "terminalai.json"))) {
        Set-Content -Path (Join-Path $projectDir "terminalai.json") -Value $fragJson -Encoding UTF8
    }
}

function Set-TerminalAiDefaultLanguage {
    <#
    .SYNOPSIS
        Persists the default model response language in configuration and the system environment.
    .EXAMPLE
        ai-lang-permanent uk
    .EXAMPLE
        Set-TerminalAiDefaultLanguage uk
    #>
    [CmdletBinding()]
    [Alias("ai-lang-permanent", "ai-lang-default")]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateSet("uk", "en", "ua")]
        [string]$Language
    )

    Set-TerminalAiLanguage -Language $Language -Permanent
}
