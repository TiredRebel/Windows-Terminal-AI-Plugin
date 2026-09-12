$repoRoot = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -Path $repoRoot -Recurse -Include *.ps1, *.psm1, *.psd1 | Where-Object { $_.FullName -notmatch '\\\.git\\' }
$bom = [byte[]](0xEF, 0xBB, 0xBF)
$fixed = 0
$total = 0

foreach ($f in $files) {
    $total++
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if (-not $hasBom) {
        $content = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($f.FullName, $content, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "Added UTF-8 BOM: $($f.FullName)" -ForegroundColor Yellow
        $fixed++
    }
}

Write-Host "UTF-8 BOM check complete. Checked: $total, Fixed: $fixed." -ForegroundColor Green
