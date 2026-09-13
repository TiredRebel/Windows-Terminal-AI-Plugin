# Install-Aot.ps1 - Deploys the compiled C# accelerator module (aif / ai-fast).
# Requires PowerShell 7+ on a compatible .NET 10 runtime; automatically skipped
# (and cleaned up) on Windows PowerShell 5.1 module paths, since that host runs
# on .NET Framework 4.8 and cannot load a .NET 10 binary. Requires the Core
# product to already be registered, so TerminalAI.psm1 can load this as a
# nested binary module.
#
# Can be run standalone:
#   pwsh -ExecutionPolicy Bypass -File .\installers\Install-Aot.ps1
# or invoked from the orchestrator, ..\Install-TerminalAi.ps1.

[CmdletBinding()]
param(
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",

    [ValidateSet("en", "uk")]
    [string]$Language = "en",

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

$step = if ($isUk) { "▶ Розгортання скомпільованого C#-модуля (aif)..." } else { "▶ Deploying compiled C# accelerator module (aif)..." }
Write-Host $step -ForegroundColor Yellow

$moduleDestinations = Get-TerminalAiModuleDestinations -Scope $Scope -CustomModulePath $CustomModulePath

foreach ($destModuleDir in $moduleDestinations) {
    # Only deploy the AOT binary to PowerShell 7+ locations (WindowsPowerShell 5.1
    # runs on .NET Framework 4.8 and cannot load a .NET 10 assembly).
    $isWindowsPowerShellPath = $destModuleDir -like "*WindowsPowerShell*"
    if ($isWindowsPowerShellPath) {
        $staleAot = Join-Path $destModuleDir "TerminalAI.Aot.dll"
        if (Test-Path $staleAot) {
            Remove-Item -Path $staleAot -Force -ErrorAction Ignore
        }
        $staleHelp = Join-Path $destModuleDir "TerminalAI.Aot.dll-Help.xml"
        if (Test-Path $staleHelp) {
            Remove-Item -Path $staleHelp -Force -ErrorAction Ignore
        }
        $msgSkip = if ($isUk) { "   ℹ Пропущено для Windows PowerShell 5.1 (потрібен PowerShell 7+ з .NET 10): $destModuleDir" } else { "   ℹ Skipped for Windows PowerShell 5.1 (PowerShell 7+ with .NET 10 required): $destModuleDir" }
        Write-Host $msgSkip -ForegroundColor DarkGray
        continue
    }

    if (-not (Test-Path $destModuleDir)) {
        New-Item -ItemType Directory -Path $destModuleDir -Force | Out-Null
    }

    $aotDllPath = Join-Path $projectDir "TerminalAI.Aot.dll"
    if (-not (Test-Path $aotDllPath)) {
        $aotDllPath = Join-Path $projectDir "AOT\bin\Release\net10.0\TerminalAI.Aot.dll"
    }

    if (-not (Test-Path $aotDllPath)) {
        $msgMissing = if ($isUk) { "   ⚠ TerminalAI.Aot.dll не знайдено в $projectDir; спершу зберіть або додайте бінарник (див. AOT/README.md)." } else { "   ⚠ TerminalAI.Aot.dll was not found in $projectDir; build or place the binary first (see AOT/README.md)." }
        Write-Host $msgMissing -ForegroundColor DarkYellow
        continue
    }

    $destAot = Join-Path $destModuleDir (Split-Path -Leaf $aotDllPath)
    $needsCopy = $true
    if (Test-Path $destAot) {
        try {
            $srcItem = Get-Item $aotDllPath -ErrorAction Ignore
            $dstItem = Get-Item $destAot -ErrorAction Ignore
            if ($srcItem -and $dstItem -and $srcItem.Length -eq $dstItem.Length -and $srcItem.LastWriteTimeUtc -eq $dstItem.LastWriteTimeUtc) {
                $needsCopy = $false
            }
        } catch { }
    }
    if ($needsCopy) {
        $errCountBefore = $global:Error.Count
        try {
            [System.IO.File]::Copy($aotDllPath, $destAot, $true)
        } catch [System.IO.IOException] {
            while ($global:Error.Count -gt $errCountBefore) {
                $global:Error.RemoveAt(0)
            }
            $msgLocked = if ($isUk) {
                "   ℹ TerminalAI.Aot.dll використовується активним процесом; збережено поточну збірку."
            } else {
                "   ℹ TerminalAI.Aot.dll is in use by an active session; retained existing binary."
            }
            Write-Host $msgLocked -ForegroundColor DarkGray
        } catch {
            while ($global:Error.Count -gt $errCountBefore) {
                $global:Error.RemoveAt(0)
            }
        }
    }

    $aotHelpPath = Join-Path $projectDir "TerminalAI.Aot.dll-Help.xml"
    if (-not (Test-Path $aotHelpPath)) {
        $aotHelpPath = Join-Path $projectDir "AOT\TerminalAI.Aot.dll-Help.xml"
    }
    if (Test-Path $aotHelpPath) {
        $destHelp = Join-Path $destModuleDir (Split-Path -Leaf $aotHelpPath)
        $errCountBefore = $global:Error.Count
        try {
            [System.IO.File]::Copy($aotHelpPath, $destHelp, $true)
        } catch {
            while ($global:Error.Count -gt $errCountBefore) {
                $global:Error.RemoveAt(0)
            }
        }
    }

    $msgDone = if ($isUk) { "   ✔ C#-модуль розгорнуто у: $destModuleDir" } else { "   ✔ C# module deployed to: $destModuleDir" }
    Write-Host $msgDone -ForegroundColor Green
}
