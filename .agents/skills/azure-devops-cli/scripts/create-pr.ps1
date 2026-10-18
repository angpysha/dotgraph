# create-pr.ps1 — Phase 10 Azure DevOps PR creation (after human approval only).
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceBranch,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [string]$Description = '',
    [string]$DescriptionFile = '',
    [string]$TargetBranch = '',
    [string]$Repository = '',
    [int[]]$WorkItems = @(),
    [switch]$Draft,
    [switch]$Squash,
    [switch]$DeleteSourceBranch,
    [switch]$Push,
    [switch]$Approved,
    [string]$OutputJson = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/azure-devops-common.ps1"

if (-not $Approved) {
    throw @'
Human approval required before PR creation (Phase 9 gate).
Re-run with -Approved after the human approves closeout.
Never push or open a PR before Phase 9 approval.
'@
}

$repoRoot = Find-RepoRoot
$ctx = Resolve-DevOpsContext -RepoRoot $repoRoot -Repository $Repository

if ($ctx.type -ne 'azure-devops') {
    throw "manifest pr.type is '$($ctx.type)' — expected 'azure-devops'. Use gh pr create for github."
}
if ([string]::IsNullOrWhiteSpace($ctx.repository)) {
    throw 'manifest pr.repo is empty — set repository name in pipeline.manifest.json'
}

Ensure-AzureDevOpsExtension
if (-not (Test-AzLoggedIn)) {
    throw 'Azure CLI not logged in. Run: az login'
}

$target = if ($TargetBranch) { $TargetBranch } else { $ctx.targetBranch }
$body = $Description
if ($DescriptionFile) {
    if (-not (Test-Path $DescriptionFile)) {
        throw "Description file not found: $DescriptionFile"
    }
    $body = Get-Content $DescriptionFile -Raw
}

if ($Push) {
    Write-Host "Pushing branch $SourceBranch..."
    git -C $repoRoot push -u origin $SourceBranch
    if ($LASTEXITCODE -ne 0) {
        throw "git push failed (exit $LASTEXITCODE)"
    }
}

$azArgs = @(
    'repos', 'pr', 'create',
    '--repository', $ctx.repository,
    '--source-branch', $SourceBranch,
    '--target-branch', $target,
    '--title', $Title
)

if ($body) {
    $azArgs += @('--description', $body)
}
if ($Draft) { $azArgs += '--draft' }
if ($Squash) { $azArgs += '--squash' }
if ($DeleteSourceBranch) { $azArgs += '--delete-source-branch' }
if ($WorkItems -and $WorkItems.Count -gt 0) {
    $azArgs += @('--work-items', ($WorkItems -join ' '))
}

$raw = Invoke-AzDevOpsCommand -AzArgs $azArgs -Organization $ctx.organization -Project $ctx.project -Json -CaptureOutput
$pr = $raw | ConvertFrom-Json

$result = [ordered]@{
    schemaVersion = '1'
    provider      = 'azure-devops'
    pullRequestId = $pr.pullRequestId
    url           = $pr.url
    sourceBranch  = $SourceBranch
    targetBranch  = $target
    repository    = $ctx.repository
    organization  = $ctx.organization
    project       = $ctx.project
    title         = $Title
    createdAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

if ($OutputJson) {
    $outPath = if ([IO.Path]::IsPathRooted($OutputJson)) { $OutputJson } else { Join-Path $repoRoot $OutputJson }
    $outDir = Split-Path $outPath -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -Path $outPath -Encoding UTF8
    Write-Host "OK   PR manifest -> $outPath"
}

Write-Host "OK   Pull request #$($pr.pullRequestId) -> $($pr.url)"
Write-Output $pr.url
exit 0
