# dotnet-format.ps1 — apply or verify dotnet format for the repo.
param([switch]$Verify)

$ErrorActionPreference = 'Stop'

function Find-RepoRoot {
    $start = $PSScriptRoot
    $dir = $start
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

$RepoRoot = Find-RepoRoot
Set-Location $RepoRoot

function Get-FormatCommandFromManifest {
    $manifest = Join-Path $RepoRoot 'pipeline.manifest.json'
    if (-not (Test-Path $manifest)) { return '' }
    $json = Get-Content $manifest -Raw | ConvertFrom-Json
    if ($json.format -and $json.format.command) {
        return [string]$json.format.command
    }
    return ''
}

function Get-FormatTarget {
    $sln = Get-ChildItem -Path $RepoRoot -Recurse -Depth 3 -Include '*.sln', '*.slnx' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Select-Object -First 1
    if ($sln) { return $sln.FullName }

    $csproj = Get-ChildItem -Path $RepoRoot -Recurse -Depth 3 -Filter '*.csproj' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Select-Object -First 1
    if ($csproj) { return $csproj.FullName }
    return ''
}

$custom = Get-FormatCommandFromManifest
$target = Get-FormatTarget

if ($custom) {
    $formatCmd = $custom
}
elseif ($target) {
    if ($Verify) {
        $formatCmd = "dotnet format `"$target`" --verify-no-changes"
    }
    else {
        $formatCmd = "dotnet format `"$target`""
    }
}
else {
    $formatCmd = if ($Verify) { 'dotnet format --verify-no-changes' } else { 'dotnet format' }
}

Write-Host "=== dotnet format @ $RepoRoot ==="
Write-Host "+ $formatCmd"
Invoke-Expression $formatCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host 'FAIL: dotnet format failed'
    exit 1
}

if ($Verify) { Write-Host 'PASS: dotnet format verify OK' }
else { Write-Host 'PASS: dotnet format applied' }
