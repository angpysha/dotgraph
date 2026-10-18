# Tester gate: test.command from pipeline.manifest.json.
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
Set-Location $repoRoot

. (Join-Path $repoRoot 'scripts/lib/PipelineScripts.ps1')

$manifest = Join-Path $repoRoot 'pipeline.manifest.json'
if (-not (Test-Path $manifest)) {
    Write-Host 'FAIL: pipeline.manifest.json not found'
    exit 1
}

$testCmd = Read-ManifestValue -ManifestPath $manifest -Keys @('test', 'command')
if ([string]::IsNullOrWhiteSpace($testCmd)) {
    Write-Host 'FAIL: no test.command in manifest'
    exit 1
}

Write-Host '=== Test Gate ==='
if (-not (Invoke-ManifestCommand $testCmd)) {
    Write-Host 'FAIL: tests failed'
    exit 1
}

Write-Host 'PASS: Test gate OK'
