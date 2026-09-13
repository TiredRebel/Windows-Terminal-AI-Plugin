@echo off
setlocal enabledelayedexpansion
title TerminalAI - Portable AI Assistant

:: 1. Search for PowerShell 7+ (pwsh.exe)
set "PWSH_EXE="
where pwsh >nul 2>nul
if %ERRORLEVEL% equ 0 (
    set "PWSH_EXE=pwsh.exe"
) else if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PWSH_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
) else if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" (
    set "PWSH_EXE=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
) else (
    set "PWSH_EXE=powershell.exe"
)

:: 2. Launch bootstrap.ps1 in Portable mode
set "SCRIPT_DIR=%~dp0"
"%PWSH_EXE%" -NoExit -ExecutionPolicy Bypass -Command "& '%SCRIPT_DIR%bootstrap.ps1' -Mode Portable %*"
