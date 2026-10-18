# publish-sdlc.ps1 — copy final SDLC artifacts from session folder to docs/sdlc (Phase 9/10).
param(
    [Parameter(Mandatory)][string]$Session,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/sdlc-session.ps1"

Publish-SdlcArtifacts -Session $Session -DryRun:$DryRun
exit 0
