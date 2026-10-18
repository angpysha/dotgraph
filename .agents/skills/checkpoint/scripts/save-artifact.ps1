# save-artifact.ps1 — copy stdin or a file into session artifacts (pwsh).
param(
    [Parameter(Mandatory)][string]$Session,
    [Parameter(Mandatory)][string]$ArtifactRel,
    [Parameter(Mandatory)][string]$Mode,
    [string]$SourceFile
)

$ErrorActionPreference = 'Stop'
$checkpoint = Join-Path $PSScriptRoot 'checkpoint.ps1'

switch ($Mode) {
    '--from' {
        if ([string]::IsNullOrWhiteSpace($SourceFile)) {
            Write-Error 'source file required with --from'
            exit 1
        }
        & $checkpoint save $Session $ArtifactRel --from $SourceFile
        exit $LASTEXITCODE
    }
    '--stdin' {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            [Console]::In.ReadToEnd() | Set-Content -Path $tmp -NoNewline
            & $checkpoint save $Session $ArtifactRel --from $tmp
            exit $LASTEXITCODE
        }
        finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    default {
        Write-Error 'use --from <file> or --stdin'
        exit 1
    }
}
