# validate-openapi.ps1 — validate OpenAPI contract + REQ traceability.
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$ReqId = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Path)) {
    Write-Host "FAIL: file not found: $Path" -ForegroundColor Red
    exit 1
}

$text = Get-Content $Path -Raw
$errors = 0

function Add-Error([string]$Message) {
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:errors++
}

if ($text -notmatch '(?m)^openapi:\s*3\.[01]') {
    Add-Error 'missing or invalid openapi version (expected 3.0.x or 3.1.x)'
}

if ($text -notmatch '(?m)^info:\s*$' -and $text -notmatch '(?m)^info:') {
    Add-Error 'missing info section'
}

if ($text -notmatch 'title:\s*.+') {
    Add-Error 'info.title is required'
}

if ($text -notmatch 'version:\s*.+') {
    Add-Error 'info.version is required'
}

if ($text -match '(?m)^paths:\s*\{\s*\}\s*$' -or $text -notmatch '(?m)^paths:') {
    Add-Error 'paths section is empty or missing — add at least one endpoint'
}

$operationIds = [regex]::Matches($text, '(?m)^\s+operationId:\s*(\S+)')
if ($operationIds.Count -eq 0) {
    Add-Error 'no operationId values found — every operation must have operationId'
}

$nnnn = ''
if ($text -match 'x-req-id:\s*REQ-(\d+)') {
    $nnnn = $Matches[1]
}
elseif ($Path -match 'OAPI-(\d+)-') {
    $nnnn = $Matches[1]
}
elseif ($ReqId) {
    $nnnn = $ReqId -replace '\D', ''
}

if ($nnnn -and $text -notmatch "REQ-$nnnn") {
    Add-Error "missing REQ-$nnnn reference (x-req-id or description)"
}

if ($ReqId -and $nnnn -and ($ReqId -replace '\D', '') -ne ($nnnn -replace '^0+', '')) {
    # allow padded ids
}

# Optional external validator
if (Get-Command npx -ErrorAction SilentlyContinue) {
    Write-Host 'INFO running @redocly/cli lint (optional)'
    $lint = npx --yes @redocly/cli@1 lint $Path 2>&1
    $lint | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Add-Error 'Redocly lint failed (fix OpenAPI syntax)'
    }
}

if ($errors -gt 0) {
    Write-Host "FAIL: $errors OpenAPI validation error(s)"
    exit 1
}

Write-Host "PASS: OpenAPI validation OK — $($operationIds.Count) operation(s), REQ-$nnnn"
exit 0
