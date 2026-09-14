[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Live,
    [int]$TimeoutSec = 10
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
}
$failures = [System.Collections.Generic.List[string]]::new()
$unknown = [System.Collections.Generic.List[string]]::new()

function Fail([string]$Message) { $failures.Add($Message) }
function HeadingSlug([string]$Text) {
    $slug = $Text.ToLowerInvariant() -replace '\[([^\]]+)\]\([^)]+\)', '$1' -replace '<[^>]+>', ''
    $slug = $slug -replace '[^\p{L}\p{N}\s-]', '' -replace '\s+', '-'
    return $slug.Trim('-')
}
function Resolve-MarkdownTarget([string]$From, [string]$Target) {
    $target = ($Target -split '[?#]', 2)[0]
    if ([string]::IsNullOrWhiteSpace($target)) { return $null }
    if ($target -match '^(?i)(https?|ftp|mailto):') { return $null }
    if ($target.StartsWith('#')) { return @{ Path = $From; Anchor = $target.Substring(1) } }
    $path = Join-Path (Split-Path -Parent $From) ($target -replace '/', '\')
    return @{ Path = [IO.Path]::GetFullPath($path); Anchor = (($Target -split '#', 2)[1]) }
}
function Check-MarkdownLinks([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw
    $seen = @{}
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$') {
            $base = HeadingSlug $Matches[1]; if (-not $seen.ContainsKey($base)) { $seen[$base] = 0 } else { $seen[$base]++ }
            $id = if ($seen[$base] -eq 0) { $base } else { "$base-$($seen[$base])" }
        }
    }
    $lineNo = 0
    foreach ($line in ($text -split "`r?`n")) {
        $lineNo++
        foreach ($m in [regex]::Matches($line, '(?<!!)!?\[[^\]]*\]\((?<target>[^)\s]+)(?:\s+"[^"]*")?\)')) {
            $target = $m.Groups['target'].Value
            $resolved = Resolve-MarkdownTarget $Path $target
            if ($null -eq $resolved) { continue }
            if (-not (Test-Path -LiteralPath $resolved.Path -PathType Leaf)) { Fail "$Path`:$lineNo missing Markdown target '$target'"; continue }
            if ($resolved.Anchor) {
                $anchorText = $resolved.Anchor.TrimStart('#').ToLowerInvariant()
                $targetText = Get-Content -LiteralPath $resolved.Path -Raw
                $ids = @{}
                $counts = @{}
                foreach ($h in ($targetText -split "`r?`n")) {
                    if ($h -match '^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$') {
                        $base = HeadingSlug $Matches[1]; if (-not $counts.ContainsKey($base)) { $counts[$base] = 0 } else { $counts[$base]++ }
                        $id = if ($counts[$base] -eq 0) { $base } else { "$base-$($counts[$base])" }; $ids[$id] = $true
                    }
                }
                if (-not $ids.ContainsKey($anchorText)) { Fail "$Path`:$lineNo missing Markdown anchor '$target'" }
            }
        }
    }
}

$pairs = @(
    @('README.md', 'README.uk.md'),
    @('AOT/README.md', 'AOT/README.uk.md')
)
foreach ($pair in $pairs) {
    $sequences = @()
    foreach ($rel in $pair) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $path)) { Fail "Missing README pair member '$rel'"; $sequences += ,@(); continue }
        $ids = [regex]::Matches((Get-Content -LiteralPath $path -Raw), '(?m)^\s*<!--\s*sync:([A-Za-z0-9._-]+)\s*-->\s*$') | ForEach-Object { $_.Groups[1].Value }
        if ($ids.Count -eq 0) { Fail "$rel has no sync markers" }
        $sequences += ,@($ids)
    }
    if ($sequences.Count -eq 2 -and (($sequences[0] -join "`n") -ne ($sequences[1] -join "`n"))) { Fail "Sync marker order differs: $($pair[0]) vs $($pair[1])" }
}

$markdownFiles = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notmatch '\\(?:\.git|dist|bin|obj)\\' }
foreach ($file in $markdownFiles) { Check-MarkdownLinks $file.FullName }

# Keep this list deliberately small: only claims prohibited by the documentation contract.
$prohibited = @('\bNative[ -]?AOT\b', '\bultra-fast\b', '\binstant(?:ly)?\b', '\bhigh-performance\b', '\bzero-allocation\b', '\beliminates script injection vectors\b', '\bavoiding command injection\b', '\bcommand injection\b', '\baccelerator module\b')
$tracked = @(& git -C $Root ls-files 2>$null)
$untracked = @(& git -C $Root ls-files --others --exclude-standard 2>$null)
foreach ($rel in @($tracked + $untracked | Select-Object -Unique)) {
    if ($rel -match '(?i)^(?:dist/|manifests/|docs/antigravity/|AOT/AOT_IMPLEMENTATION_LOG\.md$)') { continue }
    if ($rel -eq 'tools/Test-DocumentationQuality.ps1') { continue }
    $path = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or $rel -match '\.(?:dll|exe|zip|png|jpg|jpeg|gif|ico|pdf|pdb|7z)$') { continue }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $path)) {
        $lineNo++
        $scan = $line -replace '`[^`]*`', '' -replace 'https?://\S+', ''
        foreach ($pattern in $prohibited) {
            if ($scan -match $pattern) {
                $historical = $scan -match '(?i)AOT[/\\]|TerminalAI\.Aot|AotSecretSanitizer|historical|assembly name|directory name|project name|product identifier|alias'
                if (-not $historical) { Fail "$rel`:$lineNo prohibited terminology '$pattern'" }
            }
        }
    }
}

# Release references must agree across documentation; this remains offline and does not assert publication.
$releaseTags = [System.Collections.Generic.List[string]]::new(); $archiveTags = [System.Collections.Generic.List[string]]::new()
foreach ($file in $markdownFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($m in [regex]::Matches($text, 'releases/tag/(v?[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?)')) { $releaseTags.Add($m.Groups[1].Value.TrimStart('v')) }
    foreach ($m in [regex]::Matches($text, 'TerminalAI-v?([0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?)-win-x64\.zip')) { $archiveTags.Add($m.Groups[1].Value) }
}
if (($releaseTags | Select-Object -Unique).Count -gt 1) { Fail "Documented release tags are inconsistent: $($releaseTags -join ', ')" }
if (($archiveTags | Select-Object -Unique).Count -gt 1) { Fail "Documented archive versions are inconsistent: $($archiveTags -join ', ')" }
if ($releaseTags.Count -and $archiveTags.Count -and $releaseTags[0] -ne $archiveTags[0]) { Fail "Release tag '$($releaseTags[0])' does not match archive '$($archiveTags[0])'" }

if ($Live) {
    if (-not $releaseTags.Count) { $unknown.Add('GitHub release tag is not documented') }
    else {
        $tag = $releaseTags[0]; $uri = "https://api.github.com/repos/TiredRebel/Windows-Terminal-AI-Plugin/releases/tags/v$tag"
        try {
            $response = Invoke-WebRequest -Uri $uri -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'TerminalAI-doc-quality-check' } -TimeoutSec $TimeoutSec -UseBasicParsing
            if ($response.StatusCode -ne 200) { $unknown.Add("GitHub release endpoint returned HTTP $($response.StatusCode)") }
            else { $release = $response.Content | ConvertFrom-Json; if ($release.tag_name -ne "v$tag") { Fail "GitHub release tag is '$($release.tag_name)', documented 'v$tag'" }; if (-not ($release.assets.name -contains "TerminalAI-v$tag-win-x64.zip")) { Fail "GitHub release v$tag lacks documented ZIP asset" } }
        } catch { $unknown.Add("GitHub release endpoint unreachable: $($_.Exception.Message)") }
    }
    function Get-EndpointState([string]$Uri, [switch]$TreatEmptyMissing) {
        try {
            $r = Invoke-WebRequest -Uri $Uri -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'TerminalAI-doc-quality-check' } -TimeoutSec $TimeoutSec -UseBasicParsing
            if ($TreatEmptyMissing) {
                $entryCount = [regex]::Matches([string]$r.Content, '<entry(?:\s|>)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
                if ([string]::IsNullOrWhiteSpace($r.Content) -or $entryCount -eq 0) { return @{ State = 'missing'; Status = [int]$r.StatusCode } }
            }
            return @{ State = 'found'; Status = [int]$r.StatusCode }
        } catch {
            $response = $_.Exception.Response
            if ($response -and ([int]$response.StatusCode -eq 404)) { return @{ State = 'missing'; Status = 404 } }
            return @{ State = 'unknown'; Status = $null; Error = $_.Exception.Message }
        }
    }
    $wingetPending = ($markdownFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n" -match '(?i)(?:WinGet|Windows Package Manager).{0,180}(?:Upcoming|pending)'
    $wingetUri = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/t/TiredRebel/TerminalAI"
    $winget = Get-EndpointState $wingetUri
    if ($winget.State -eq 'unknown') { $unknown.Add("WinGet manifest endpoint unreachable: $($winget.Error)") }
    elseif ($wingetPending -and $winget.State -eq 'found') { Fail 'Documentation marks WinGet pending, but the authoritative winget-pkgs path exists' }
    elseif (-not $wingetPending -and $winget.State -eq 'missing') { Fail 'Documentation presents WinGet as live, but the authoritative winget-pkgs path is missing' }

    $galleryPending = ($markdownFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n" -match '(?i)(?:PowerShell Gallery|PSGallery).{0,180}(?:Upcoming|pending)'
    $gallery = Get-EndpointState 'https://www.powershellgallery.com/api/v2/FindPackagesById()?id=''TerminalAI''' -TreatEmptyMissing
    if ($gallery.State -eq 'unknown') { $unknown.Add("PowerShell Gallery endpoint unreachable: $($gallery.Error)") }
    elseif ($galleryPending -and $gallery.State -eq 'found') { Fail 'Documentation marks PowerShell Gallery pending, but the official package query returned a result' }
    elseif (-not $galleryPending -and $gallery.State -eq 'missing') { Fail 'Documentation presents PowerShell Gallery as live, but the official package query is empty' }
}

foreach ($u in $unknown) { Write-Host "UNKNOWN: $u" -ForegroundColor Yellow }
foreach ($f in $failures) { Write-Host "FAIL: $f" -ForegroundColor Red }
if ($failures.Count) { exit 1 }
if ($Live -and $unknown.Count) { exit 2 }
Write-Host 'Documentation quality checks passed.' -ForegroundColor Green
exit 0
