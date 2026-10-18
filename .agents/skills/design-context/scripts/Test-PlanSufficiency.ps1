#!/usr/bin/env pwsh
# Readonly sufficiency check for design-context critique.
# Always exits 0 unless the script itself cannot run (unreadable paths).
[CmdletBinding()]
param(
    [Parameter()]
    [string]$FeatureDir
)

$ErrorActionPreference = 'Stop'

function Find-RepoRoot {
    param([string]$Start = (Get-Location).Path)
    $current = (Resolve-Path -LiteralPath $Start).Path
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $current '.specify') -PathType Container) {
            return $current
        }
        $parent = Split-Path $current -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) {
            return $null
        }
        $current = $parent
    }
}

function Get-FeatureDirFromJson {
    param([string]$RepoRoot)
    $jsonPath = Join-Path $RepoRoot '.specify/feature.json'
    if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
        return $null
    }
    try {
        $obj = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        $rel = [string]$obj.feature_directory
        if ([string]::IsNullOrWhiteSpace($rel)) { return $null }
        if ([System.IO.Path]::IsPathRooted($rel)) { return $rel }
        return (Join-Path $RepoRoot $rel)
    } catch {
        return $null
    }
}

function Test-OpenBlockers {
    param([string]$PackPath)
    if (-not (Test-Path -LiteralPath $PackPath -PathType Leaf)) {
        return $false
    }
    $text = Get-Content -LiteralPath $PackPath -Raw
    if ($text -notmatch '(?im)^##\s+Open blockers') {
        return $false
    }
    $after = [regex]::Split($text, '(?im)^##\s+Open blockers[^\n]*\n', 2)
    if ($after.Count -lt 2) { return $false }
    $section = $after[1]
    $next = [regex]::Split($section, '(?im)^##\s+', 2)
    $body = $next[0]
    foreach ($line in ($body -split '\r?\n')) {
        if ($line -match '^\s*-\s+') {
            if ($line -notmatch 'deferred-by-operator' -and $line -notmatch '(?i)none|empty|n/a') {
                return $true
            }
        }
    }
    return $false
}

$repoRoot = Find-RepoRoot
if (-not $repoRoot) {
    Write-Output 'FEATURE_DIR: (not found)'
    Write-Output 'STATUS: blocked'
    Write-Output 'REASONS:'
    Write-Output '- Spec Kit project root not found (no .specify/)'
    Write-Output 'RECOMMEND: none'
    exit 0
}

$resolvedDir = $null
if (-not [string]::IsNullOrWhiteSpace($FeatureDir)) {
    if ([System.IO.Path]::IsPathRooted($FeatureDir)) {
        $resolvedDir = $FeatureDir
    } else {
        $resolvedDir = Join-Path $repoRoot $FeatureDir
    }
} else {
    $resolvedDir = Get-FeatureDirFromJson -RepoRoot $repoRoot
}

if ([string]::IsNullOrWhiteSpace($resolvedDir) -or -not (Test-Path -LiteralPath $resolvedDir -PathType Container)) {
    Write-Output "FEATURE_DIR: $resolvedDir"
    Write-Output 'STATUS: blocked'
    Write-Output 'REASONS:'
    Write-Output '- feature directory missing (set .specify/feature.json or pass -FeatureDir)'
    Write-Output 'RECOMMEND: none'
    exit 0
}

$absFeature = (Resolve-Path -LiteralPath $resolvedDir).Path
$planPath = Join-Path $absFeature 'plan.md'
$packPath = Join-Path $absFeature 'design-context.md'
$rfcDir = Join-Path $absFeature 'rfcs'
$adrDir = Join-Path $repoRoot 'docs/adr'

Write-Output "FEATURE_DIR: $absFeature"

if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
    Write-Output 'STATUS: blocked'
    Write-Output 'REASONS:'
    Write-Output '- plan.md missing'
    Write-Output 'RECOMMEND: none'
    Write-Output 'HINT: run /speckit.plan first'
    exit 0
}

$reasons = [System.Collections.Generic.List[string]]::new()
$planText = Get-Content -LiteralPath $planPath -Raw

if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
    [void]$reasons.Add('design-context.md missing')
}

if ($planText -match 'NEEDS CLARIFICATION') {
    [void]$reasons.Add('plan.md contains NEEDS CLARIFICATION')
}

if (Test-OpenBlockers -PackPath $packPath) {
    [void]$reasons.Add('open blockers in design-context.md')
}

$hasAdrOrRfc = $false
if (Test-Path -LiteralPath $adrDir -PathType Container) {
    $adrFiles = Get-ChildItem -LiteralPath $adrDir -Filter '*.md' -ErrorAction SilentlyContinue
    if ($adrFiles) { $hasAdrOrRfc = $true }
}
if (Test-Path -LiteralPath $rfcDir -PathType Container) {
    $rfcFiles = Get-ChildItem -LiteralPath $rfcDir -Filter '*.md' -ErrorAction SilentlyContinue
    if ($rfcFiles) { $hasAdrOrRfc = $true }
}

$forkLanguage = $planText -match '(?i)instead of|alternatives considered|we chose|rejected alternative'
$recommendGrill = $forkLanguage -and -not $hasAdrOrRfc -and ($planText -notmatch '(?i)docs/adr/|rfcs/')

if ($reasons.Count -eq 0) {
    Write-Output 'STATUS: sufficient'
    Write-Output 'REASONS:'
    Write-Output '- none'
    Write-Output 'RECOMMEND: none'
    exit 0
}

Write-Output 'STATUS: insufficient'
Write-Output 'REASONS:'
foreach ($r in $reasons) {
    Write-Output "- $r"
}
if ($recommendGrill) {
    Write-Output 'RECOMMEND: scan+grill'
} else {
    Write-Output 'RECOMMEND: scan'
}
exit 0
