# ensure-azure-devops.ps1 — verify Azure CLI + azure-devops extension + auth.
param(
    [switch]$InstallExtension,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/azure-devops-common.ps1"

$repoRoot = Find-RepoRoot
$issues = [System.Collections.Generic.List[string]]::new()
$info = [ordered]@{ ok = $true; repoRoot = $repoRoot; checks = [ordered]@{} }

if (-not (Test-AzCliInstalled)) {
    $issues.Add('Azure CLI (az) not found. Install: https://learn.microsoft.com/cli/azure/install-azure-cli')
    $info.checks.azCli = $false
}
else {
    $version = (az version --query '"azure-cli"' -o tsv 2>$null)
    $info.checks.azCli = $true
    $info.checks.azVersion = $version
}

if ($info.checks.azCli) {
    if (-not (Test-AzureDevOpsExtension)) {
        if ($InstallExtension) {
            Ensure-AzureDevOpsExtension
            $info.checks.extension = $true
        }
        else {
            $issues.Add('azure-devops extension missing. Run: pwsh ensure-azure-devops.ps1 -InstallExtension')
            $info.checks.extension = $false
        }
    }
    else {
        $info.checks.extension = $true
    }
}

if ($info.checks.azCli) {
    $info.checks.loggedIn = Test-AzLoggedIn
    $info.checks.devOpsPat = -not [string]::IsNullOrWhiteSpace($env:AZURE_DEVOPS_EXT_PAT)
    if (-not $info.checks.devOpsPat) {
        $issues.Add('AZURE_DEVOPS_EXT_PAT not set — macOS: run azdo-login; CI: pipeline secret (see SKILL.md Authentication)')
    }
    if (-not $info.checks.loggedIn) {
        $info.checks.azAccountLogin = $false
        # az login is optional for DevOps when PAT is set; warn only
        if (-not $info.checks.devOpsPat) {
            $issues.Add('az login not active — optional for DevOps if PAT is set via azdo-login')
        }
    }
    else {
        $info.checks.azAccountLogin = $true
    }
}

$ctx = $null
if (Test-Path (Join-Path $repoRoot 'pipeline.manifest.json')) {
    try {
        $ctx = Resolve-DevOpsContext -RepoRoot $repoRoot
        $info.manifest = [ordered]@{
            type         = $ctx.type
            organization = $ctx.organization
            project      = $ctx.project
            repository   = $ctx.repository
            targetBranch = $ctx.targetBranch
        }
        if ($ctx.type -eq 'azure-devops') {
            if ([string]::IsNullOrWhiteSpace($ctx.organization)) {
                $issues.Add('manifest pr.org is empty — set org or run configure-azure-devops.ps1')
            }
            if ([string]::IsNullOrWhiteSpace($ctx.project)) {
                $issues.Add('manifest pr.project is empty — set project or run configure-azure-devops.ps1')
            }
            if ([string]::IsNullOrWhiteSpace($ctx.repository)) {
                $issues.Add('manifest pr.repo is empty — set repository name for PR creation')
            }
        }
    }
    catch {
        $issues.Add($_.Exception.Message)
    }
}

if ($issues.Count -gt 0) {
    $info.ok = $false
    $info.issues = $issues
    if ($Json) {
        $info | ConvertTo-Json -Depth 6
    }
    else {
        foreach ($issue in $issues) { Write-Host "FAIL: $issue" }
    }
    exit 1
}

if ($Json) {
    $info | ConvertTo-Json -Depth 6
}
else {
    Write-Host "PASS: Azure DevOps CLI ready — org=$($ctx.organization) project=$($ctx.project)"
}
exit 0
