<#
.SYNOPSIS
  Assert beads rust (`br`) is available and initialized. Fail the phase with a CRITICAL banner if not.

.DESCRIPTION
  Contract: specs/011-speckit-tasks-beads/contracts/beads-ready-gate.md
  Exit 0 on success; non-zero on failure after printing the CRITICAL ❌ banner.
  Never suggests or runs `bd`.

.PARAMETER WorkingDirectory
  Repo root to probe (default: current directory).
#>
[CmdletBinding()]
param(
    [string]$WorkingDirectory = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-CriticalBanner {
    param([string]$Detail = '')
    $cross = '❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌'
    Write-Host $cross
    Write-Host 'CRITICAL — BEADS NOT INITIALIZED'
    Write-Host $cross
    Write-Host ''
    Write-Host 'This phase cannot continue.'
    Write-Host ''
    Write-Host 'Cause:'
    Write-Host '  • beads rust (`br`) is missing or not initialized in this workspace'
    Write-Host ''
    Write-Host 'Required action:'
    Write-Host '  1. Install `br` if needed (beads_rust)'
    Write-Host '  2. Initialize beads: `br init`'
    Write-Host '  3. Confirm readiness: `br info --json`'
    Write-Host '  4. Re-run this phase'
    Write-Host ''
    Write-Host 'STOP: Do not write tasks.md and do not invent a markdown-first fallback.'
    Write-Host $cross
    if ($Detail) {
        Write-Host "Detail: $Detail"
    }
}

Push-Location $WorkingDirectory
try {
    $brCmd = Get-Command br -ErrorAction SilentlyContinue
    if (-not $brCmd) {
        Write-CriticalBanner -Detail 'br executable not found on PATH'
        exit 1
    }

    $infoJson = & br info --json 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        Write-CriticalBanner -Detail ("br info --json failed (exit $exit): " + ($infoJson | Out-String).Trim())
        exit 1
    }

    try {
        $info = $infoJson | Out-String | ConvertFrom-Json
    } catch {
        Write-CriticalBanner -Detail ("br info --json was not valid JSON: $($_.Exception.Message)")
        exit 1
    }

    $db = $null
    $beadsDir = $null
    if ($info.PSObject.Properties.Name -contains 'database_path') { $db = [string]$info.database_path }
    if ($info.PSObject.Properties.Name -contains 'beads_dir') { $beadsDir = [string]$info.beads_dir }

    if ([string]::IsNullOrWhiteSpace($db) -and [string]::IsNullOrWhiteSpace($beadsDir)) {
        Write-CriticalBanner -Detail 'br info --json did not report database_path or beads_dir'
        exit 1
    }

    if ($db -and -not (Test-Path -LiteralPath $db)) {
        Write-CriticalBanner -Detail "database_path missing on disk: $db"
        exit 1
    }

    Write-Host "BEADS READY: br=$($brCmd.Source) db=$db beads_dir=$beadsDir"
    exit 0
}
finally {
    Pop-Location
}
