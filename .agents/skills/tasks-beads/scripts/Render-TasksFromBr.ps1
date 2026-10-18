<#
.SYNOPSIS
  Render specs/<feature>/tasks.md as a projection of the canonical br task graph.

.DESCRIPTION
  Contract: specs/011-speckit-tasks-beads/contracts/tasks-md-projection.md
  Asserts beads readiness first. Never imports markdown into br. Never uses bd.

.PARAMETER FeatureLabel
  Label scoping feature issues (e.g. speckit:011-speckit-tasks-beads).

.PARAMETER OutFile
  Destination tasks.md path.

.PARAMETER FeatureTitle
  Title line for the document.

.PARAMETER WorkingDirectory
  Repo root (default: current directory).

.PARAMETER SkipReadyAssert
  Skip Assert-BeadsReady.ps1 (not recommended).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FeatureLabel,

    [Parameter(Mandatory = $true)]
    [string]$OutFile,

    [string]$FeatureTitle = 'Feature tasks',

    [string]$WorkingDirectory = (Get-Location).Path,

    [switch]$SkipReadyAssert
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AssertScriptPath {
    $here = $PSScriptRoot
    return (Join-Path $here 'Assert-BeadsReady.ps1')
}

function ConvertFrom-BrJson {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    return ($Text | ConvertFrom-Json)
}

function Get-IssueList {
    param([string]$Label)
    # Include closed so projection reflects completion state
    $raw = & br list -l $Label -a --limit 0 --json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "br list failed for label '$Label': $raw"
    }
    $parsed = ConvertFrom-BrJson $raw
    if ($null -eq $parsed) { return @() }
    if ($parsed.PSObject.Properties.Name -contains 'issues') {
        return @($parsed.issues)
    }
    if ($parsed -is [System.Array]) { return @($parsed) }
    return @($parsed)
}

function Get-ReadyIdSet {
    $raw = & br ready --limit 0 --json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        return [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
    $parsed = ConvertFrom-BrJson $raw
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $items = @()
    if ($null -eq $parsed) { return $set }
    if ($parsed -is [System.Array]) { $items = @($parsed) }
    elseif ($parsed.PSObject.Properties.Name -contains 'issues') { $items = @($parsed.issues) }
    else { $items = @($parsed) }
    foreach ($i in $items) {
        if ($i.id) { [void]$set.Add([string]$i.id) }
    }
    return $set
}

function Get-DependsOnIds {
    param([string]$IssueId)
    $raw = & br dep list $IssueId --direction down --format json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { return @() }
    try {
        $parsed = ConvertFrom-BrJson $raw
    } catch {
        return @()
    }
    if ($null -eq $parsed) { return @() }
    $rows = if ($parsed -is [System.Array]) { @($parsed) } else { @($parsed) }
    $ids = @()
    foreach ($r in $rows) {
        $depType = ''
        if ($r.PSObject.Properties.Name -contains 'type') { $depType = [string]$r.type }
        # Skip pure parent-child for Mermaid blockers; keep blocking deps
        if ($depType -eq 'parent-child') { continue }
        if ($r.PSObject.Properties.Name -contains 'depends_on_id' -and $r.depends_on_id) {
            $ids += [string]$r.depends_on_id
        }
    }
    return $ids
}

function Get-FriendlyId {
    param([string]$Title, [int]$Index)
    if ($Title -match '\b(T\d{3})\b') { return $Matches[1] }
    return ('T{0:D3}' -f $Index)
}

Push-Location $WorkingDirectory
try {
    if (-not $SkipReadyAssert) {
        $assert = Get-AssertScriptPath
        & pwsh -NoProfile -File $assert -WorkingDirectory $WorkingDirectory
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    $issues = @(Get-IssueList -Label $FeatureLabel)
    if ($issues.Count -eq 0) {
        Write-Error "No br issues found with label '$FeatureLabel'. Create the graph before rendering."
        exit 2
    }

    $ready = Get-ReadyIdSet
    $sorted = $issues | Sort-Object { $_.id }

    $depsById = @{}
    $allIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($iss in $sorted) {
        [void]$allIds.Add([string]$iss.id)
        $depsById[[string]$iss.id] = @(Get-DependsOnIds -IssueId ([string]$iss.id))
    }

    # Parallel batch: ready issues that do not depend on another ready in-scope issue
    $parallelIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($iss in $sorted) {
        $id = [string]$iss.id
        $st = [string]$iss.status
        if ($st -eq 'closed') { continue }
        if (-not $ready.Contains($id)) { continue }
        $blockedByPeer = $false
        foreach ($d in $depsById[$id]) {
            if ($allIds.Contains($d) -and $ready.Contains($d)) { $blockedByPeer = $true; break }
        }
        if (-not $blockedByPeer) { [void]$parallelIds.Add($id) }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Tasks: $FeatureTitle")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('> **Authority:** beads rust (`br`) is the canonical task graph. This file is a **generated projection**. Do not reverse-sync silent markdown edits into `br`. Never use `bd`.')
    [void]$sb.AppendLine(">")
    [void]$sb.AppendLine("> Feature label: ``$FeatureLabel``")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Parallel execution')
    [void]$sb.AppendLine()
    if ($parallelIds.Count -eq 0) {
        [void]$sb.AppendLine('_No parallel-ready batch right now (check `br ready`)._')
    } else {
        [void]$sb.AppendLine('Tasks marked `[P]` are currently ready and mutually unblocked per `br`:')
        [void]$sb.AppendLine()
        foreach ($readyId in ($parallelIds | Sort-Object)) {
            [void]$sb.AppendLine("- ``$readyId``")
        }
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Task checklist')
    [void]$sb.AppendLine()

    $idx = 1
    foreach ($iss in $sorted) {
        $id = [string]$iss.id
        $title = [string]$iss.title
        $status = [string]$iss.status
        $checked = if ($status -eq 'closed') { 'x' } else { ' ' }
        $p = if ($parallelIds.Contains($id)) { ' [P]' } else { '' }
        $friendly = Get-FriendlyId -Title $title -Index $idx
        $desc = $title
        if ($iss.description) {
            $first = ([string]$iss.description -split "`n")[0].Trim()
            if ($first -and $first -ne $title) { $desc = "$title — $first" }
        }
        [void]$sb.AppendLine("- [$checked]$p $friendly ``$id`` $desc")
        $idx++
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Dependency graph')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('```mermaid')
    [void]$sb.AppendLine('flowchart TD')

    function Escape-MermaidLabel([string]$s) {
        return ($s -replace '["\[\]]', '' -replace '\s+', ' ').Trim()
    }

    $nodeKeys = @{}
    $n = 0
    foreach ($iss in $sorted) {
        $n++
        $key = "N$n"
        $nodeKeys[[string]$iss.id] = $key
        $label = Escape-MermaidLabel ("{0}: {1}" -f $iss.id, $iss.title)
        [void]$sb.AppendLine("  $key[`"$label`"]")
    }

    foreach ($iss in $sorted) {
        $id = [string]$iss.id
        $toKey = $nodeKeys[$id]
        foreach ($dep in $depsById[$id]) {
            if (-not $nodeKeys.ContainsKey($dep)) { continue }
            # dep --> id  means id depends on dep (dep must finish first)
            $fromKey = $nodeKeys[$dep]
            [void]$sb.AppendLine("  $fromKey --> $toKey")
        }
    }

    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('_Generated by core/skills/tasks-beads/scripts/Render-TasksFromBr.ps1_')

    $absOut = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $WorkingDirectory $OutFile }
    $parent = Split-Path -Parent $absOut
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($absOut, $sb.ToString())
    Write-Host "Wrote projection: $absOut ($($sorted.Count) issues)"
    exit 0
}
finally {
    Pop-Location
}
