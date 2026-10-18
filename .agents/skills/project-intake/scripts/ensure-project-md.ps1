# ensure-project-md.ps1 — validate PROJECT.md for adapt (Vision + Stack required).
# Detects greenfield repos (no runtime stack files yet).
#
# Exit codes: 0 = ready | 1 = missing | 2 = incomplete | 3 = greenfield + brief OK
#
# Usage (from repo root):
#   pwsh .agents/skills/project-intake/scripts/ensure-project-md.ps1
#   pwsh .agents/skills/project-intake/scripts/ensure-project-md.ps1 -Json
param(
    [string]$ProjectFile = 'PROJECT.md',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Test-SectionPresent {
    param([string]$Content, [string[]]$HeadingPatterns)
    foreach ($pat in $HeadingPatterns) {
        if ($Content -match "(?m)^#{1,3}\s+$pat\s*$") { return $true }
    }
    return $false
}

function Test-SectionHasBody {
    param([string]$Content, [string[]]$HeadingPatterns)
    foreach ($pat in $HeadingPatterns) {
        $m = [regex]::Match($Content, "(?ms)^#{1,3}\s+$pat\s*\r?\n(.*?)(?=^#{1,3}\s|\z)")
        if ($m.Success) {
            $body = ($m.Groups[1].Value -replace '<!--.*?-->', '' -replace '\s', '')
            if ($body.Length -ge 20) { return $true }
        }
    }
    return $false
}

function Test-GreenfieldRepo {
    $signals = @(
        '*.csproj', '*.fsproj', '*.sln', '*.slnx', 'pubspec.yaml', 'package.json', 'Package.swift',
        '*.xcodeproj', 'Chart.yaml', 'Cargo.toml', 'go.mod', 'pom.xml', 'build.gradle*'
    )
    foreach ($glob in $signals) {
        if (Get-ChildItem -Path . -Filter $glob -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[/\\](\.git|node_modules|\.build|DerivedData|artifacts)[/\\]' } |
            Select-Object -First 1) {
            return $false
        }
    }
    return $true
}

$greenfield = Test-GreenfieldRepo
$result = [ordered]@{
    schemaVersion = '1'
    projectFile   = $ProjectFile
    greenfield    = $greenfield
    ready         = $false
    exitCode      = 1
    issues        = @()
    sections      = [ordered]@{
        vision = $false
        stack  = $false
    }
}

if (-not (Test-Path $ProjectFile)) {
    $result.issues += 'PROJECT.md not found — run project-intake (ask vision + stack, then create file).'
    $result.exitCode = 1
}
else {
    $content = Get-Content $ProjectFile -Raw
    $visionHead = Test-SectionPresent $content @('Vision', 'Main [Ii]dea', 'Overview', 'Summary')
    $stackHead  = Test-SectionPresent $content @('Stack', 'Technology', 'Tech [Ss]tack')
    $visionBody = Test-SectionHasBody $content @('Vision', 'Main [Ii]dea', 'Overview', 'Summary')
    $stackBody  = Test-SectionHasBody $content @('Stack', 'Technology', 'Tech [Ss]tack')

    $result.sections.vision = $visionBody
    $result.sections.stack  = $stackBody

    if (-not $visionHead -or -not $stackHead) {
        $result.issues += 'PROJECT.md must include ## Vision (or Main idea) and ## Stack headings.'
        $result.exitCode = 2
    }
    elseif (-not $visionBody -or -not $stackBody) {
        $result.issues += 'Vision and Stack sections need real content (not just placeholders/comments).'
        $result.exitCode = 2
    }
    else {
        $result.ready = $true
        $result.exitCode = if ($greenfield) { 3 } else { 0 }
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Host "=== project-intake: $ProjectFile ==="
    Write-Host "greenfield: $($result.greenfield)"
    foreach ($issue in $result.issues) { Write-Host "ISSUE: $issue" }
    if ($result.ready) {
        if ($result.exitCode -eq 3) {
            Write-Host 'OK PROJECT.md ready (greenfield — stack-selector should use brief as primary signal).'
        }
        else {
            Write-Host 'OK PROJECT.md ready.'
        }
    }
}

exit $result.exitCode
