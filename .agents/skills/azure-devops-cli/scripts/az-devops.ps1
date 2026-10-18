# az-devops.ps1 — passthrough to `az` with org/project defaults from pipeline.manifest.json.
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AzArguments
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/azure-devops-common.ps1"

if (-not $AzArguments -or $AzArguments.Count -eq 0) {
    Write-Host @'
Usage: pwsh az-devops.ps1 <az-subcommand> [args...]

Examples:
  pwsh az-devops.ps1 repos pr list --status active
  pwsh az-devops.ps1 pipelines run --name "CI" --branch main
  pwsh az-devops.ps1 boards work-item show --id 12345
  pwsh az-devops.ps1 devops project list

Org/project defaults come from pipeline.manifest.json pr.* and az devops configure.
'@
    exit 1
}

if (-not (Test-AzCliInstalled)) {
    throw 'Azure CLI (az) not found'
}
Ensure-AzureDevOpsExtension

$repoRoot = Find-RepoRoot
$ctx = Resolve-DevOpsContext -RepoRoot $repoRoot

Invoke-AzDevOpsCommand -AzArgs $AzArguments -Organization $ctx.organization -Project $ctx.project
exit $LASTEXITCODE
