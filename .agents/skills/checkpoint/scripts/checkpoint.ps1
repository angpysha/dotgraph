# Checkpoint helper — delegates to agentic-tool (pwsh).
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '../../../../')).Path
Set-Location $root

function Get-PipelineHome {
    if ($env:AI_PIPELINE_HOME) { return $env:AI_PIPELINE_HOME }
    $hint = Join-Path $root '.agents/pipeline.home'
    if (Test-Path $hint) { return (Get-Content $hint -Raw).Trim() }
    return $root
}

$home = Get-PipelineHome
$lib = Join-Path $home 'scripts/lib/PipelineScripts.ps1'
if (Test-Path $lib) {
    . $lib
    $code = Invoke-AgenticTool -ToolArgs (@('checkpoint') + $Args)
    exit $code
}

if (Get-Command agentic-tool -ErrorAction SilentlyContinue) {
    & agentic-tool checkpoint @Args
    exit $LASTEXITCODE
}

$proj = Join-Path $home 'src/Agentic.Tool/Agentic.Tool.fsproj'
if (Test-Path $proj) {
    $env:AI_PIPELINE_HOME = $home
    dotnet run --project $proj -v q -- checkpoint @Args
    exit $LASTEXITCODE
}

Write-Error 'agentic-tool not found (PATH, AI_PIPELINE_HOME, or .agents/pipeline.home).'
exit 1
