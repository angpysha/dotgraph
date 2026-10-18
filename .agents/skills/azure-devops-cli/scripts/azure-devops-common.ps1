# Shared helpers for azure-devops-cli skill scripts.
$ErrorActionPreference = 'Stop'

function Find-RepoRoot {
    $cwd = (Get-Location).Path
    if ((Test-Path (Join-Path $cwd 'pipeline.manifest.json')) -or
        (Test-Path (Join-Path $cwd 'docs/sdlc/requirements')) -or
        (Test-Path (Join-Path $cwd '.git')) -or
        (Test-Path (Join-Path $cwd '.agents/pipeline.home'))) {
        return (Resolve-Path $cwd).Path
    }
    $dir = $PSScriptRoot
    while ($dir -and $dir -ne '/') {
        if ((Test-Path (Join-Path $dir 'pipeline.manifest.json')) -or
            (Test-Path (Join-Path $dir '.git')) -or
            (Test-Path (Join-Path $dir '.agents/pipeline.home'))) {
            return (Resolve-Path $dir).Path
        }
        $dir = Split-Path $dir -Parent
    }
    return (Resolve-Path (Join-Path $PSScriptRoot '../../../../')).Path
}

function Get-ManifestPrConfig {
    param([string]$RepoRoot)
    $manifestPath = Join-Path $RepoRoot 'pipeline.manifest.json'
    if (-not (Test-Path $manifestPath)) {
        throw "pipeline.manifest.json not found at repo root: $RepoRoot"
    }
    $json = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if (-not $json.pr) {
        throw 'pipeline.manifest.json is missing the "pr" section'
    }
    return $json.pr
}

function Format-DevOpsOrgUrl {
    param([string]$Org)
    if ([string]::IsNullOrWhiteSpace($Org)) { return '' }
    if ($Org -match '^https?://') { return $Org.TrimEnd('/') }
    return "https://dev.azure.com/$($Org.Trim('/'))"
}

function Get-DevOpsDefaults {
    $org = ''
    $project = ''
    try {
        $show = az devops configure --list 2>$null
        if ($LASTEXITCODE -eq 0 -and $show) {
            foreach ($line in ($show -split "`n")) {
                if ($line -match '^\s*organization\s*=\s*(.+)$') { $org = $Matches[1].Trim() }
                if ($line -match '^\s*project\s*=\s*(.+)$') { $project = $Matches[1].Trim() }
            }
        }
    }
    catch { }
    return [ordered]@{ organization = $org; project = $project }
}

function Resolve-DevOpsContext {
    param(
        [string]$RepoRoot,
        [string]$Organization = '',
        [string]$Project = '',
        [string]$Repository = ''
    )
    $pr = Get-ManifestPrConfig -RepoRoot $RepoRoot
    $defaults = Get-DevOpsDefaults

    $org = if ($Organization) { Format-DevOpsOrgUrl $Organization }
           elseif ($pr.org) { Format-DevOpsOrgUrl ([string]$pr.org) }
           else { $defaults.organization }

    $project = if ($Project) { $Project }
               elseif ($pr.project) { [string]$pr.project }
               else { $defaults.project }

    $repo = if ($Repository) { $Repository }
            elseif ($pr.repo) { [string]$pr.repo }
            else { '' }

    $targetBranch = if ($pr.target_branch) { [string]$pr.target_branch } else { 'main' }

    return [ordered]@{
        type         = [string]$pr.type
        organization = $org
        project      = $project
        repository   = $repo
        targetBranch = $targetBranch
        branchPrefix = $pr.branch_prefix
    }
}

function Test-AzCliInstalled {
    $cmd = Get-Command az -ErrorAction SilentlyContinue
    return [bool]$cmd
}

function Test-AzureDevOpsExtension {
    $ext = az extension list --query "[?name=='azure-devops'].name" -o tsv 2>$null
    return ($LASTEXITCODE -eq 0) -and (-not [string]::IsNullOrWhiteSpace($ext))
}

function Test-AzLoggedIn {
    $account = az account show -o json 2>$null
    return ($LASTEXITCODE -eq 0) -and (-not [string]::IsNullOrWhiteSpace($account))
}

function Ensure-AzureDevOpsExtension {
    if (Test-AzureDevOpsExtension) { return }
    Write-Host 'Installing Azure DevOps CLI extension (azure-devops)...'
    az extension add --name azure-devops --only-show-errors | Out-Null
    if (-not (Test-AzureDevOpsExtension)) {
        throw 'Failed to install azure-devops extension. Run: az extension add --name azure-devops'
    }
}

function Invoke-AzDevOpsCommand {
    param(
        [string[]]$AzArgs,
        [string]$Organization = '',
        [string]$Project = '',
        [switch]$Json,
        [switch]$CaptureOutput
    )
    $args = [System.Collections.Generic.List[string]]::new()
    $args.AddRange($AzArgs)

    $hasOrg = $false
    $hasProject = $false
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -in '--organization', '-org') { $hasOrg = $true }
        if ($args[$i] -in '--project', '-p') { $hasProject = $true }
    }

    if (-not $hasOrg -and $Organization) {
        $args.Add('--organization')
        $args.Add($Organization)
    }
    if (-not $hasProject -and $Project) {
        $args.Add('--project')
        $args.Add($Project)
    }
    if ($Json) {
        $hasOutput = $false
        for ($i = 0; $i -lt $args.Count; $i++) {
            if ($args[$i] -in '--output', '-o') { $hasOutput = $true }
        }
        if (-not $hasOutput) {
            $args.Add('--output')
            $args.Add('json')
        }
    }

    if ($CaptureOutput) {
        $raw = & az @args 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "az command failed (exit $LASTEXITCODE): az $($args -join ' ')`n$raw"
        }
        return ($raw | Out-String).TrimEnd()
    }

    & az @args
    if ($LASTEXITCODE -ne 0) {
        throw "az command failed (exit $LASTEXITCODE): az $($args -join ' ')"
    }
}

function Invoke-AzDevOpsJson {
    param(
        [string[]]$AzArgs,
        [string]$Organization = '',
        [string]$Project = '',
        [string]$Query = ''
    )
    $args = [System.Collections.Generic.List[string]]::new()
    $args.AddRange($AzArgs)

    if ($Query) {
        $hasQuery = $false
        for ($i = 0; $i -lt $args.Count; $i++) {
            if ($args[$i] -eq '--query') { $hasQuery = $true }
        }
        if (-not $hasQuery) {
            $args.Add('--query')
            $args.Add($Query)
        }
    }

    $raw = Invoke-AzDevOpsCommand -AzArgs $args -Organization $Organization -Project $Project -Json -CaptureOutput
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return 'null'
    }
    return $raw
}

function Get-AgenticToolInvoker {
    $repoRoot = Find-RepoRoot
    foreach ($cfg in @('Debug', 'Release')) {
        $dll = Join-Path $repoRoot "src/Agentic.Tool/bin/$cfg/net10.0/Agentic.Tool.dll"
        if (Test-Path $dll) {
            $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
            if ($dotnet) {
                return @{ FileName = $dotnet.Source; PrefixArgs = @('exec', $dll) }
            }
        }
    }
    $cmd = Get-Command agentic-tool -ErrorAction SilentlyContinue
    if ($cmd) {
        return @{ FileName = $cmd.Source; PrefixArgs = @() }
    }
    return $null
}

function ConvertTo-Toon {
    param(
        [string]$Json,
        [switch]$Stats
    )
    $statsArg = if ($Stats) { @('--stats') } else { @() }
    $invoker = Get-AgenticToolInvoker

    if ($invoker) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $invoker.FileName
        $psi.Arguments = ($invoker.PrefixArgs + @('toon', 'encode', '--stdin') + $statsArg) -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Write($Json)
        $proc.StandardInput.Close()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        if ($stderr) { Write-Host $stderr.Trim() }
        if ($proc.ExitCode -eq 0) {
            return $stdout.TrimEnd()
        }
        if ($invoker.PrefixArgs.Count -eq 0) {
            Write-Warning 'agentic-tool toon encode failed; trying Python fallback'
        }
        else {
            throw "agentic-tool toon encode failed (exit $($proc.ExitCode))"
        }
    }

    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
    if ($python) {
        $script = Join-Path $PSScriptRoot 'json-to-toon.py'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $python.Source
        $psi.Arguments = (@($script, '--stdin') + $statsArg) -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Write($Json)
        $proc.StandardInput.Close()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        if ($stderr) { Write-Host $stderr.Trim() }
        if ($proc.ExitCode -ne 0) {
            throw "json-to-toon.py failed (exit $($proc.ExitCode))"
        }
        return $stdout.TrimEnd()
    }

    throw 'No TOON encoder found. Install agentic-tool or: pip install toon-format'
}

function Get-RecipeCatalog {
    $catalogPath = Join-Path $PSScriptRoot '../catalog/recipes.json'
    if (-not (Test-Path $catalogPath)) {
        throw "Recipe catalog not found: $catalogPath"
    }
    return Get-Content $catalogPath -Raw | ConvertFrom-Json
}

function Expand-RecipeTemplate {
    param(
        [string]$Template,
        [hashtable]$Vars
    )
    $result = $Template
    foreach ($key in $Vars.Keys) {
        $result = $result -replace "\{$key\}", [string]$Vars[$key]
    }
    if ($result -match '\{[a-zA-Z]+\}') {
        throw "Missing recipe variable(s) in: $result"
    }
    return $result
}
