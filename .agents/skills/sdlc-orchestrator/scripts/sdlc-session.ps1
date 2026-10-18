# sdlc-session.ps1 — session artifact paths and publish to docs/sdlc
$ErrorActionPreference = 'Stop'

function Find-RepoRoot {
    $cwd = (Get-Location).Path
    if ((Test-Path (Join-Path $cwd 'pipeline.manifest.json')) -or
        (Test-Path (Join-Path $cwd '.git')) -or
        (Test-Path (Join-Path $cwd '.agents/pipeline.home'))) {
        return (Resolve-Path $cwd).Path
    }
    $dir = $PSScriptRoot
    while ($dir -and $dir -ne '/') {
        if ((Test-Path (Join-Path $dir 'pipeline.manifest.json')) -or
            (Test-Path (Join-Path $dir '.git'))) {
            return (Resolve-Path $dir).Path
        }
        $dir = Split-Path $dir -Parent
    }
    return (Resolve-Path (Join-Path $PSScriptRoot '../../../../')).Path
}

function Get-SessionDir {
    param([string]$Session, [string]$RepoRoot = '')
    if (-not $RepoRoot) { $RepoRoot = Find-RepoRoot }
    return Join-Path $RepoRoot "_code_agent/$Session"
}

function Get-SessionSdlcRoot {
    param([string]$Session, [string]$RepoRoot = '')
    return Join-Path (Get-SessionDir -Session $Session -RepoRoot $RepoRoot) 'artifacts/sdlc'
}

function Resolve-SdlcRoots {
    param(
        [string]$Session = '',
        [string]$RepoRoot = ''
    )
    if (-not $RepoRoot) { $RepoRoot = Find-RepoRoot }
    $published = Join-Path $RepoRoot 'docs/sdlc'
    if ($Session) {
        $working = Get-SessionSdlcRoot -Session $Session -RepoRoot $RepoRoot
        return [ordered]@{
            working   = $working
            published = $published
            mode      = 'session'
        }
    }
    return [ordered]@{
        working   = $published
        published = $published
        mode      = 'published'
    }
}

function Get-DesignDir {
    param([string]$Session = '')
    $roots = Resolve-SdlcRoots -Session $Session
    return Join-Path $roots.working 'design'
}

function Get-ApiDir {
    param([string]$Session = '')
    $roots = Resolve-SdlcRoots -Session $Session
    return Join-Path $roots.working 'api'
}

function Get-RequirementsDir {
    param([string]$Session = '')
    $roots = Resolve-SdlcRoots -Session $Session
    return Join-Path $roots.working 'requirements'
}

function Get-TestReportsDir {
    param([string]$Session = '')
    $roots = Resolve-SdlcRoots -Session $Session
    return Join-Path $roots.working 'test-reports'
}

function Publish-SdlcArtifacts {
    param(
        [Parameter(Mandatory)][string]$Session,
        [switch]$DryRun,
        [string]$RepoRoot = ''
    )
    if (-not $RepoRoot) { $RepoRoot = Find-RepoRoot }
    $src = Get-SessionSdlcRoot -Session $Session -RepoRoot $RepoRoot
    if (-not (Test-Path $src)) {
        throw "Session SDLC artifacts not found: $src"
    }

    $dst = Join-Path $RepoRoot 'docs/sdlc'
    $copied = [System.Collections.Generic.List[string]]::new()

    Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length).TrimStart([IO.Path]::DirectorySeparatorChar, '/')
        $target = Join-Path $dst $rel
        $targetDir = Split-Path $target -Parent
        if ($DryRun) {
            Write-Host "DRY RUN copy -> $rel"
        }
        else {
            if ($targetDir -and -not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $target -Force
            $copied.Add($rel)
        }
    }

    if ($DryRun) {
        Write-Host "DRY RUN publish from $src to $dst"
    }
    else {
        Write-Host "OK   published $($copied.Count) file(s) from session to docs/sdlc"
        foreach ($rel in $copied) { Write-Host "     $rel" }
    }
    return $copied
}
