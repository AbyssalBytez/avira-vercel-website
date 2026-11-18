<#
.SYNOPSIS
    Points every absolute URL in the site at a given domain.

.DESCRIPTION
    This is a static single page, so the production origin has to be spelled out
    in full wherever a machine reads it: the canonical link, the Open Graph and
    Twitter tags, the JSON-LD graph, robots.txt and sitemap.xml.

    Renaming the Vercel project (or attaching a real domain) leaves all of those
    pointing at the old host. Meta/WhatsApp then follow the old domain's redirect
    to the new one, notice that og:url names a different host, and silently drop
    the link preview. This script rewrites every occurrence in one pass.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/set-domain.ps1 avira-perfumes.vercel.app

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/set-domain.ps1 https://aviraperfumes.com/
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Domain
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Normalise the argument to "https://host" with no trailing slash.
$hostPart = $Domain.Trim()
$hostPart = $hostPart -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''
$hostPart = $hostPart.TrimEnd('/')

if ($hostPart -notmatch '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$') {
    throw "'$Domain' does not look like a bare domain (expected something like avira-perfumes.vercel.app)."
}

$newOrigin = "https://$hostPart"
$files = @('index.html', 'robots.txt', 'sitemap.xml')
$utf8 = New-Object System.Text.UTF8Encoding($false)

# The canonical tag is the source of truth for the *current* origin, which means
# this script keeps working on every run, not just the first one.
$indexPath = Join-Path $root 'index.html'
$html = [System.IO.File]::ReadAllText($indexPath)
$match = [regex]::Match($html, '<link\s+rel="canonical"\s+href="(https?://[^/"]+)/?"')
if (-not $match.Success) {
    throw 'Could not find <link rel="canonical" href="..."> in index.html.'
}

$oldOrigin = $match.Groups[1].Value
if ($oldOrigin -eq $newOrigin) {
    Write-Host "Already pointing at $newOrigin - nothing to do."
    exit 0
}

$pattern = [regex]::Escape($oldOrigin)
$total = 0

foreach ($file in $files) {
    $path = Join-Path $root $file
    if (-not (Test-Path $path)) {
        Write-Warning "Skipping missing file: $file"
        continue
    }

    $text = [System.IO.File]::ReadAllText($path)
    $count = ([regex]::Matches($text, $pattern)).Count
    if ($count -eq 0) { continue }

    # ReadAllText/WriteAllText keep the existing UTF-8-without-BOM encoding and
    # the CRLF line endings intact.
    [System.IO.File]::WriteAllText($path, $text.Replace($oldOrigin, $newOrigin), $utf8)
    $total += $count
    Write-Host ("{0,-12} {1} replacement(s)" -f $file, $count)
}

$leftovers = 0
foreach ($file in $files) {
    $path = Join-Path $root $file
    if (-not (Test-Path $path)) { continue }
    $leftovers += ([regex]::Matches([System.IO.File]::ReadAllText($path), $pattern)).Count
}

if ($leftovers -gt 0) {
    throw "$leftovers occurrence(s) of $oldOrigin are still present."
}

Write-Host "Done: $oldOrigin -> $newOrigin ($total replacements)." -ForegroundColor Green
