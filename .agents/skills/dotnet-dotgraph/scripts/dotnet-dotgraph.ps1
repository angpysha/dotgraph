# dotnet-dotgraph.ps1 — wrapper for the dotgraph NuGet package graph CLI.
param(
    [Parameter(Position = 0)]
    [ValidateSet('init', 'refresh', 'diff', 'sync', 'analyze', 'update', 'ensure-tool')]
    [string]$Command = 'diff',

    [switch]$Interactive,
    [switch]$DryRun,
    [string]$DotgraphVersion = '',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

function Find-RepoRoot {
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

function Find-DotgraphWorkingRoot {
    param([string]$RepoRoot)
    if (Test-Path (Join-Path $RepoRoot '.dotgraph.json')) {
        return $RepoRoot
    }
    $sln = Get-ChildItem -Path $RepoRoot -Recurse -Depth 4 -Include '*.sln', '*.slnx' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Select-Object -First 1
    if ($sln) { return $sln.Directory.FullName }
    return $RepoRoot
}

function Get-DotgraphManifestConfig {
    param([string]$RepoRoot)
    $manifest = Join-Path $RepoRoot 'pipeline.manifest.json'
    if (-not (Test-Path $manifest)) { return $null }
    $json = Get-Content $manifest -Raw | ConvertFrom-Json
    if ($json.dotgraph) { return $json.dotgraph }
    return $null
}

function Ensure-DotgraphTool {
    param([string]$RepoRoot, [string]$Version)

    if (Test-Path (Join-Path $RepoRoot '.config/dotnet-tools.json')) {
        Push-Location $RepoRoot
        try {
            Write-Host '+ dotnet tool restore'
            dotnet tool restore 2>&1 | Write-Host
            if ($LASTEXITCODE -eq 0) {
                $local = dotnet tool list 2>&1 | Out-String
                if ($local -match 'dotgraph') {
                    Write-Host 'OK   dotgraph (local tool manifest)'
                    return 'local'
                }
            }
        }
        finally {
            Pop-Location
        }
    }

    $globalList = dotnet tool list --global 2>&1 | Out-String
    if ($globalList -match 'dotgraph') {
        Write-Host 'OK   dotgraph (global tool)'
        return 'global'
    }

    $installArgs = @('tool', 'install', '--global', 'dotgraph')
    if ($Version) { $installArgs += @('--version', $Version) }
    Write-Host ('+ dotnet ' + ($installArgs -join ' '))
    & dotnet @installArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to install dotgraph. See https://www.nuget.org/packages/dotgraph'
    }
    Write-Host 'OK   dotgraph installed (global)'
    return 'global'
}

function Build-CommandArgs {
    param(
        [string]$Command,
        [switch]$Interactive,
        [switch]$DryRun,
        [string[]]$Rest
    )

    $args = @($Command)
    switch ($Command) {
        'sync' {
            if ($DryRun) { $args += '--dry-run' }
            if ($Interactive) { $args += '--interactive' }
        }
        'update' {
            if ($Rest.Count -lt 2) {
                throw "update requires package/version pairs, e.g. update MyLib.Core 2.1.0"
            }
            $args += $Rest
            if ($DryRun) { $args += '--dry-run' }
            if ($Interactive) { $args += '--interactive' }
        }
        'analyze' {
            if ($Rest.Count -lt 1) {
                throw 'analyze requires at least one package id'
            }
            $args += $Rest
        }
        default {
            if ($Rest.Count -gt 0) {
                throw "command '$Command' does not accept extra arguments"
            }
        }
    }
    return $args
}

$RepoRoot = Find-RepoRoot
$WorkRoot = Find-DotgraphWorkingRoot $RepoRoot
Set-Location $WorkRoot

$manifestCfg = Get-DotgraphManifestConfig $RepoRoot
if ($manifestCfg -and $manifestCfg.toolVersion -and -not $DotgraphVersion) {
    $DotgraphVersion = [string]$manifestCfg.toolVersion
}

if ($Command -eq 'ensure-tool') {
    Ensure-DotgraphTool -RepoRoot $RepoRoot -Version $DotgraphVersion | Out-Null
    Write-Host 'PASS: dotgraph tool ready'
    exit 0
}

$toolSource = Ensure-DotgraphTool -RepoRoot $RepoRoot -Version $DotgraphVersion
$cliArgs = Build-CommandArgs -Command $Command -Interactive:$Interactive -DryRun:$DryRun -Rest $Rest

Write-Host "=== dotgraph $Command @ $WorkRoot ==="
$logPath = Join-Path $RepoRoot '.agents/dotgraph-last-run.log'
$agentsDir = Split-Path $logPath -Parent
if (-not (Test-Path $agentsDir)) {
    New-Item -ItemType Directory -Force -Path $agentsDir | Out-Null
}

if (Get-Command dotgraph -ErrorAction SilentlyContinue) {
    $output = & dotgraph @cliArgs 2>&1
}
else {
    $output = & dotnet dotgraph @cliArgs 2>&1
}
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 0 }

$output | Tee-Object -FilePath $logPath | Write-Host

$report = [ordered]@{
    schemaVersion = '1'
    command       = $Command
    cliArgs       = $cliArgs
    workingRoot   = $WorkRoot
    toolSource    = $toolSource
    exitCode      = $exitCode
    log           = '.agents/dotgraph-last-run.log'
    snapshot      = if (Test-Path (Join-Path $WorkRoot '.dotgraph.json')) { '.dotgraph.json' } else { $null }
    docs          = 'https://www.nuget.org/packages/dotgraph'
}
$reportPath = Join-Path $RepoRoot '.agents/dotgraph-report.json'
$report | ConvertTo-Json -Depth 4 | Set-Content -Path $reportPath -Encoding UTF8

if ($exitCode -ne 0) {
    Write-Host "FAIL: dotgraph $Command exited $exitCode" -ForegroundColor Red
    exit $exitCode
}

Write-Host "PASS: dotgraph $Command OK"
Write-Host "Report: .agents/dotgraph-report.json"
exit 0
