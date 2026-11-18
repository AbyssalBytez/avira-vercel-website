# ---------------------------------------------------------------------------
# check-classes.ps1 - guard against classes that silently render as nothing.
#
# tailwind.css is a pre-compiled bundle, so a class that is used in index.html
# but never made it into the bundle does nothing at all: no error, no warning,
# just a layout that quietly disagrees with the markup. This script lists every
# class token used in index.html that is defined in neither tailwind.css nor the
# page's inline <style> block.
#
# Usage (from the project folder):
#   powershell -ExecutionPolicy Bypass -File tools/check-classes.ps1
#
# Exit code 0 = every class resolves, 1 = at least one does not.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

$htmlPath = Join-Path $root 'index.html'
$cssPath = Join-Path $root 'tailwind.css'

foreach ($p in @($htmlPath, $cssPath)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Error "Missing file: $p"
        exit 2
    }
}

$html = [System.IO.File]::ReadAllText($htmlPath)
$css = [System.IO.File]::ReadAllText($cssPath)

# The page's own <style> block legitimately defines custom classes (.nav-grid,
# .btn-liquid, .checkout-input, ...), so those count as resolved too.
$inlineCss = ''
$m = [regex]::Matches($html, '(?s)<style[^>]*>(.*?)</style>')
foreach ($block in $m) { $inlineCss += $block.Groups[1].Value + "`n" }

# Backslashes only exist to escape selectors in the compiled CSS; dropping them
# lets a plain-text search find ".sm\:block" when the token is "sm:block".
$cssIndex = ($css + "`n" + $inlineCss) -replace '\\', ''

# Collect class tokens from every class="..." attribute, including the ones
# inside the JS template literals that build the grid and quiz markup.
$classAttr = [regex]::Matches($html, '(?:class|className)\s*=\s*"([^"]*)"')
$tokens = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($attr in $classAttr) {
    $value = $attr.Groups[1].Value
    if ($value -match '\$\{') { continue }   # interpolated: skip the fragment
    foreach ($raw in ($value -split '\s+')) {
        $t = $raw.Trim()
        if (-not $t) { continue }
        if ($t -match '^[@/]') { continue }
        [void]$tokens.Add($t)
    }
}

# Class names that only ever appear via JS concatenation or that are state
# hooks rather than styling hooks.
$allow = @(
    'is-checkout'
)

$missing = New-Object 'System.Collections.Generic.List[string]'
foreach ($t in $tokens) {
    if ($allow -contains $t) { continue }
    $needle = '.' + $t
    # A definition looks like:  .token {   .token:hover {   .a .token > x {
    $pattern = '(?m)(^|[\s,{}>+~])' + [regex]::Escape($needle) + '(?=[\s,{:.#\[>+~]|$)'
    if (-not [regex]::IsMatch($cssIndex, $pattern)) {
        [void]$missing.Add($t)
    }
}

if ($missing.Count -eq 0) {
    Write-Host ("OK - all {0} classes used in index.html resolve." -f $tokens.Count)
    exit 0
}

$missing.Sort()
Write-Host ("{0} of {1} classes used in index.html have no CSS rule:" -f $missing.Count, $tokens.Count)
foreach ($t in $missing) { Write-Host ("  " + $t) }
exit 1
