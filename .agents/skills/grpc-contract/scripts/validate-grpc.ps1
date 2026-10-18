# validate-grpc.ps1 — validate Protocol Buffers / gRPC contract + REQ traceability.
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

if ($text -notmatch '(?m)^syntax\s*=\s*"proto3"\s*;') {
    Add-Error 'syntax must be proto3'
}

if ($text -notmatch '(?m)^package\s+[\w.]+\s*;') {
    Add-Error 'missing package declaration'
}

if ($text -notmatch '(?m)^service\s+\w+\s*\{') {
    Add-Error 'missing service definition with rpc methods'
}

$rpcCount = ([regex]::Matches($text, '(?m)^\s*rpc\s+\w+')).Count
if ($rpcCount -lt 1) {
    Add-Error 'no rpc methods defined'
}

$nnnn = ''
if ($text -match 'REQ-(\d{4})') { $nnnn = $Matches[1] }
elseif ($Path -match 'GRPC-(\d+)-') { $nnnn = $Matches[1].PadLeft(4, '0') }
elseif ($ReqId) { $nnnn = ($ReqId -replace '\D', '').PadLeft(4, '0') }

if ($nnnn -and $text -notmatch "REQ-$nnnn") {
    Add-Error "missing REQ-$nnnn reference in proto comments"
}

if (Get-Command protoc -ErrorAction SilentlyContinue) {
    Write-Host 'INFO running protoc syntax check'
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) ("grpc-validate-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    try {
        Copy-Item $Path (Join-Path $tmpDir (Split-Path $Path -Leaf))
        & protoc --proto_path=$tmpDir --descriptor_set_out="$tmpDir/out.pb" (Join-Path $tmpDir (Split-Path $Path -Leaf)) 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) { Add-Error 'protoc validation failed' }
    }
    finally {
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($errors -gt 0) {
    Write-Host "FAIL: $errors gRPC/proto validation error(s)"
    exit 1
}

Write-Host "PASS: gRPC proto validation OK — REQ-$nnnn, $rpcCount rpc(s)"
exit 0
