# Validates SDD and TDD exist for a given REQ numeric ID.
param(
    [Parameter(Mandatory)][string]$Nnnn,
    [string]$Session = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/sdlc-session.ps1"

$designDir = Get-DesignDir -Session $Session
$apiDir = Get-ApiDir -Session $Session
$errors = 0

$sdd = Get-ChildItem -Path $designDir -Filter "SDD-$Nnnn-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1
$tdd = Get-ChildItem -Path $designDir -Filter "TDD-$Nnnn-*.md" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $sdd) {
    Write-Host "FAIL: SDD-$Nnnn-*.md not found in $designDir"
    $errors++
}
if (-not $tdd) {
    Write-Host "FAIL: TDD-$Nnnn-*.md not found in $designDir"
    $errors++
}

function Test-DesignFile {
    param([string]$File, [string]$Label)
    $text = Get-Content $File -Raw
    if ($text -notmatch "REQ-$Nnnn") {
        Write-Host "FAIL: $Label missing parent REQ-$Nnnn reference"
        $script:errors++
    }
    if ($text -notmatch '```mermaid') {
        Write-Host "FAIL: $Label missing Mermaid diagram"
        $script:errors++
    }
}

if ($sdd) {
    Test-DesignFile $sdd.FullName 'SDD'
    $sddText = Get-Content $sdd.FullName -Raw
    if ($sddText -notmatch 'alternative') {
        Write-Host 'FAIL: SDD missing Design Alternatives section'
        $errors++
    }
    if ($sddText -notmatch 'migration') {
        Write-Host 'FAIL: SDD missing Migration Impact section'
        $errors++
    }
}

if ($tdd) {
    Test-DesignFile $tdd.FullName 'TDD'
    $tddText = Get-Content $tdd.FullName -Raw
    if ($tddText -notmatch 'testing strategy') {
        Write-Host 'FAIL: TDD missing Testing Strategy section'
        $errors++
    }
}

# OpenAPI contract (when SDD defines HTTP API)
$sddHasApi = $false
if ($sdd) {
    $sddText = Get-Content $sdd.FullName -Raw
    if ($sddText -match '(?i)##\s*4\.\s*API Design' -and $sddText -match '\|\s*(GET|POST|PUT|PATCH|DELETE)\s*\|') {
        $sddHasApi = $true
    }
}

if ($sddHasApi) {
    $oapiFile = Get-ChildItem -Path $apiDir -Filter "OAPI-$Nnnn-*.yaml" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $oapiFile) {
        $oapiFile = Get-ChildItem -Path $apiDir -Filter "OAPI-$Nnnn-*.yml" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $oapiFile) {
        Write-Host "FAIL: SDD defines HTTP REST API but OAPI-$Nnnn-*.yaml not found in $apiDir"
        Write-Host 'HINT: run openapi-contract scaffold-openapi.ps1 then complete schema (architect Phase 5)'
        $errors++
    }
    else {
        $validateOapi = Join-Path $PSScriptRoot '../../openapi-contract/scripts/validate-openapi.ps1'
        if (Test-Path $validateOapi) {
            Write-Host "INFO validating OpenAPI $($oapiFile.Name)"
            & pwsh -NoProfile -File $validateOapi $oapiFile.FullName -ReqId $Nnnn
            if ($LASTEXITCODE -ne 0) { $errors++ }
        }
        else {
            Write-Host "WARN validate-openapi.ps1 not found at $validateOapi"
        }
    }
}

# GraphQL contract
$sddHasGraphql = $false
if ($sdd) {
    $sddText = Get-Content $sdd.FullName -Raw
    if ($sddText -match '(?i)##\s*4b\.\s*GraphQL|GraphQL API') {
        $sddHasGraphql = $true
    }
}

if ($sddHasGraphql) {
    $gqlFile = Get-ChildItem -Path $apiDir -Filter "GQL-$Nnnn-*.graphql" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gqlFile) {
        Write-Host "FAIL: SDD defines GraphQL API but GQL-$Nnnn-*.graphql not found in $apiDir"
        $errors++
    }
    else {
        $validateGql = Join-Path $PSScriptRoot '../../graphql-contract/scripts/validate-graphql.ps1'
        if (Test-Path $validateGql) {
            Write-Host "INFO validating GraphQL $($gqlFile.Name)"
            & pwsh -NoProfile -File $validateGql $gqlFile.FullName -ReqId $Nnnn
            if ($LASTEXITCODE -ne 0) { $errors++ }
        }
    }
}

# gRPC / protobuf contract
$sddHasGrpc = $false
if ($sdd) {
    $sddText = Get-Content $sdd.FullName -Raw
    if ($sddText -match '(?i)##\s*4c\.\s*gRPC|gRPC API|protobuf') {
        $sddHasGrpc = $true
    }
}

if ($sddHasGrpc) {
    $protoFile = Get-ChildItem -Path $apiDir -Filter "GRPC-$Nnnn-*.proto" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $protoFile) {
        Write-Host "FAIL: SDD defines gRPC API but GRPC-$Nnnn-*.proto not found in $apiDir"
        $errors++
    }
    else {
        $validateGrpc = Join-Path $PSScriptRoot '../../grpc-contract/scripts/validate-grpc.ps1'
        if (Test-Path $validateGrpc) {
            Write-Host "INFO validating gRPC $($protoFile.Name)"
            & pwsh -NoProfile -File $validateGrpc $protoFile.FullName -ReqId $Nnnn
            if ($LASTEXITCODE -ne 0) { $errors++ }
        }
    }
}

if ($errors -gt 0) {
    Write-Host "FAIL: $errors design validation error(s)"
    exit 1
}

Write-Host "PASS: Design validation OK — SDD=$($sdd.FullName) TDD=$($tdd.FullName)"
