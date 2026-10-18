# scaffold-openapi.ps1 — create OpenAPI stub + contract brief from a REQ id.
param(
    [Parameter(Mandatory)][string]$ReqId,
    [string]$Slug = '',
    [string]$FeatureTitle = '',
    [string]$Session = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Find-RepoRoot {
    $cwd = (Get-Location).Path
    if ((Test-Path (Join-Path $cwd 'pipeline.manifest.json')) -or
        (Test-Path (Join-Path $cwd 'docs/sdlc/requirements')) -or
        (Test-Path (Join-Path $cwd '.git')) -or
        (Test-Path (Join-Path $cwd '.agents/pipeline.home'))) {
        return (Resolve-Path $cwd).Path
    }
    $dir = $PSScriptRoot
    while ($dir -and $dir -ne '/') {
        if ((Test-Path (Join-Path $dir 'pipeline.manifest.json')) -or
            (Test-Path (Join-Path $dir 'AGENTS.md')) -or
            (Test-Path (Join-Path $dir '.git')) -or
            (Test-Path (Join-Path $dir '.agents/pipeline.home')) -or
            (Test-Path (Join-Path $dir '.beads'))) {
            return (Resolve-Path $dir).Path
        }
        $dir = Split-Path $dir -Parent
    }
    return (Resolve-Path (Join-Path $PSScriptRoot '../../../../')).Path
}

function Get-OpenApiArtifactDir {
    param([string]$RepoRoot)
    $manifest = Join-Path $RepoRoot 'pipeline.manifest.json'
    if (Test-Path $manifest) {
        $json = Get-Content $manifest -Raw | ConvertFrom-Json
        if ($json.artifacts.openapi) {
            $pattern = [string]$json.artifacts.openapi
            $dir = Split-Path ($pattern -replace '\{id\}', 'x' -replace '\{slug\}', 'y') -Parent
            if ($dir) { return Join-Path $RepoRoot $dir }
        }
    }
    return Join-Path $RepoRoot 'docs/sdlc/api'
}

$RepoRoot = Find-RepoRoot
Set-Location $RepoRoot

$nnnn = $ReqId -replace '\D', ''
if ($nnnn.Length -lt 4) { $nnnn = $nnnn.PadLeft(4, '0') }

if ($Session) {
    $apiDir = Join-Path $RepoRoot "_code_agent/$Session/artifacts/sdlc/api"
    $reqDir = Join-Path $RepoRoot "_code_agent/$Session/artifacts/sdlc/requirements"
}
else {
    $apiDir = Get-OpenApiArtifactDir -RepoRoot $RepoRoot
    $reqDir = Join-Path $RepoRoot 'docs/sdlc/requirements'
}
New-Item -ItemType Directory -Path $apiDir -Force | Out-Null
$reqFile = Get-ChildItem -Path $reqDir -Filter "REQ-$nnnn-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $reqFile) {
    Write-Host "FAIL: REQ-$nnnn-*.md not found in $reqDir" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Slug)) {
    if ($reqFile.Name -match "REQ-$nnnn-(.+)\.md") {
        $Slug = $Matches[1]
    }
    else {
        $Slug = 'api'
    }
}

if ([string]::IsNullOrWhiteSpace($FeatureTitle)) {
    $reqText = Get-Content $reqFile.FullName -Raw
    if ($reqText -match '# REQ-\d+:\s*(.+)') {
        $FeatureTitle = $Matches[1].Trim()
    }
    else {
        $FeatureTitle = "REQ-$nnnn API"
    }
}

$outYaml = Join-Path $apiDir "OAPI-$nnnn-$Slug.yaml"
$outBrief = Join-Path $apiDir "OAPI-$nnnn-$Slug-brief.md"

if ((Test-Path $outYaml) -and -not $Force) {
    Write-Host "FAIL: $outYaml exists (use -Force to overwrite)" -ForegroundColor Red
    exit 2
}

$stubPath = Join-Path (Join-Path $PSScriptRoot '..') 'templates/openapi-stub.yaml'
$stub = Get-Content $stubPath -Raw
$stub = $stub.Replace('{REQ_ID}', $nnnn).Replace('{FEATURE_TITLE}', $FeatureTitle)
Set-Content -Path $outYaml -Value $stub -Encoding UTF8 -NoNewline

$briefPath = Join-Path (Join-Path $PSScriptRoot '..') 'templates/contract-brief.md'
$brief = Get-Content $briefPath -Raw
$brief = $brief.Replace('{REQ_ID}', $nnnn).Replace('{slug}', $Slug)
Set-Content -Path $outBrief -Value $brief -Encoding UTF8

$report = [ordered]@{
    schemaVersion = '1'
    reqId         = "REQ-$nnnn"
    openapi       = (Resolve-Path $outYaml).Path.Replace($RepoRoot, '').TrimStart('/')
    brief         = (Resolve-Path $outBrief).Path.Replace($RepoRoot, '').TrimStart('/')
    reqSource     = $reqFile.Name
}
$reportPath = Join-Path $RepoRoot '.agents/openapi-scaffold-report.json'
if (-not (Test-Path (Split-Path $reportPath -Parent))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $reportPath -Parent) | Out-Null
}
$report | ConvertTo-Json | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "OK   OpenAPI stub -> $outYaml"
Write-Host "OK   Contract brief -> $outBrief"
Write-Host 'PASS: scaffold complete — architect/TL completes paths and schemas'
exit 0
