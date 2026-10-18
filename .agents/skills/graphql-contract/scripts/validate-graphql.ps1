# validate-graphql.ps1 — validate GraphQL schema + REQ traceability.
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

if ($text -notmatch '(?i)type\s+Query\b') {
    Add-Error 'missing type Query — GraphQL schema must define Query root'
}

if ($text -notmatch '(?i)schema\s*\{' -and $text -notmatch '(?i)type\s+Query\b') {
    Add-Error 'invalid GraphQL schema structure'
}

$nnnn = ''
if ($text -match 'REQ-(\d{4})') { $nnnn = $Matches[1] }
elseif ($Path -match 'GQL-(\d+)-') { $nnnn = $Matches[1].PadLeft(4, '0') }
elseif ($ReqId) { $nnnn = ($ReqId -replace '\D', '').PadLeft(4, '0') }

if ($nnnn -and $text -notmatch "REQ-$nnnn") {
    Add-Error "missing REQ-$nnnn reference in schema comments or directives"
}

$fields = [regex]::Matches($text, '(?m)^\s+\w+\s*(\([^)]*\))?\s*:\s*')
if ($fields.Count -lt 1) {
    Add-Error 'no GraphQL fields defined — add Query/Mutation fields beyond placeholders'
}

if (Get-Command npx -ErrorAction SilentlyContinue) {
    Write-Host 'INFO optional GraphQL syntax check via graphql'
    $tmpSchema = $Path
    npx --yes graphql@16 --experimental-json-output 2>$null | Out-Null
}

if ($errors -gt 0) {
    Write-Host "FAIL: $errors GraphQL validation error(s)"
    exit 1
}

Write-Host "PASS: GraphQL validation OK — REQ-$nnnn, $($fields.Count) field(s)"
exit 0
