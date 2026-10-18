# scaffold-grpc.ps1 — create gRPC proto stub + contract brief from REQ id.
param(
    [Parameter(Mandatory)][string]$ReqId,
    [string]$Slug = '',
    [string]$FeatureTitle = '',
    [string]$PackageName = '',
    [string]$ServiceName = '',
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

function Get-ArtifactDir {
    param([string]$RepoRoot, [string]$ManifestKey)
    $manifest = Join-Path $RepoRoot 'pipeline.manifest.json'
    if (Test-Path $manifest) {
        $json = Get-Content $manifest -Raw | ConvertFrom-Json
        if ($json.artifacts.$ManifestKey) {
            $pattern = [string]$json.artifacts.$ManifestKey
            $dir = Split-Path ($pattern -replace '\{id\}', 'x' -replace '\{slug\}', 'y') -Parent
            if ($dir) { return Join-Path $RepoRoot $dir }
        }
    }
    return Join-Path $RepoRoot 'docs/sdlc/api'
}

function ConvertTo-PascalCase([string]$Value) {
    $parts = ($Value -split '[-_\s]+') | Where-Object { $_ }
    return ($parts | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1).ToLower() }) -join ''
}

$RepoRoot = Find-RepoRoot
Set-Location $RepoRoot

$nnnn = ($ReqId -replace '\D', '').PadLeft(4, '0')
if ($Session) {
    $apiDir = Join-Path $RepoRoot "_code_agent/$Session/artifacts/sdlc/api"
    $reqDir = Join-Path $RepoRoot "_code_agent/$Session/artifacts/sdlc/requirements"
}
else {
    $apiDir = Get-ArtifactDir $RepoRoot 'grpc_proto'
    $reqDir = Join-Path $RepoRoot 'docs/sdlc/requirements'
}
New-Item -ItemType Directory -Force -Path $apiDir | Out-Null
$reqFile = Get-ChildItem -Path $reqDir -Filter "REQ-$nnnn-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $reqFile) {
    Write-Host "FAIL: REQ-$nnnn-*.md not found" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Slug) -and $reqFile.Name -match "REQ-$nnnn-(.+)\.md") {
    $Slug = $Matches[1]
}
if ([string]::IsNullOrWhiteSpace($Slug)) { $Slug = 'api' }

if ([string]::IsNullOrWhiteSpace($FeatureTitle)) {
    $reqText = Get-Content $reqFile.FullName -Raw
    if ($reqText -match '# REQ-\d+:\s*(.+)') { $FeatureTitle = $Matches[1].Trim() }
    else { $FeatureTitle = "REQ-$nnnn gRPC API" }
}

$pascal = ConvertTo-PascalCase $Slug
if ([string]::IsNullOrWhiteSpace($PackageName)) { $PackageName = $pascal.ToLowerInvariant() }
if ([string]::IsNullOrWhiteSpace($ServiceName)) { $ServiceName = "${pascal}Service" }

$outProto = Join-Path $apiDir "GRPC-$nnnn-$Slug.proto"
$outBrief = Join-Path $apiDir "GRPC-$nnnn-$Slug-brief.md"

if ((Test-Path $outProto) -and -not $Force) {
    Write-Host "FAIL: $outProto exists (use -Force)" -ForegroundColor Red
    exit 2
}

$stub = Get-Content (Join-Path $PSScriptRoot '../templates/service-stub.proto') -Raw
$stub = $stub.Replace('{REQ_ID}', $nnnn).Replace('{FEATURE_TITLE}', $FeatureTitle)
$stub = $stub.Replace('{PACKAGE_NAME}', $PackageName).Replace('{SERVICE_NAME}', $ServiceName)
Set-Content -Path $outProto -Value $stub -Encoding UTF8

$brief = Get-Content (Join-Path $PSScriptRoot '../templates/contract-brief.md') -Raw
$brief = $brief.Replace('{REQ_ID}', $nnnn).Replace('{slug}', $Slug)
$brief = $brief.Replace('{package}', $PackageName).Replace('{ServiceName}', $ServiceName)
Set-Content -Path $outBrief -Value $brief -Encoding UTF8

Write-Host "OK   gRPC proto -> $outProto"
Write-Host "OK   Contract brief -> $outBrief"
Write-Host 'PASS: gRPC scaffold complete'
exit 0
