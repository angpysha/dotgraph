# dotnet-unit-tests.ps1 — run unit tests with Cobertura coverage + TRX for Azure DevOps.
param(
    [string]$Configuration = 'Release',
    [string]$Filter = '',
    [string]$ResultsDir = 'TestResults',
    [switch]$NoCoverage
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

function Get-ManifestTestConfig {
    param([string]$RepoRoot)
    $manifest = Join-Path $RepoRoot 'pipeline.manifest.json'
    if (-not (Test-Path $manifest)) { return $null }
    $json = Get-Content $manifest -Raw | ConvertFrom-Json
    return $json.test
}

function Get-TestTarget {
    param([string]$RepoRoot)
    $sln = Get-ChildItem -Path $RepoRoot -Recurse -Depth 3 -Include '*.sln', '*.slnx' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Select-Object -First 1
    if ($sln) { return $sln.FullName }

    $testProj = Get-ChildItem -Path $RepoRoot -Recurse -Depth 4 -Filter '*Tests*.csproj' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Select-Object -First 1
    if ($testProj) { return $testProj.FullName }

    $csproj = Get-ChildItem -Path $RepoRoot -Recurse -Depth 3 -Filter '*.csproj' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Select-Object -First 1
    if ($csproj) { return $csproj.FullName }
    return ''
}

function Get-RelativePath {
    param([string]$RepoRoot, [string]$FullPath)
    if ([string]::IsNullOrWhiteSpace($FullPath)) { return '' }
    $root = (Resolve-Path $RepoRoot).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $full = (Resolve-Path $FullPath).Path
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
    }
    return $full
}

function Write-AzureDevOpsResults {
    param(
        [string]$RepoRoot,
        [string]$ResultsDir,
        [string]$TrxPath,
        [string]$CoberturaPath,
        [int]$ExitCode,
        [hashtable]$CoverageSummary
    )

    $relTrx = Get-RelativePath $RepoRoot $TrxPath
    $relCobertura = Get-RelativePath $RepoRoot $CoberturaPath
    $summaryRel = Join-Path $ResultsDir 'azure-devops-results.json'
    $summaryPath = Join-Path $RepoRoot $summaryRel

    $payload = [ordered]@{
        schemaVersion = '1'
        passed        = ($ExitCode -eq 0)
        exitCode      = $ExitCode
        azureDevOps   = [ordered]@{
            publishTestResults = [ordered]@{
                testResultsFormat = 'VSTest'
                testResultsFiles  = $relTrx
            }
            publishCodeCoverageResults = [ordered]@{
                codeCoverageTool      = 'Cobertura'
                summaryFileLocation   = $relCobertura
            }
        }
        artifacts = [ordered]@{
            trx              = $relTrx
            cobertura        = $relCobertura
            resultsDirectory = $ResultsDir
        }
        coverage = $CoverageSummary
    }

    $payload | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding UTF8
    return $summaryPath
}

$RepoRoot = Find-RepoRoot
Set-Location $RepoRoot

$testConfig = Get-ManifestTestConfig $RepoRoot
if ($testConfig -and $testConfig.results -and $testConfig.results.directory) {
    $ResultsDir = [string]$testConfig.results.directory
}

$absResults = Join-Path $RepoRoot $ResultsDir
$coverageDir = Join-Path $absResults 'coverage'
$trxPath = Join-Path $absResults 'test-results.trx'
$coberturaPath = Join-Path $coverageDir 'cobertura.xml'

New-Item -ItemType Directory -Force -Path $coverageDir | Out-Null

$target = Get-TestTarget $RepoRoot
if (-not $target) {
    Write-Host 'FAIL: no solution or test project found' -ForegroundColor Red
    exit 1
}

$runSettings = Join-Path $PSScriptRoot 'coverage.runsettings.xml'
if (-not (Test-Path $runSettings)) {
    Write-Host "FAIL: missing $runSettings" -ForegroundColor Red
    exit 1
}

$dotnetArgs = @(
    'test',
    $target,
    '--configuration', $Configuration,
    '--results-directory', $absResults,
    '--logger', "trx;LogFileName=$trxPath",
    '--settings', $runSettings
)

if ($Filter) {
    $dotnetArgs += @('--filter', $Filter)
}
elseif ($testConfig -and $testConfig.filter) {
    $dotnetArgs += @('--filter', [string]$testConfig.filter)
}

if (-not $NoCoverage) {
    $dotnetArgs += @('--collect', 'XPlat Code Coverage')
}

Write-Host "=== dotnet unit tests @ $RepoRoot ==="
Write-Host ('+ dotnet ' + ($dotnetArgs -join ' '))

& dotnet @dotnetArgs
$exitCode = $LASTEXITCODE

if (-not (Test-Path $trxPath)) {
    $trxFound = Get-ChildItem -Path $absResults -Recurse -Filter '*.trx' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($trxFound) {
        Copy-Item $trxFound.FullName $trxPath -Force
    }
}

if (-not $NoCoverage) {
    $coberturaFound = Get-ChildItem -Path $absResults -Recurse -Filter 'coverage.cobertura.xml' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($coberturaFound) {
        Copy-Item $coberturaFound.FullName $coberturaPath -Force
        Write-Host "OK   cobertura -> $(Get-RelativePath $RepoRoot $coberturaPath)"
    }
    else {
        Write-Host 'WARN no coverage.cobertura.xml — add coverlet.collector to test projects or use SDK 8+' -ForegroundColor Yellow
    }
}

$coverageSummary = @{}
if (Test-Path $coberturaPath) {
    [xml]$covXml = Get-Content $coberturaPath
    $root = $covXml.coverage
    if ($root) {
        $lineRate = [double]$root.'line-rate'
        $branchRate = [double]$root.'branch-rate'
        $coverageSummary = @{
            lineCoveragePercent   = [math]::Round($lineRate * 100, 2)
            branchCoveragePercent = [math]::Round($branchRate * 100, 2)
            linesValid            = [int]$root.'lines-valid'
            linesCovered          = [int]$root.'lines-covered'
            branchesValid         = [int]$root.'branches-valid'
            branchesCovered       = [int]$root.'branches-covered'
        }
        Write-Host ("COVERAGE line={0}% branch={1}% ({2}/{3} lines)" -f `
            $coverageSummary.lineCoveragePercent, `
            $coverageSummary.branchCoveragePercent, `
            $coverageSummary.linesCovered, `
            $coverageSummary.linesValid)
    }
}

$summaryPath = Write-AzureDevOpsResults -RepoRoot $RepoRoot -ResultsDir $ResultsDir `
    -TrxPath $trxPath -CoberturaPath $coberturaPath -ExitCode $exitCode -CoverageSummary $coverageSummary

Write-Host "OK   Azure DevOps manifest -> $(Get-RelativePath $RepoRoot $summaryPath)"
Get-Content $summaryPath -Raw | Write-Host

if ($exitCode -ne 0) {
    Write-Host 'FAIL: unit tests failed' -ForegroundColor Red
    exit $exitCode
}

Write-Host 'PASS: unit tests OK'
exit 0
