# Shared helpers for pipeline PowerShell scripts (pwsh 7+).
# Dot-source: . (Join-Path $PSScriptRoot '..\lib\PipelineScripts.ps1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRootFromScript {
    param([int]$LevelsUp = 4)
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt $LevelsUp; $i++) {
        $dir = Split-Path $dir -Parent
    }
    return (Resolve-Path $dir).Path
}

function Read-ManifestValue {
    param(
        [string]$ManifestPath = 'pipeline.manifest.json',
        [string[]]$Keys
    )
    if (-not (Test-Path $ManifestPath)) { return '' }
    $json = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    $cur = $json
    foreach ($k in $Keys) {
        if ($null -eq $cur) { return '' }
        $cur = $cur.$k
    }
    if ($null -eq $cur) { return '' }
    return [string]$cur
}

function Resolve-GateScriptPath {
    param([string]$Path)
    if (Test-Path $Path) { return (Resolve-Path $Path).Path }
    return $Path
}

function Test-GateScriptReady {
    param([string]$Path)
    $resolved = Resolve-GateScriptPath $Path
    if (-not (Test-Path $resolved)) { return $false }
    return $true
}

function Copy-Tree {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludeDirNames = @('available', 'archive')
    )
    if (-not (Test-Path $Source)) { return }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    # Merge copy: update/overwrite paths present in Source; NEVER delete destination-only
    # children (preserves host-only user skills/agents/hooks). Do not use robocopy /MIR.
    if (Get-Command robocopy -ErrorAction SilentlyContinue) {
        $xd = @()
        foreach ($name in $ExcludeDirNames) { $xd += '/XD'; $xd += $name }
        # /E copy subdirs including empty; /XO optional — use plain /E without /MIR
        & robocopy $Source $Destination /E /NFL /NDL /NJH /NJS /NC /NS /XO @xd | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit $LASTEXITCODE" }
        return
    }

    Get-ChildItem -Path $Source -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSIsContainer -and ($_.Name -in $ExcludeDirNames)) { return }
        $destPath = Join-Path $Destination $_.Name
        if ($_.PSIsContainer) {
            Copy-Tree -Source $_.FullName -Destination $destPath -ExcludeDirNames $ExcludeDirNames
        }
        else {
            Copy-Item -Path $_.FullName -Destination $destPath -Force
        }
    }
}

function Link-Tree {
    param(
        [string]$Source,
        [string]$Destination
    )
    if (-not (Test-Path $Source)) { return }
    $parent = Split-Path $Destination -Parent
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    if (Test-Path $Destination) {
        $item = Get-Item $Destination -Force
        if (-not $item.LinkType -and $item.PSIsContainer) {
            $srcNames = @(Get-ChildItem -Path $Source -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
            $extras = @(
                Get-ChildItem -Path $Destination -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notin $srcNames -and $_.Name -notin @('available', 'archive') }
            )
            if ($extras.Count -gt 0) {
                Write-Warning "Link-Tree will replace $Destination; destination-only entries (migrate into .agents to keep via link):"
                foreach ($e in $extras) {
                    Write-Warning ("  - " + $e.FullName)
                    $agentsMirror = Join-Path $Source $e.Name
                    # Best-effort: copy destination-only into .agents counterpart before link
                    try {
                        if ($e.PSIsContainer) {
                            if (-not (Test-Path $agentsMirror)) {
                                Copy-Tree -Source $e.FullName -Destination $agentsMirror
                                Write-Host "INFO migrated $($e.Name) into $agentsMirror before link"
                            }
                        }
                        else {
                            if (-not (Test-Path $agentsMirror)) {
                                Copy-Item -Path $e.FullName -Destination $agentsMirror -Force
                                Write-Host "INFO migrated $($e.Name) into $agentsMirror before link"
                            }
                        }
                    }
                    catch {
                        Write-Warning "Could not migrate $($e.FullName): $_"
                    }
                }
            }
        }
        if ($item.LinkType) { Remove-Item $Destination -Force }
        else { Remove-Item $Destination -Recurse -Force }
    }

    $resolvedSource = (Resolve-Path $Source).Path
    if ($IsWindows) {
        New-Item -ItemType Junction -Path $Destination -Target $resolvedSource | Out-Null
    }
    else {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $resolvedSource | Out-Null
    }
}

function Invoke-ManifestCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $true }
    Write-Host "+ $Command"
    Invoke-Expression $Command
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { return $false }
    return $true
}

function Invoke-AgenticTool {
    param([string[]]$ToolArgs)

    if (Get-Command agentic-tool -ErrorAction SilentlyContinue) {
        & agentic-tool @ToolArgs
        return $LASTEXITCODE
    }

    $root = Get-Location
    $home = $env:AI_PIPELINE_HOME
    if ([string]::IsNullOrWhiteSpace($home) -and (Test-Path (Join-Path $root '.agents/pipeline.home'))) {
        $home = (Get-Content (Join-Path $root '.agents/pipeline.home') -Raw).Trim()
    }

    $proj = Join-Path $home 'src/Agentic.Tool/Agentic.Tool.fsproj'
    if (Test-Path $proj) {
        $env:AI_PIPELINE_HOME = $home
        dotnet run --project $proj -v q -- @ToolArgs
        return $LASTEXITCODE
    }

    $psWrapper = Join-Path $home 'bin/agentic-tool.ps1'
    if (Test-Path $psWrapper) {
        $env:AI_PIPELINE_HOME = $home
        & pwsh -NoProfile -File $psWrapper @ToolArgs
        return $LASTEXITCODE
    }

    Write-Error 'agentic-tool not found (PATH, AI_PIPELINE_HOME, or .agents/pipeline.home).'
    return 1
}
