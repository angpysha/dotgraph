# Developer gate: build.command from pipeline.manifest.json + optional secret scan.
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
Set-Location $repoRoot

. (Join-Path $repoRoot 'scripts/lib/PipelineScripts.ps1')

$manifest = Join-Path $repoRoot 'pipeline.manifest.json'
if (-not (Test-Path $manifest)) {
    Write-Host 'FAIL: pipeline.manifest.json not found — run agentic-tool install + .agents adapt'
    exit 1
}

$buildCmd = Read-ManifestValue -ManifestPath $manifest -Keys @('build', 'command')

Write-Host '=== Dev Gate ==='
if ([string]::IsNullOrWhiteSpace($buildCmd)) {
    Write-Warning 'WARN: no build.command in manifest — skipping build step'
}
elseif (-not (Invoke-ManifestCommand $buildCmd)) {
    Write-Host 'FAIL: build failed'
    exit 1
}

Write-Host '=== Secret scan ==='
if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    & gitleaks detect --no-banner --redact 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'FAIL: gitleaks found potential secrets'
        exit 1
    }
    Write-Host 'gitleaks: clean'
}
else {
    $pattern = '(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|password\s*=\s*["''][^"'']{6,})'
    if (Test-Path (Join-Path $repoRoot '.git')) {
        $diff = git diff --cached -U0 2>$null
        if ($diff -match $pattern) {
            Write-Host 'FAIL: potential secret in staged diff (regex)'
            exit 1
        }
    }
    Write-Host 'secret scan (regex): clean'
}

Write-Host 'PASS: Dev gate OK'
