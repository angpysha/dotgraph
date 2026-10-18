# install-editorconfig.ps1 — interactive EditorConfig installer for multi-stack repos.
param(
    [string[]]$Stacks = @(),
    [switch]$Interactive,
    [switch]$DetectOnly,
    [switch]$Force,
    [switch]$Merge,
    [string]$OutputPath = '.editorconfig'
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

function Get-SkillRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-Catalog {
    $path = Join-Path (Get-SkillRoot) 'catalog.json'
    if (-not (Test-Path $path)) { throw "catalog.json not found at $path" }
    return Get-Content $path -Raw | ConvertFrom-Json
}

function Test-RepoSignal {
    param([string]$RepoRoot, [string]$Signal)
    if ($Signal -match '[\*\?]') {
        $glob = $Signal
        $hits = Get-ChildItem -Path $RepoRoot -Recurse -Depth 5 -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|bin|obj|target|build|\.dart_tool)[\\/]' } |
            Where-Object { $_.Name -like ($glob -replace '\*', '*') -or $_.Name -eq ($glob -replace '\*', '') }
        if ($hits) { return $true }
        # glob path style e.g. lib/main.dart
        $parts = $Signal -split '/'
        if ($parts.Count -gt 1) {
            $candidate = Join-Path $RepoRoot $Signal
            if (Test-Path $candidate) { return $true }
        }
        return $false
    }

    $lower = $Signal.ToLowerInvariant()
    if (Test-Path (Join-Path $RepoRoot $Signal)) { return $true }

    # Search file names and shallow content for keywords (package.json, pubspec.yaml)
    $nameHits = Get-ChildItem -Path $RepoRoot -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|bin|obj|target|build|\.dart_tool)[\\/]' } |
        Where-Object { $_.Name -eq $Signal -or $_.Name -like $Signal }
    if ($nameHits) { return $true }

    if ($lower -match '^[\w\.@\-]+$' -and $lower -notmatch '\.') {
        $textFiles = @('package.json', 'pubspec.yaml', 'Cargo.toml', 'angular.json', 'svelte.config.js', 'svelte.config.ts')
        foreach ($tf in $textFiles) {
            $fp = Get-ChildItem -Path $RepoRoot -Recurse -Depth 4 -Filter $tf -File -ErrorAction SilentlyContinue |
                Select-Object -First 3
            foreach ($f in $fp) {
                $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
                if ($content -and $content.ToLowerInvariant().Contains($lower)) { return $true }
            }
        }
    }
    return $false
}

function Get-DetectedStacks {
    param($Catalog, [string]$RepoRoot)
    $detected = [System.Collections.Generic.List[string]]::new()
    foreach ($stack in $Catalog.stacks) {
        $matched = $false
        foreach ($sig in $stack.signals) {
            if (Test-RepoSignal -RepoRoot $RepoRoot -Signal ([string]$sig)) {
                $matched = $true
                break
            }
        }
        if (-not $matched -and $stack.signals_extra) {
            foreach ($sig in $stack.signals_extra) {
                if (Test-RepoSignal -RepoRoot $RepoRoot -Signal ([string]$sig)) {
                    $matched = $true
                    break
                }
            }
        }
        if ($matched) { $detected.Add([string]$stack.id) }
    }
    return $detected | Select-Object -Unique
}

function Read-TemplateContent {
    param([string]$TemplateName)
    $path = Join-Path (Join-Path (Get-SkillRoot) 'templates') ($TemplateName + '.editorconfig')
    if (-not (Test-Path $path)) {
        Write-Warning "template missing: $TemplateName"
        return ''
    }
    return (Get-Content $path -Raw).TrimEnd()
}

function Get-TemplateNamesForStacks {
    param($Catalog, [string[]]$StackIds)
    $templates = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $StackIds) {
        $stack = $Catalog.stacks | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if (-not $stack) {
            Write-Warning "unknown stack: $id"
            continue
        }
        foreach ($t in $stack.templates) {
            if (-not $templates.Contains([string]$t)) {
                $templates.Add([string]$t)
            }
        }
    }
    return $templates
}

function Get-MarkerBlock {
    param([string]$MarkerId, [string]$Content)
    return ($Content -split "`n" | Where-Object { $_ -match "editorconfig-install:$([regex]::Escape($MarkerId))" }).Count -ge 2
}

function Invoke-InteractiveSelection {
    param($Catalog, [string[]]$Detected, [string[]]$Preselected)
    Write-Host ''
    Write-Host '=== EditorConfig stack picker (interactive) ===' -ForegroundColor Cyan
    Write-Host 'Enter numbers separated by commas, stack ids, or press Enter for detected defaults.'
    Write-Host ''

    $i = 1
    $indexMap = @{}
    foreach ($stack in $Catalog.stacks) {
        $flag = ''
        if ($Detected -contains $stack.id) { $flag = ' [detected]' }
        if ($Preselected -contains $stack.id) { $flag += ' [selected]' }
        Write-Host ("  {0,2}. {1,-12} {2}{3}" -f $i, $stack.id, $stack.name, $flag)
        Write-Host ("      {0}" -f $stack.description)
        $indexMap[[string]$i] = [string]$stack.id
        $i++
    }
    Write-Host ''
    $answer = Read-Host 'Stacks to install'
    if ([string]::IsNullOrWhiteSpace($answer)) {
        if ($Preselected.Count -gt 0) { return $Preselected }
        if ($Detected.Count -gt 0) { return $Detected }
        throw 'No stacks selected.'
    }

    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ($answer -split '[,\s]+')) {
        $p = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($indexMap.ContainsKey($p)) {
            $selected.Add($indexMap[$p])
        }
        elseif ($Catalog.stacks.id -contains $p) {
            $selected.Add($p)
        }
        else {
            Write-Warning "ignored unknown selection: $p"
        }
    }
    if ($selected.Count -eq 0) { throw 'No valid stacks selected.' }
    return $selected | Select-Object -Unique
}

function Build-EditorConfigContent {
    param([string[]]$TemplateNames)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $TemplateNames) {
        $content = Read-TemplateContent $name
        if ($content) { $parts.Add($content) }
    }
    return ($parts -join "`n`n") + "`n"
}

function Merge-IntoExisting {
    param([string]$ExistingPath, [string]$NewContent, [string[]]$TemplateNames)
    $existing = Get-Content $ExistingPath -Raw
    $merged = $existing.TrimEnd() + "`n`n"
    foreach ($name in $TemplateNames) {
        if (Get-MarkerBlock -MarkerId $name -Content $existing) {
            Write-Host "SKIP section already present: $name"
            continue
        }
        $block = Read-TemplateContent $name
        if ($name -eq 'base') { continue } # never merge root block twice
        if ($block) {
            $merged += $block + "`n`n"
            Write-Host "ADD  section: $name"
        }
    }
    return $merged.TrimEnd() + "`n"
}

# --- main ---
$RepoRoot = Find-RepoRoot
Set-Location $RepoRoot
$Catalog = Get-Catalog
$detected = @(Get-DetectedStacks -Catalog $Catalog -RepoRoot $RepoRoot)

if ($DetectOnly) {
    $result = [ordered]@{
        repoRoot = $RepoRoot
        detected = $detected
        available = @($Catalog.stacks | ForEach-Object { $_.id })
    }
    $result | ConvertTo-Json | Write-Host
    exit 0
}

$selected = @($Stacks)
if ($Interactive -or $selected.Count -eq 0) {
    $selected = @(Invoke-InteractiveSelection -Catalog $Catalog -Detected $detected -Preselected $selected)
}

$templateNames = @(Get-TemplateNamesForStacks -Catalog $Catalog -StackIds $selected)
if ($templateNames.Count -eq 0) {
    Write-Host 'FAIL: no templates for selected stacks' -ForegroundColor Red
    exit 1
}

$outFile = Join-Path $RepoRoot $OutputPath
$content = Build-EditorConfigContent -TemplateNames $templateNames

if (Test-Path $outFile) {
    if ($Merge) {
        $content = Merge-IntoExisting -ExistingPath $outFile -NewContent $content -TemplateNames $templateNames
        Write-Host "MERGE -> $OutputPath"
    }
    elseif ($Force) {
        Write-Host "OVERWRITE -> $OutputPath"
    }
    else {
        Write-Host "FAIL: $OutputPath exists. Use -Merge or -Force." -ForegroundColor Red
        exit 2
    }
}
else {
    Write-Host "CREATE -> $OutputPath"
}

Set-Content -Path $outFile -Value $content -Encoding UTF8 -NoNewline

$report = [ordered]@{
    schemaVersion = '1'
    output        = $OutputPath
    stacks        = $selected
    templates     = $templateNames
    detected      = $detected
}
$reportPath = Join-Path $RepoRoot '.agents/editorconfig-install-report.json'
if (-not (Test-Path (Split-Path $reportPath -Parent))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $reportPath -Parent) | Out-Null
}
$report | ConvertTo-Json | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'Installed stacks:' ($selected -join ', ')
Write-Host "Report: .agents/editorconfig-install-report.json"
Write-Host 'PASS: EditorConfig install OK' -ForegroundColor Green
exit 0
