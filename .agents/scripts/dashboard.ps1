# dashboard.ps1 — Multi-workspace hub (009) over machine-global registry + per-repo sessions
# Usage:
#   pwsh ./scripts/dashboard.ps1
#   pwsh ./scripts/dashboard.ps1 -Port 8765 -RepoRoot /path/to/repo
#   pwsh ./scripts/dashboard.ps1 -Smoke
#   pwsh ./scripts/dashboard.ps1 -GenerateOnly
#   pwsh ./scripts/dashboard.ps1 -Serve
#   pwsh ./scripts/dashboard.ps1 -Detail /path/to/workspace
#   pwsh ./scripts/dashboard.ps1 -ResumeRun <run_id> -Detail <workspace> [-ResumeInput key=value]
#
# Registry: ~/.agentic-pipeline/workspace-registry.json (or AGENTIC_PIPELINE_HOME / XDG)
# Default (no -Smoke/-Serve/-GenerateOnly/-Detail/-ResumeRun): GenerateOnly (non-blocking).

param(
    [string]$RepoRoot = '',
    [int]$Port = 8765,
    [switch]$GenerateOnly,
    [switch]$Smoke,
    [switch]$Serve,
    [string]$Detail = '',
    [string]$ResumeRun = '',
    [string]$ResumeInput = 'spec_verdict=approve'
)

$ErrorActionPreference = 'Stop'

function Get-RegistryPath {
    if ($env:AGENTIC_PIPELINE_HOME) { return (Join-Path $env:AGENTIC_PIPELINE_HOME 'workspace-registry.json') }
    if ($env:XDG_CONFIG_HOME) { return (Join-Path $env:XDG_CONFIG_HOME 'agentic-pipeline/workspace-registry.json') }
    return (Join-Path $HOME '.agentic-pipeline/workspace-registry.json')
}

function Find-RepoRoot {
    param([string]$Start)
    $dir = if ($Start) { (Resolve-Path $Start).Path } else { (Get-Location).Path }
    while ($dir) {
        if ((Test-Path (Join-Path $dir '.git')) -or (Test-Path (Join-Path $dir 'pipeline.manifest.json'))) { return $dir }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return (Get-Location).Path
}

function Read-Registry {
    $path = Get-RegistryPath
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{ version = 1; updated_at = ''; workspaces = @() }
    }
    return (Get-Content $path -Raw | ConvertFrom-Json)
}

function Get-SpecKitReadiness {
    param([string]$Root)
    $manifest = Join-Path $Root 'pipeline.manifest.json'
    $enabled = $true
    if (Test-Path $manifest) {
        try {
            $m = Get-Content $manifest -Raw | ConvertFrom-Json
            if ($null -ne $m.spec_kit -and $null -ne $m.spec_kit.enabled) { $enabled = [bool]$m.spec_kit.enabled }
        } catch {}
    }
    if (-not $enabled) { return 'degraded_disabled' }
    $specify = Get-Command specify -ErrorAction SilentlyContinue
    if (-not $specify) { return 'cli_missing' }
    $specifyDir = Join-Path $Root '.specify'
    if (-not (Test-Path $specifyDir)) { return 'not_initialized' }
    if (-not ((Test-Path (Join-Path $specifyDir 'templates')) -or (Test-Path (Join-Path $specifyDir 'workflows')) -or (Test-Path (Join-Path $specifyDir 'memory/constitution.md')))) {
        return 'not_initialized'
    }
    return 'ok'
}

function Get-SpecKitRunState {
    param([string]$Root, [string]$RunId)
    if ([string]::IsNullOrWhiteSpace($RunId)) { return $null }
    $statePath = Join-Path $Root ".specify/workflows/runs/$RunId/state.json"
    if (-not (Test-Path $statePath)) { return $null }
    try { return (Get-Content $statePath -Raw | ConvertFrom-Json) } catch { return $null }
}

function Sync-SessionWorkflowTwin {
    param([string]$Root, [string]$SessionDir)
    $statePath = Join-Path $SessionDir 'state.json'
    if (-not (Test-Path $statePath)) { return $null }
    try {
        $st = Get-Content $statePath -Raw | ConvertFrom-Json
        if (-not $st.workflow -or -not $st.workflow.run_id) { return $st.workflow }
        $run = Get-SpecKitRunState -Root $Root -RunId ([string]$st.workflow.run_id)
        if (-not $run) { return $st.workflow }
        $newStatus = if ($run.status) { [string]$run.status } else { [string]$st.workflow.status }
        $step = if ($run.current_step_id) { [string]$run.current_step_id } else { $null }
        # Rewrite twin status from Spec Kit authority
        $obj = Get-Content $statePath -Raw | ConvertFrom-Json
        if (-not $obj.workflow) { $obj | Add-Member -NotePropertyName workflow -NotePropertyValue ([pscustomobject]@{}) }
        $wf = [ordered]@{
            id = if ($obj.workflow.id) { [string]$obj.workflow.id } elseif ($run.workflow_id) { [string]$run.workflow_id } else { '' }
            run_id = [string]$st.workflow.run_id
            status = $newStatus
        }
        if ($step) { $wf.step = $step }
        $obj.workflow = [pscustomobject]$wf
        $obj | ConvertTo-Json -Depth 12 | Set-Content -Path $statePath -Encoding UTF8
        return $obj.workflow
    } catch {
        return $null
    }
}

function Get-WorkspaceSessions {
    param([string]$Root)
    $codeAgent = Join-Path $Root '_code_agent'
    $list = @()
    if (-not (Test-Path $codeAgent)) { return $list }
    Get-ChildItem $codeAgent -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object {
        $wf = Sync-SessionWorkflowTwin -Root $Root -SessionDir $_.FullName
        $list += [pscustomobject]@{
            name = $_.Name
            path = $_.FullName
            updated = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            workflow = $wf
        }
    }
    return $list
}

function Get-LatestSpecKitRun {
    param([string]$Root)
    $runsRoot = Join-Path $Root '.specify/workflows/runs'
    if (-not (Test-Path $runsRoot)) { return $null }
    $latest = Get-ChildItem $runsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    $st = Get-SpecKitRunState -Root $Root -RunId $latest.Name
    if (-not $st) { return $null }
    return [pscustomobject]@{
        id = if ($st.workflow_id) { [string]$st.workflow_id } else { '' }
        run_id = $latest.Name
        status = if ($st.status) { [string]$st.status } else { 'unknown' }
        step = if ($st.current_step_id) { [string]$st.current_step_id } else { '' }
        session = ''
    }
}

function Get-WorkspaceSummary {
    param([string]$Path)
    $row = [ordered]@{
        path = $Path
        name = Split-Path $Path -Leaf
        status = 'path_unavailable'
        managed = $false
        skills = @()
        stack = @()
        constitution = 'not set'
        spec_kit = 'path_unavailable'
        workflow = $null
        host = ''
        tracker = ''
        vision = ''
        agents = @()
        packs = @()
        sessions = @()
    }
    if (-not (Test-Path $Path)) { return [pscustomobject]$row }
    $row.status = 'present'
    $row.spec_kit = Get-SpecKitReadiness -Root $Path
    $manifest = Join-Path $Path 'pipeline.manifest.json'
    if (Test-Path $manifest) {
        $row.managed = $true
        try {
            $m = Get-Content $manifest -Raw | ConvertFrom-Json
            $row.status = if ($m.status) { $m.status } else { 'present' }
            $row.host = if ($m.host) { $m.host } else { '' }
            $row.tracker = if ($m.tracker.type) { $m.tracker.type } else { '' }
            if ($m.packs) { $row.packs = @($m.packs); $row.stack = @($m.packs) }
            if ($m.agents) { $row.agents = @($m.agents) }
            if ($m.project.name) { $row.name = $m.project.name }
        } catch { $row.status = 'manifest_error' }
    }
    $skillsDir = Join-Path $Path '.agents/skills'
    if (Test-Path $skillsDir) {
        $row.skills = @(Get-ChildItem $skillsDir -Directory | ForEach-Object { $_.Name })
    }
    $const = Join-Path $Path '.specify/memory/constitution.md'
    $row.constitution = if (Test-Path $const) { 'present' } else { 'not set' }
    $projectMd = Join-Path $Path 'PROJECT.md'
    if (Test-Path $projectMd) {
        $lines = Get-Content $projectMd -TotalCount 40
        $visionLine = $lines | Where-Object { $_ -match '(?i)^#+\s*vision|^vision\s*:' } | Select-Object -First 1
        if ($visionLine) { $row.vision = ($visionLine -replace '^#+\s*', '').Trim() }
    }
    $sessions = @(Get-WorkspaceSessions -Root $Path)
    $row.sessions = $sessions
    $withWf = $sessions | Where-Object { $_.workflow -and $_.workflow.run_id } | Select-Object -First 1
    if ($withWf) {
        $row.workflow = [pscustomobject]@{
            id = $withWf.workflow.id
            run_id = $withWf.workflow.run_id
            status = $withWf.workflow.status
            step = if ($withWf.workflow.step) { $withWf.workflow.step } else { '' }
            session = $withWf.name
        }
    } else {
        $row.workflow = Get-LatestSpecKitRun -Root $Path
    }
    return [pscustomobject]$row
}

function Invoke-WorkflowResume {
    param([string]$Root, [string]$RunId, [string]$Input)
    $specify = Get-Command specify -ErrorAction SilentlyContinue
    if (-not $specify) {
        Write-Error "specify CLI not found (cli_missing)"
        return 2
    }
    $args = @('workflow', 'resume', $RunId, '--json')
    if (-not [string]::IsNullOrWhiteSpace($Input)) {
        $args += @('-i', $Input)
    }
    Push-Location $Root
    try {
        Write-Host "Running: specify $($args -join ' ') @ $Root"
        & specify @args
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    # Refresh twins for all sessions pointing at this run
    Get-ChildItem (Join-Path $Root '_code_agent') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Sync-SessionWorkflowTwin -Root $Root -SessionDir $_.FullName | Out-Null
    }
    return $code
}

function ConvertTo-SafeHtml {
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-ResumeBlockHtml {
    param($Workflow, [string]$WorkspacePath)
    if (-not $Workflow -or -not $Workflow.run_id) {
        return '<p class="meta">No active lane workflow run.</p>'
    }
    $rid = ConvertTo-SafeHtml $Workflow.run_id
    $status = [string]$Workflow.status
    $canResume = $status -in @('paused', 'failed', 'waiting', 'gate')
    $encPath = [uri]::EscapeDataString($WorkspacePath)
    $cmd = "specify workflow resume $rid -i spec_verdict=approve --json"
    $html = @"
<div class="card">
  <h3>Lane workflow</h3>
  <p><code>$(ConvertTo-SafeHtml $Workflow.id)</code> · run <code>$rid</code> · <strong>$(ConvertTo-SafeHtml $status)</strong>
  $(if ($Workflow.step) { "· step <code>$(ConvertTo-SafeHtml $Workflow.step)</code>" } else { '' })
  $(if ($Workflow.session) { "· session <code>$(ConvertTo-SafeHtml $Workflow.session)</code>" } else { '' })</p>
  <p class="meta">CLI: <code>$(ConvertTo-SafeHtml $cmd)</code></p>
"@
    if ($canResume) {
        $html += @"
  <form method="get" action="/resume">
    <input type="hidden" name="path" value="$(ConvertTo-SafeHtml $WorkspacePath)"/>
    <input type="hidden" name="run_id" value="$rid"/>
    <label>Input <input name="input" value="spec_verdict=approve" size="40"/></label>
    <button type="submit">Resume run</button>
  </form>
  <p class="meta">Or open: <a href="/resume?path=$encPath&amp;run_id=$rid&amp;input=spec_verdict%3Dapprove"><code>/resume</code></a></p>
"@
    }
    $html += '</div>'
    return $html
}

function New-DetailHtml {
    param($Summary)
    $sessRows = ($Summary.sessions | ForEach-Object {
        $wf = if ($_.workflow) { "$($_.workflow.id) /$($_.workflow.run_id) ($($_.workflow.status))" } else { '—' }
        "<tr><td><code>$(ConvertTo-SafeHtml $_.name)</code></td><td>$(ConvertTo-SafeHtml $_.updated)</td><td>$(ConvertTo-SafeHtml $wf)</td></tr>"
    }) -join "`n"
    if (-not $sessRows) { $sessRows = '<tr><td colspan="3" class="meta">No _code_agent sessions</td></tr>' }
    $agents = ($Summary.agents | Select-Object -First 20) -join ', '
    $packs = ($Summary.packs -join ', ')
    $skills = ($Summary.skills | Select-Object -First 24) -join ', '
    $resume = New-ResumeBlockHtml -Workflow $Summary.workflow -WorkspacePath $Summary.path
    $unmanaged = if (-not $Summary.managed) { '<p class="warn">Unmanaged / needs install (no pipeline.manifest.json)</p>' } else { '' }
    return @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/><title>$(ConvertTo-SafeHtml $Summary.name)</title>
<style>
body{font-family:ui-sans-serif,system-ui,sans-serif;margin:1.5rem;background:#0f1419;color:#e7ecf1;max-width:1100px}
table{border-collapse:collapse;width:100%;font-size:0.9rem;margin:1rem 0}
th,td{border-bottom:1px solid #2a3440;padding:0.55rem 0.4rem;text-align:left;vertical-align:top}
th{color:#9fb0c0;font-weight:600}
code{font-size:0.8rem;color:#b8f0c0}
a{color:#6cb6ff}
.meta{color:#9fb0c0}
.warn{color:#f0c14a}
.card{border:1px solid #2a3440;padding:1rem;margin:1rem 0;border-radius:6px}
button{background:#2a6;color:#fff;border:0;padding:0.4rem 0.8rem;border-radius:4px;cursor:pointer}
input{background:#1a222c;border:1px solid #2a3440;color:#e7ecf1;padding:0.3rem;margin-right:0.5rem}
</style></head><body>
<p><a href="/">← Workspaces</a></p>
<h1>$(ConvertTo-SafeHtml $Summary.name)</h1>
$unmanaged
<p class="meta"><code>$(ConvertTo-SafeHtml $Summary.path)</code></p>
<p>Status: <strong>$(ConvertTo-SafeHtml $Summary.status)</strong> · Spec Kit: <strong>$(ConvertTo-SafeHtml $Summary.spec_kit)</strong> · Constitution: $(ConvertTo-SafeHtml $Summary.constitution)</p>
<p>Host: $(ConvertTo-SafeHtml $Summary.host) · Tracker: $(ConvertTo-SafeHtml $Summary.tracker)</p>
<p>Stack/packs: $(ConvertTo-SafeHtml $packs)</p>
<p>Agents: $(ConvertTo-SafeHtml $agents)</p>
<p>Skills: $(ConvertTo-SafeHtml $skills)</p>
$(if ($Summary.vision) { "<p>Vision: $(ConvertTo-SafeHtml $Summary.vision)</p>" } else { '' })
$resume
<h2>Sessions</h2>
<table><thead><tr><th>Session</th><th>Updated</th><th>Workflow twin</th></tr></thead>
<tbody>$sessRows</tbody></table>
<p class="meta">Deep session UI: <code>pwsh scripts/session-ui.ps1 -RepoRoot &quot;$(ConvertTo-SafeHtml $Summary.path)&quot;</code></p>
</body></html>
"@
}

function New-HubHtml {
    param($Summaries, [string]$RegistryPath)
    $htmlRows = ($Summaries | ForEach-Object {
        $skills = ($_.skills | Select-Object -First 12) -join ', '
        $stack = ($_.stack -join ', ')
        $wf = if ($_.workflow) { "$($_.workflow.id) / $($_.workflow.run_id) ($($_.workflow.status))" } else { '—' }
        $safePath = ConvertTo-SafeHtml $_.path
        $href = "/ws?path=$([uri]::EscapeDataString([string]$_.path))"
        $needs = if (-not $_.managed) { ' · needs install' } else { '' }
        @"
<tr>
  <td><a href="$href"><code>$safePath</code></a></td>
  <td>$(ConvertTo-SafeHtml $_.name)$needs</td>
  <td>$(ConvertTo-SafeHtml $_.status)</td>
  <td>$(ConvertTo-SafeHtml $skills)</td>
  <td>$(ConvertTo-SafeHtml $stack)</td>
  <td>$(ConvertTo-SafeHtml $_.constitution)</td>
  <td>$(ConvertTo-SafeHtml $_.spec_kit)</td>
  <td>$(ConvertTo-SafeHtml $wf)</td>
</tr>
"@
    }) -join "`n"

    return @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/><title>Pipeline Dashboard</title>
<style>
body{font-family:ui-sans-serif,system-ui,sans-serif;margin:1.5rem;background:#0f1419;color:#e7ecf1}
table{border-collapse:collapse;width:100%;font-size:0.9rem}
th,td{border-bottom:1px solid #2a3440;padding:0.55rem 0.4rem;text-align:left;vertical-align:top}
th{color:#9fb0c0;font-weight:600}
code{font-size:0.8rem;color:#b8f0c0}
a{color:#6cb6ff}
.meta{color:#9fb0c0;margin-bottom:1rem}
</style></head><body>
<h1>Pipeline workspaces</h1>
<p class="meta">Registry: $(ConvertTo-SafeHtml $RegistryPath)</p>
<p class="meta">Click a path for detail (Spec Kit readiness, workflow twin, sessions, resume).</p>
<table>
<thead><tr><th>Path</th><th>Name</th><th>Status</th><th>Skills</th><th>Stack</th><th>Constitution</th><th>Spec Kit</th><th>Workflow</th></tr></thead>
<tbody>
$htmlRows
</tbody></table>
</body></html>
"@
}

function Write-DetailText {
    param($Summary)
    Write-Host "=== Workspace detail ==="
    Write-Host ("path:         {0}" -f $Summary.path)
    Write-Host ("name:         {0}" -f $Summary.name)
    Write-Host ("status:       {0}" -f $Summary.status)
    Write-Host ("managed:      {0}" -f $Summary.managed)
    Write-Host ("spec_kit:     {0}" -f $Summary.spec_kit)
    Write-Host ("constitution: {0}" -f $Summary.constitution)
    Write-Host ("host:         {0}" -f $Summary.host)
    Write-Host ("tracker:      {0}" -f $Summary.tracker)
    Write-Host ("stack:        {0}" -f ($Summary.stack -join ','))
    Write-Host ("agents:       {0}" -f ($Summary.agents -join ','))
    Write-Host ("skills:       {0}" -f ($Summary.skills -join ','))
    if ($Summary.vision) { Write-Host ("vision:       {0}" -f $Summary.vision) }
    if ($Summary.workflow) {
        Write-Host ("workflow:     {0} run={1} status={2} step={3} session={4}" -f `
            $Summary.workflow.id, $Summary.workflow.run_id, $Summary.workflow.status, $Summary.workflow.step, $Summary.workflow.session)
        if ($Summary.workflow.status -in @('paused', 'failed', 'waiting', 'gate')) {
            Write-Host ("resume:       specify workflow resume {0} -i {1} --json" -f $Summary.workflow.run_id, $ResumeInput)
        }
    } else {
        Write-Host 'workflow:     —'
    }
    Write-Host ("sessions:     {0}" -f $Summary.sessions.Count)
    $Summary.sessions | ForEach-Object {
        $w = if ($_.workflow) { "$($_.workflow.id)/$($_.workflow.run_id)($($_.workflow.status))" } else { '—' }
        Write-Host ("  - {0}  twin={1}" -f $_.name, $w)
    }
}

# --- main ---
if (-not $RepoRoot) { $RepoRoot = Find-RepoRoot }
$RepoRoot = (Resolve-Path $RepoRoot).Path

if ($ResumeRun -and $Detail) {
    $detailRoot = (Resolve-Path $Detail).Path
    exit (Invoke-WorkflowResume -Root $detailRoot -RunId $ResumeRun -Input $ResumeInput)
}

if ($Detail) {
    $detailRoot = (Resolve-Path $Detail).Path
    $summary = Get-WorkspaceSummary -Path $detailRoot
    Write-DetailText -Summary $summary
    if ($Smoke) {
        Write-Host 'DETAIL SMOKE OK'
        exit 0
    }
    if (-not $Serve -and -not $GenerateOnly) {
        exit 0
    }
}

$reg = Read-Registry
$paths = @()
if ($reg.workspaces) {
    foreach ($w in $reg.workspaces) { if ($w.path) { $paths += [string]$w.path } }
}
if ($paths.Count -eq 0) { $paths = @($RepoRoot) }
if ($Detail) {
    $dp = (Resolve-Path $Detail).Path
    if ($paths -notcontains $dp) { $paths = @($dp) + $paths }
}

$summaries = @($paths | ForEach-Object { Get-WorkspaceSummary -Path $_ })

if ($Smoke -and -not $Detail) {
    Write-Host "Registry: $(Get-RegistryPath)"
    Write-Host "Workspaces: $($summaries.Count)"
    $summaries | ForEach-Object {
        Write-Host ("- {0} | {1} | skills={2} | stack={3} | constitution={4} | spec_kit={5}" -f $_.path, $_.status, ($_.skills -join ','), ($_.stack -join ','), $_.constitution, $_.spec_kit)
        if ($_.workflow) { Write-Host ("  workflow: {0} run={1} status={2} session={3}" -f $_.workflow.id, $_.workflow.run_id, $_.workflow.status, $_.workflow.session) }
        Write-Host ("  sessions: {0}" -f $_.sessions.Count)
    }
    Write-Host 'SMOKE OK'
    exit 0
}

$outDir = Join-Path $RepoRoot '.session-ui'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$hubHtml = New-HubHtml -Summaries $summaries -RegistryPath (Get-RegistryPath)
$indexPath = Join-Path $outDir 'index.html'
Set-Content -Path $indexPath -Value $hubHtml -Encoding UTF8

# Write per-workspace detail pages for offline browsing
$wsDir = Join-Path $outDir 'workspaces'
New-Item -ItemType Directory -Force -Path $wsDir | Out-Null
foreach ($s in $summaries) {
    $safeName = ($s.name -replace '[^\w\.-]', '_')
    $hash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($s.path))).Replace('-', '').Substring(0, 12).ToLowerInvariant()
    $page = Join-Path $wsDir "$safeName-$hash.html"
    Set-Content -Path $page -Value (New-DetailHtml -Summary $s) -Encoding UTF8
}

$doServe = [bool]$Serve
if (-not $GenerateOnly -and -not $Smoke -and -not $Serve -and -not $Detail) {
    # Non-blocking default: write HTML and exit (avoid hanging HTTP server in agents/CI)
    Write-Host "Wrote $indexPath (default GenerateOnly). Use -Serve to host http://127.0.0.1:$Port/"
    exit 0
}

if ($GenerateOnly -and -not $Serve) {
    Write-Host "Wrote $indexPath"
    exit 0
}

Write-Host "Hub page: $indexPath"
Write-Host "Serving hub on http://127.0.0.1:$Port/ (Ctrl+C to stop)"

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
try {
    while ($true) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $localPath = $req.Url.AbsolutePath
        $qs = $req.QueryString
        $bodyHtml = $hubHtml
        $statusCode = 200

        try {
            if ($localPath -eq '/ws' -or $localPath -eq '/detail') {
                $p = $qs['path']
                if ($p -and (Test-Path $p)) {
                    $bodyHtml = New-DetailHtml -Summary (Get-WorkspaceSummary -Path $p)
                } else {
                    $bodyHtml = '<html><body><h1>Workspace not found</h1><a href="/">Back</a></body></html>'
                    $statusCode = 404
                }
            }
            elseif ($localPath -eq '/resume') {
                $p = $qs['path']
                $rid = $qs['run_id']
                $inp = $qs['input']
                if (-not $inp) { $inp = 'spec_verdict=approve' }
                if ($p -and $rid -and (Test-Path $p)) {
                    $code = Invoke-WorkflowResume -Root $p -RunId $rid -Input $inp
                    $sum = Get-WorkspaceSummary -Path $p
                    $note = if ($code -eq 0) { 'Resume invoked (exit 0). Twin refreshed if session present.' } else { "Resume exit $code — see CLI output / Spec Kit run state." }
                    $bodyHtml = "<html><body><p>$note</p>" + (New-DetailHtml -Summary $sum) + '</body></html>'
                } else {
                    $bodyHtml = '<html><body><h1>Missing path or run_id</h1><a href="/">Back</a></body></html>'
                    $statusCode = 400
                }
            }
            else {
                # Refresh hub each request
                $summaries = @($paths | ForEach-Object { Get-WorkspaceSummary -Path $_ })
                $hubHtml = New-HubHtml -Summaries $summaries -RegistryPath (Get-RegistryPath)
                $bodyHtml = $hubHtml
            }
        } catch {
            $bodyHtml = "<html><body><h1>Error</h1><pre>$(ConvertTo-SafeHtml $_.Exception.Message)</pre><a href='/'>Back</a></body></html>"
            $statusCode = 500
        }

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($bodyHtml)
        $ctx.Response.StatusCode = $statusCode
        $ctx.Response.ContentType = 'text/html; charset=utf-8'
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
    }
} finally {
    $listener.Stop()
}
