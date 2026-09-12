# Parse all PowerShell files in repo and report errors
$repoRoot = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -Path $repoRoot -Recurse -Include *.ps1, *.psm1, *.psd1 | Where-Object { $_.FullName -notmatch '\\\.git\\' }
$hasError = $false

foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        Write-Host "FAIL: $($f.Name) - $($errors[0].Message)" -ForegroundColor Red
        $hasError = $true
    } else {
        Write-Host "OK: $($f.Name)" -ForegroundColor Green
    }
}

if ($hasError) {
    exit 1
} else {
    Write-Host "`nAll files parsed successfully with 0 errors." -ForegroundColor Green
    exit 0
}
