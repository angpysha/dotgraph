# configure-azure-devops.ps1 — apply manifest pr.org / pr.project to az devops defaults.
param(
    [string]$Organization = '',
    [string]$Project = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/azure-devops-common.ps1"

$repoRoot = Find-RepoRoot
Ensure-AzureDevOpsExtension

if (-not (Test-AzLoggedIn)) {
    throw 'Azure CLI not logged in. Run: az login'
}

$ctx = Resolve-DevOpsContext -RepoRoot $repoRoot -Organization $Organization -Project $Project
$org = $ctx.organization
$project = $ctx.project

if ([string]::IsNullOrWhiteSpace($org)) {
    throw 'Organization required. Set pipeline.manifest.json pr.org or pass -Organization'
}
if ([string]::IsNullOrWhiteSpace($project)) {
    throw 'Project required. Set pipeline.manifest.json pr.project or pass -Project'
}

$configureArgs = @(
    'devops', 'configure',
    '--defaults', "organization=$org", "project=$project"
)

if ($DryRun) {
    Write-Host "DRY RUN: az $($configureArgs -join ' ')"
    exit 0
}

Invoke-AzDevOpsCommand -AzArgs $configureArgs
Write-Host "OK   az devops defaults -> organization=$org project=$project"
exit 0
