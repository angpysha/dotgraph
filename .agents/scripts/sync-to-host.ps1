# sync-to-host.ps1 — project .agents/ into agent-host folders (pwsh).
# Usage: pwsh -File sync-to-host.ps1 [TARGET_DIR] [cursor|claude|windsurf|all|auto|manual]
param(
    [string]$Target = (Get-Location).Path,
    [string]$AgentHost = 'auto'
)

. (Join-Path $PSScriptRoot 'lib/PipelineScripts.ps1')

$Target = (Resolve-Path $Target).Path
$Src = Join-Path $Target '.agents'

if (-not (Test-Path $Src)) {
    Write-Error "$Src not found — run 'agentic-tool install' first"
    exit 1
}

function Get-DetectedHosts {
    $hosts = [System.Collections.Generic.List[string]]::new()
    if (Test-Path (Join-Path $Target '.cursor')) { $hosts.Add('cursor') }
    if ((Test-Path (Join-Path $Target '.claude')) -or (Test-Path (Join-Path $Target 'CLAUDE.md'))) {
        $hosts.Add('claude')
    }
    if (Test-Path (Join-Path $Target '.windsurf')) { $hosts.Add('windsurf') }
    if ($hosts.Count -eq 0) { $hosts.Add('cursor') }
    return $hosts
}

function Sync-Subtree {
    param([string]$SubDir, [string]$DestRoot, [bool]$UseLinks)
    $source = Join-Path $Src $SubDir
    if (-not (Test-Path $source)) { return }
    $destination = Join-Path $DestRoot $SubDir
    if ($UseLinks) {
        Write-Host "sync -> $destination (link)"
        Link-Tree $source $destination
    }
    else {
        Write-Host "sync -> $destination (copy)"
        Copy-Tree $source $destination
    }
}

function Sync-Cursor {
    param([bool]$UseLinks)
    $destRoot = Join-Path $Target '.cursor'
    Sync-Subtree 'agents' $destRoot $UseLinks
    Sync-Subtree 'skills' $destRoot $UseLinks
    Sync-Subtree 'rules' $destRoot $UseLinks
}

function Sync-Claude {
    param([bool]$UseLinks)
    $destRoot = Join-Path $Target '.claude'
    Sync-Subtree 'agents' $destRoot $UseLinks
    Sync-Subtree 'skills' $destRoot $UseLinks
    Sync-Subtree 'rules' $destRoot $UseLinks
}

function Sync-Windsurf {
    param([bool]$UseLinks)
    $destRoot = Join-Path $Target '.windsurf'
    Sync-Subtree 'agents' $destRoot $UseLinks
    Sync-Subtree 'skills' $destRoot $UseLinks
}

function Invoke-HostSync {
    param([string]$Name, [bool]$UseLinks)
    switch ($Name) {
        'cursor' { Sync-Cursor -UseLinks $UseLinks }
        'claude' { Sync-Claude -UseLinks $UseLinks }
        'windsurf' { Sync-Windsurf -UseLinks $UseLinks }
        default { Write-Warning "unknown host: $Name" }
    }
}

switch ($AgentHost) {
    'auto' {
        $detected = Get-DetectedHosts
        $useLinks = $detected.Count -gt 1
        foreach ($h in $detected) { Invoke-HostSync $h $useLinks }
    }
    'all' {
        Sync-Cursor -UseLinks $true
        Sync-Claude -UseLinks $true
        Sync-Windsurf -UseLinks $true
    }
    'manual' {
        Write-Host 'INFO manual host — no projection ( .agents/ only )'
    }
    { $_ -in @('cursor', 'claude', 'windsurf') } {
        Invoke-HostSync $AgentHost $false
    }
    default {
        Write-Error "unknown host: $AgentHost"
        exit 1
    }
}

Write-Host "OK sync complete ($AgentHost)"
