# InstallerCommon.ps1 - Shared helpers for the TerminalAI product installers.
# Dot-sourced by every Install-*.ps1 script in this folder (and by the
# top-level orchestrator, .\Install-TerminalAi.ps1). Not meant to be run directly.

function Test-TerminalAiIsAdmin {
    [CmdletBinding()]
    param()
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Assert-TerminalAiScopeAdmin {
    # Returns $true when it is safe to proceed, $false (after printing a
    # localized error) when -Scope AllUsers was requested without admin rights.
    [CmdletBinding()]
    param(
        [ValidateSet("CurrentUser", "AllUsers")]
        [string]$Scope = "CurrentUser",

        [bool]$IsUkrainian = $false
    )

    if ($Scope -ne "AllUsers") { return $true }
    if (Test-TerminalAiIsAdmin) { return $true }

    $msgAdmin = if ($IsUkrainian) {
        "[TerminalAI] Installation for all users (-Scope AllUsers) requires Administrator privileges (Run as Administrator)."
    } else {
        "[TerminalAI] Installation for all users (-Scope AllUsers) requires Administrator privileges (Run as Administrator)."
    }
    Write-Error $msgAdmin
    return $false
}

function Get-TerminalAiModuleDestinations {
    # Resolves the candidate PSModulePath-style destination folder(s) for the
    # TerminalAI module, without creating anything on disk. The last entry is
    # always the Windows PowerShell 5.1 location when more than one applies.
    [CmdletBinding()]
    param(
        [ValidateSet("CurrentUser", "AllUsers")]
        [string]$Scope = "CurrentUser",

        [string]$CustomModulePath
    )

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

    return @($candidateRoots | ForEach-Object { Join-Path $_ "TerminalAI" })
}

function Show-SpinnerWait {
    param(
        [string]$Message,
        [scriptblock]$Condition,
        [int]$TimeoutSec = 20,
        [bool]$IsUkrainian = $false
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $chars = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
    $i = 0
    $doneLabel = "ready!"
    $timeoutLabel = "Wait timeout elapsed."
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if (& $Condition) {
            Write-Host "`r   ✔ $Message - $doneLabel ($([Math]::Round($sw.Elapsed.TotalSeconds, 1))s)          " -ForegroundColor Green
            return $true
        }
        $c = $chars[$i % $chars.Count]
        $i++
        $elapsed = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        Write-Host -NoNewline "`r   $c $Message (${elapsed}s / ${TimeoutSec}s)... "
        Start-Sleep -Milliseconds 250
    }
    Write-Host "`n   ⚠ $timeoutLabel" -ForegroundColor DarkYellow
    return $false
}
