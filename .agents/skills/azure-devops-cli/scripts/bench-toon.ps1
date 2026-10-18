# bench-toon.ps1 — token stats for ADO sample payloads
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$dll = Join-Path $repoRoot 'src/Agentic.Tool/bin/Debug/net10.0/Agentic.Tool.dll'
if (-not (Test-Path $dll)) { throw "Build agentic-tool first: $dll" }

function Bench {
    param([string]$Name, [string]$Json)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'dotnet'
    $psi.Arguments = "exec `"$dll`" toon encode --stdin --stats"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($Json)
    $p.StandardInput.Close()
    [void]$p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd().Trim()
    $p.WaitForExit()
    Write-Output "$Name : $err"
}

$samples = Join-Path $PSScriptRoot '../catalog/samples'
Bench 'shaped-10-pr' (Get-Content (Join-Path $samples 'pr-list-shaped.json') -Raw)
Bench 'raw-10-pr' (Get-Content (Join-Path $samples 'pr-list-raw.json') -Raw)
Bench 'pipeline-2-runs' '[{"id":101,"state":"completed","result":"succeeded","sourceBranch":"refs/heads/main","finishedDate":"2026-06-10T12:00:00Z","url":"https://dev.azure.com/o/p/_build/results?buildId=101"},{"id":102,"state":"completed","result":"failed","sourceBranch":"refs/heads/feature/x","finishedDate":"2026-06-10T11:00:00Z","url":"https://dev.azure.com/o/p/_build/results?buildId=102"}]'
