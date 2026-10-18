# session-ui.ps1 — Basic local file-backed session UI over _code_agent/
# Prefer: agentic-tool dashboard (multi-workspace hub). This script remains for per-repo session detail.
# Usage:
#   pwsh ./scripts/session-ui.ps1
#   pwsh ./scripts/session-ui.ps1 -Port 8765 -RepoRoot /path/to/repo
#   pwsh ./scripts/session-ui.ps1 -GenerateOnly   # write HTML under .session-ui/ and exit
#   pwsh ./scripts/session-ui.ps1 -Smoke          # list/detail UX smoke without serving
#
# Serves list + detail on http://127.0.0.1:<port>/ (re-reads disk each request).
# UX: search/sort, sectioned detail, refresh/auto-refresh, relative times, soft-fail banners.
# No tokens/hooks required (epic 006 optional later).

param(
    [string]$RepoRoot = '',
    [int]$Port = 8765,
    [switch]$GenerateOnly,
    [switch]$Smoke
)

$ErrorActionPreference = 'Stop'

function Find-RepoRoot {
    param([string]$Start)
    $dir = if ($Start) { (Resolve-Path $Start).Path } else { (Get-Location).Path }
    while ($dir) {
        if ((Test-Path (Join-Path $dir '.git')) -or
            (Test-Path (Join-Path $dir 'pipeline.manifest.json')) -or
            (Test-Path (Join-Path $dir '.specify'))) {
            return $dir
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return (Get-Location).Path
}

if (-not $RepoRoot) { $RepoRoot = Find-RepoRoot }
$RepoRoot = (Resolve-Path $RepoRoot).Path
$CodeAgent = Join-Path $RepoRoot '_code_agent'
$OutDir = Join-Path $RepoRoot '.session-ui'

$SecretKeyPattern = '(?i)(password|secret|token|pat|api[_-]?key|authorization|credential|private[_-]?key)'

function Test-SecretKeyName {
    param([string]$Name)
    return [regex]::IsMatch($Name, $SecretKeyPattern)
}

function ConvertTo-SafeHtml {
    param($Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

function Get-RedactedObject {
    param($Obj, [int]$Depth = 0)
    if ($Depth -gt 8 -or $null -eq $Obj) { return $Obj }
    if ($Obj -is [string] -or $Obj -is [ValueType]) { return $Obj }
    if ($Obj -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in $Obj.Keys) {
            $key = [string]$k
            if (Test-SecretKeyName $key) { $out[$key] = '[redacted]' }
            else { $out[$key] = Get-RedactedObject $Obj[$k] ($Depth + 1) }
        }
        return $out
    }
    if ($Obj -is [System.Collections.IEnumerable] -and -not ($Obj -is [string])) {
        $list = @()
        foreach ($item in $Obj) { $list += ,(Get-RedactedObject $item ($Depth + 1)) }
        return $list
    }
    # PSCustomObject from ConvertFrom-Json
    $props = $Obj.PSObject.Properties
    if ($props) {
        $out = [ordered]@{}
        foreach ($p in $props) {
            if (Test-SecretKeyName $p.Name) { $out[$p.Name] = '[redacted]' }
            else { $out[$p.Name] = Get-RedactedObject $p.Value ($Depth + 1) }
        }
        return $out
    }
    return $Obj
}

function ConvertTo-PrettyJson {
    param($Obj)
    try {
        return ($Obj | ConvertTo-Json -Depth 12)
    } catch {
        return [string]$Obj
    }
}

function Get-SessionSummaries {
    $rows = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path $CodeAgent)) { return @() }

    $dirs = Get-ChildItem -Path $CodeAgent -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^\.' } |
        Sort-Object Name -Descending

    $byFeature = @{}
    foreach ($d in $dirs) {
        $statePath = Join-Path $d.FullName 'state.json'
        $row = [ordered]@{
            id               = $d.Name
            path             = $d.FullName
            ok               = $true
            error            = $null
            lane             = 'unconfirmed'
            lane_status      = $null
            feature_directory = $null
            phase            = $null
            owner_agent      = $null
            updated          = $d.LastWriteTimeUtc.ToString('o')
            is_latest        = $false
        }

        if (-not (Test-Path $statePath)) {
            $row.ok = $false
            $row.error = 'missing state.json'
            $rows.Add([pscustomobject]$row)
            continue
        }

        try {
            $raw = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop
            $state = $raw | ConvertFrom-Json -ErrorAction Stop
            $feature = $null
            if ($state.feature_directory) { $feature = [string]$state.feature_directory }
            elseif ($state.spec_kit -and $state.spec_kit.feature_directory) {
                $feature = [string]$state.spec_kit.feature_directory
            }
            $laneStatus = if ($state.lane_status) { [string]$state.lane_status } else { $null }
            $flow = if ($state.flow) { [string]$state.flow } else { $null }
            $lane = if ($flow) { $flow }
                elseif ($laneStatus -eq 'confirmed') { 'confirmed (no flow)' }
                elseif ($laneStatus) { "unconfirmed ($laneStatus)" }
                else { 'unconfirmed' }

            $row.lane = $lane
            $row.lane_status = $laneStatus
            $row.feature_directory = $feature
            $row.phase = if ($state.phase) { [string]$state.phase } else { $null }
            $row.owner_agent = if ($state.owner_agent) { [string]$state.owner_agent } else { $null }
            if ($state.updated) { $row.updated = [string]$state.updated }
            elseif ($state.created) { $row.updated = [string]$state.created }

            if ($feature) {
                if (-not $byFeature.ContainsKey($feature)) { $byFeature[$feature] = [System.Collections.Generic.List[object]]::new() }
                $byFeature[$feature].Add([pscustomobject]$row)
            }
        } catch {
            $row.ok = $false
            $row.error = "bad state.json: $($_.Exception.Message)"
        }
        $rows.Add([pscustomobject]$row)
    }

    foreach ($feature in @($byFeature.Keys)) {
        $group = @($byFeature[$feature] | Sort-Object { $_.updated } -Descending)
        if ($group.Count -gt 0) {
            $latestId = $group[0].id
            foreach ($r in $rows) {
                if ($r.id -eq $latestId -and $r.feature_directory -eq $feature) {
                    $r.is_latest = $true
                }
            }
        }
    }

    return @($rows)
}

function Get-SessionDetail {
    param([string]$SessionId)
    $dir = Join-Path $CodeAgent $SessionId
    if (-not (Test-Path $dir)) {
        return [pscustomobject]@{ ok = $false; error = "session not found: $SessionId"; id = $SessionId }
    }

    $detail = [ordered]@{
        ok                = $true
        id                = $SessionId
        path              = $dir
        error             = $null
        state             = $null
        state_raw_ok      = $false
        lane              = 'unconfirmed'
        lane_status       = $null
        flow              = $null
        feature_directory = $null
        phase             = 'not set'
        owner_agent       = 'not set'
        blockers          = @('not set')
        last_gate         = 'not set'
        steps             = @()
        events_truncated  = $false
        events            = @()
        usage_note        = 'Usage / tokens unavailable (epic 006 not required for this UI).'
    }

    $statePath = Join-Path $dir 'state.json'
    if (Test-Path $statePath) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -ErrorAction Stop
            $detail.state_raw_ok = $true
            $detail.state = Get-RedactedObject $state
            if ($state.feature_directory) { $detail.feature_directory = [string]$state.feature_directory }
            elseif ($state.spec_kit -and $state.spec_kit.feature_directory) {
                $detail.feature_directory = [string]$state.spec_kit.feature_directory
            }
            $detail.lane_status = if ($state.lane_status) { [string]$state.lane_status } else { $null }
            $detail.flow = if ($state.flow) { [string]$state.flow } else { $null }
            $detail.lane = if ($detail.flow) { $detail.flow }
                elseif ($detail.lane_status -eq 'confirmed') { 'confirmed (no flow)' }
                elseif ($detail.lane_status) { "unconfirmed ($($detail.lane_status))" }
                else { 'unconfirmed' }
            if ($state.phase) { $detail.phase = [string]$state.phase }
            if ($state.owner_agent) { $detail.owner_agent = [string]$state.owner_agent }
            if ($state.blockers) {
                $detail.blockers = @($state.blockers | ForEach-Object { [string]$_ })
                if ($detail.blockers.Count -eq 0) { $detail.blockers = @('not set') }
            }
            if ($state.last_gate) { $detail.last_gate = [string]$state.last_gate }
            elseif ($state.lastGate) { $detail.last_gate = [string]$state.lastGate }
        } catch {
            $detail.ok = $true  # soft-fail detail: still show steps
            $detail.error = "bad state.json: $($_.Exception.Message)"
            $detail.state_raw_ok = $false
        }
    } else {
        $detail.error = 'missing state.json'
    }

    $stepsDir = Join-Path $dir 'steps'
    $steps = [System.Collections.Generic.List[object]]::new()
    if (Test-Path $stepsDir) {
        Get-ChildItem -Path $stepsDir -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            ForEach-Object {
                $rel = $_.FullName.Substring($dir.Length).TrimStart([char]'\', [char]'/')
                $relNorm = $rel.Replace('\', '/')
                $steps.Add([pscustomobject]@{
                    path     = $relNorm
                    name     = $_.Name
                    modified = $_.LastWriteTimeUtc.ToString('o')
                    size     = $_.Length
                })
            }
    }
    # Also list top-level checkpoint-ish folders
    foreach ($extra in @('checkpoints', 'gates')) {
        $extraDir = Join-Path $dir $extra
        if (Test-Path $extraDir) {
            Get-ChildItem -Path $extraDir -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object FullName |
                ForEach-Object {
                    $rel = $_.FullName.Substring($dir.Length).TrimStart([char]'\', [char]'/')
                    $relNorm = $rel.Replace('\', '/')
                    $steps.Add([pscustomobject]@{
                        path     = $relNorm
                        name     = $_.Name
                        modified = $_.LastWriteTimeUtc.ToString('o')
                        size     = $_.Length
                    })
                }
        }
    }
    $detail.steps = @($steps)

    $eventsPath = Join-Path $dir 'events.jsonl'
    if (Test-Path $eventsPath) {
        $lines = Get-Content -LiteralPath $eventsPath -ErrorAction SilentlyContinue
        $max = 100
        if ($lines.Count -gt $max) {
            $detail.events_truncated = $true
            $lines = $lines | Select-Object -Last $max
        }
        $ev = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                $ev.Add((Get-RedactedObject $obj))
            } catch {
                $ev.Add([pscustomobject]@{ raw = [string]$line; parse_error = $true })
            }
        }
        $detail.events = @($ev)
    }

    return [pscustomobject]$detail
}

function Get-SharedCss {
    return @'
:root {
  --bg: #f0f3f7;
  --bg-accent: #e4ebf3;
  --ink: #152033;
  --muted: #5a6a7d;
  --line: #c9d4e2;
  --card: #ffffff;
  --accent: #1a6b8c;
  --accent-hover: #165a78;
  --warn: #9a6700;
  --warn-bg: #fff8e6;
  --warn-line: #f0d78c;
  --bad: #b42318;
  --bad-bg: #fef3f2;
  --bad-line: #fecdca;
  --ok: #067647;
  --ok-bg: #ecfdf3;
  --ok-line: #a9efc5;
  --latest: #175cd3;
  --latest-bg: #eff8ff;
  --latest-line: #b2ddff;
  --shadow: 0 1px 2px rgba(21, 32, 51, 0.06), 0 4px 12px rgba(21, 32, 51, 0.04);
  --radius: 10px;
  --mono: "IBM Plex Mono", "SF Mono", "Menlo", "Consolas", monospace;
  --sans: "IBM Plex Sans", "Segoe UI", "Helvetica Neue", "Arial Nova", sans-serif;
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  min-height: 100vh;
  padding: 1.25rem 1rem 3rem;
  font-family: var(--sans);
  color: var(--ink);
  background:
    radial-gradient(ellipse 80% 50% at 0% 0%, var(--bg-accent), transparent 55%),
    linear-gradient(180deg, #f7f9fc 0%, var(--bg) 40%, #e8eef5 100%);
  line-height: 1.5;
  font-size: 15px;
}
main { max-width: 980px; margin: 0 auto; }
.topbar {
  display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: space-between;
  gap: 0.75rem 1.25rem; margin-bottom: 1.25rem;
}
.brand-block h1 {
  font-size: clamp(1.35rem, 3vw, 1.7rem);
  margin: 0 0 0.2rem; letter-spacing: -0.025em; font-weight: 650;
}
.lead { color: var(--muted); margin: 0; font-size: 0.95rem; max-width: 36rem; }
.toolbar {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem;
}
.btn {
  appearance: none; border: 1px solid var(--line); background: var(--card);
  color: var(--ink); font: inherit; font-size: 0.875rem; font-weight: 550;
  padding: 0.45rem 0.85rem; border-radius: 8px; cursor: pointer;
  box-shadow: var(--shadow); text-decoration: none; display: inline-flex;
  align-items: center; gap: 0.35rem;
}
.btn:hover { border-color: var(--accent); color: var(--accent); }
.btn-primary { background: var(--accent); color: #fff; border-color: var(--accent); }
.btn-primary:hover { background: var(--accent-hover); color: #fff; border-color: var(--accent-hover); }
.toggle {
  display: inline-flex; align-items: center; gap: 0.4rem;
  font-size: 0.85rem; color: var(--muted); user-select: none;
  padding: 0.35rem 0.55rem; background: var(--card); border: 1px solid var(--line);
  border-radius: 8px;
}
.toggle input { accent-color: var(--accent); }
.breadcrumbs {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.35rem;
  font-size: 0.85rem; color: var(--muted); margin-bottom: 1rem;
}
.breadcrumbs a { color: var(--accent); text-decoration: none; font-weight: 550; }
.breadcrumbs a:hover { text-decoration: underline; }
.breadcrumbs .sep { opacity: 0.5; }
.breadcrumbs .current { color: var(--ink); font-weight: 600; word-break: break-all; }
a { color: var(--accent); }
.meta { font-family: var(--mono); font-size: 0.78rem; color: var(--muted); }
.panel {
  background: var(--card); border: 1px solid var(--line); border-radius: var(--radius);
  box-shadow: var(--shadow); overflow: hidden; margin-bottom: 1rem;
}
.panel-head {
  display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
  gap: 0.5rem; padding: 0.85rem 1rem; border-bottom: 1px solid var(--line);
  background: #f8fafc;
}
.panel-head h2 {
  margin: 0; font-size: 0.95rem; font-weight: 650; letter-spacing: -0.01em;
}
.panel-body { padding: 1rem; }
.panel-body.tight { padding: 0; }
.filters {
  display: flex; flex-wrap: wrap; gap: 0.6rem; padding: 0.85rem 1rem;
  border-bottom: 1px solid var(--line); background: #f8fafc;
}
.filters label { display: flex; flex-direction: column; gap: 0.25rem;
  font-size: 0.72rem; font-weight: 600; text-transform: uppercase;
  letter-spacing: 0.04em; color: var(--muted); flex: 1 1 160px; }
.filters input, .filters select {
  font: inherit; font-size: 0.9rem; text-transform: none; letter-spacing: normal;
  font-weight: 450; color: var(--ink); padding: 0.45rem 0.6rem;
  border: 1px solid var(--line); border-radius: 8px; background: #fff;
}
.filters input:focus, .filters select:focus {
  outline: 2px solid rgba(26, 107, 140, 0.25); border-color: var(--accent);
}
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 0.7rem 1rem; border-bottom: 1px solid var(--line);
  vertical-align: top; font-size: 0.92rem; }
th { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.05em;
  color: var(--muted); font-weight: 650; background: #fafbfc; }
tr:last-child td { border-bottom: 0; }
tbody tr:hover td { background: #f5f8fb; }
td a.session-link { font-weight: 600; text-decoration: none; word-break: break-all; }
td a.session-link:hover { text-decoration: underline; }
.badge {
  display: inline-block; padding: 0.12rem 0.5rem; border: 1px solid var(--line);
  border-radius: 6px; font-size: 0.72rem; font-family: var(--mono);
  font-weight: 500; background: #f8fafc; white-space: nowrap;
}
.badge.warn { color: var(--warn); border-color: var(--warn-line); background: var(--warn-bg); }
.badge.bad { color: var(--bad); border-color: var(--bad-line); background: var(--bad-bg); }
.badge.ok { color: var(--ok); border-color: var(--ok-line); background: var(--ok-bg); }
.badge.latest { color: var(--latest); border-color: var(--latest-line); background: var(--latest-bg); }
.banner {
  display: flex; gap: 0.65rem; align-items: flex-start;
  padding: 0.75rem 1rem; border-radius: var(--radius); border: 1px solid;
  margin-bottom: 1rem; font-size: 0.9rem;
}
.banner.bad { background: var(--bad-bg); border-color: var(--bad-line); color: #7a271a; }
.banner.warn { background: var(--warn-bg); border-color: var(--warn-line); color: #7a4d00; }
.banner .banner-title { font-weight: 650; margin-bottom: 0.15rem; }
.banner .banner-body { color: inherit; opacity: 0.92; word-break: break-word; }
.empty {
  padding: 2rem 1.25rem; text-align: center; color: var(--muted);
}
.empty strong { display: block; color: var(--ink); font-size: 1.05rem; margin-bottom: 0.35rem; }
.empty code { font-family: var(--mono); font-size: 0.85rem; background: #eef2f7;
  padding: 0.1rem 0.35rem; border-radius: 4px; }
.list-status {
  padding: 0.5rem 1rem; font-size: 0.8rem; color: var(--muted);
  border-top: 1px solid var(--line); background: #fafbfc;
}
.grid { display: grid; gap: 0.75rem; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); }
.field {
  background: #f8fafc; border: 1px solid var(--line); border-radius: 8px; padding: 0.75rem;
}
.field .label { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.04em;
  color: var(--muted); margin-bottom: 0.3rem; font-weight: 650; }
.field .value { font-family: var(--mono); font-size: 0.88rem; word-break: break-word; }
pre {
  margin: 0; background: #152033; color: #e8eef5; padding: 1rem;
  overflow: auto; font-family: var(--mono); font-size: 0.76rem; line-height: 1.45;
  border-radius: 0 0 var(--radius) var(--radius); max-height: 28rem;
}
.section-nav {
  display: flex; flex-wrap: wrap; gap: 0.4rem; margin: 0 0 1.1rem;
}
.section-nav a {
  font-size: 0.8rem; text-decoration: none; color: var(--muted);
  padding: 0.3rem 0.65rem; border: 1px solid var(--line); border-radius: 999px;
  background: var(--card);
}
.section-nav a:hover { color: var(--accent); border-color: var(--accent); }
.hint { font-size: 0.85rem; color: var(--muted); margin-top: 1rem; }
.footer-meta { margin-top: 1.5rem; font-size: 0.8rem; color: var(--muted); }
.rel-time { white-space: nowrap; }
.rel-time .abs { display: block; font-size: 0.72rem; opacity: 0.75; margin-top: 0.1rem; }
.sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip: rect(0,0,0,0); border: 0; }
@media (max-width: 640px) {
  body { padding: 0.85rem 0.65rem 2.5rem; }
  th:nth-child(4), td:nth-child(4) { display: none; }
  .filters label { flex: 1 1 100%; }
  td, th { padding: 0.55rem 0.7rem; }
}
'@
}

function Get-SharedJs {
    return @'
(function () {
  function parseTs(raw) {
    if (!raw) return null;
    var d = new Date(raw);
    if (!isNaN(d.getTime())) return d;
    // date-only (YYYY-MM-DD)
    if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
      d = new Date(raw + "T00:00:00Z");
      if (!isNaN(d.getTime())) return d;
    }
    return null;
  }
  function relLabel(d) {
    var sec = Math.round((Date.now() - d.getTime()) / 1000);
    var future = sec < 0;
    sec = Math.abs(sec);
    var unit, n;
    if (sec < 45) return future ? "in a moment" : "just now";
    if (sec < 90) { n = 1; unit = "minute"; }
    else if (sec < 3600) { n = Math.round(sec / 60); unit = "minute"; }
    else if (sec < 5400) { n = 1; unit = "hour"; }
    else if (sec < 86400) { n = Math.round(sec / 3600); unit = "hour"; }
    else if (sec < 129600) { n = 1; unit = "day"; }
    else if (sec < 2592000) { n = Math.round(sec / 86400); unit = "day"; }
    else if (sec < 3888000) { n = 1; unit = "month"; }
    else if (sec < 31536000) { n = Math.round(sec / 2592000); unit = "month"; }
    else { n = Math.round(sec / 31536000); unit = "year"; }
    var plural = n === 1 ? unit : unit + "s";
    return future ? ("in " + n + " " + plural) : (n + " " + plural + " ago");
  }
  function refreshRelTimes() {
    var nodes = document.querySelectorAll("[data-ts]");
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var d = parseTs(el.getAttribute("data-ts"));
      if (!d) continue;
      var rel = el.querySelector(".rel");
      if (rel) rel.textContent = relLabel(d);
    }
  }
  function setupRefresh() {
    var btn = document.getElementById("btn-refresh");
    if (btn) btn.addEventListener("click", function () { location.reload(); });
    var tog = document.getElementById("auto-refresh");
    if (!tog) return;
    var key = "session-ui-auto-refresh";
    var saved = localStorage.getItem(key) === "1";
    tog.checked = saved;
    var timer = null;
    function apply() {
      if (timer) { clearInterval(timer); timer = null; }
      localStorage.setItem(key, tog.checked ? "1" : "0");
      if (tog.checked) {
        timer = setInterval(function () { location.reload(); }, 15000);
      }
    }
    tog.addEventListener("change", apply);
    apply();
  }
  function setupListFilters() {
    var q = document.getElementById("filter-q");
    var sort = document.getElementById("filter-sort");
    var tbody = document.getElementById("session-tbody");
    var status = document.getElementById("list-status");
    var emptyFilter = document.getElementById("empty-filter");
    if (!tbody) return;
    function rowText(tr) {
      return (tr.getAttribute("data-search") || "").toLowerCase();
    }
    function rowUpdated(tr) {
      var d = parseTs(tr.getAttribute("data-updated"));
      return d ? d.getTime() : 0;
    }
    function apply() {
      var query = (q && q.value || "").trim().toLowerCase();
      var rows = Array.prototype.slice.call(tbody.querySelectorAll("tr[data-session]"));
      var visible = [];
      rows.forEach(function (tr) {
        var ok = !query || rowText(tr).indexOf(query) !== -1;
        tr.hidden = !ok;
        if (ok) visible.push(tr);
      });
      var mode = sort ? sort.value : "updated-desc";
      visible.sort(function (a, b) {
        if (mode === "name-asc") {
          return (a.getAttribute("data-id") || "").localeCompare(b.getAttribute("data-id") || "");
        }
        if (mode === "name-desc") {
          return (b.getAttribute("data-id") || "").localeCompare(a.getAttribute("data-id") || "");
        }
        if (mode === "updated-asc") return rowUpdated(a) - rowUpdated(b);
        return rowUpdated(b) - rowUpdated(a);
      });
      visible.forEach(function (tr) { tbody.appendChild(tr); });
      var total = rows.length;
      var shown = visible.length;
      if (status) {
        status.textContent = shown === total
          ? (total + " session" + (total === 1 ? "" : "s"))
          : (shown + " of " + total + " sessions");
      }
      if (emptyFilter) emptyFilter.hidden = !(total > 0 && shown === 0);
    }
    if (q) q.addEventListener("input", apply);
    if (sort) sort.addEventListener("change", apply);
    apply();
  }
  document.addEventListener("DOMContentLoaded", function () {
    refreshRelTimes();
    setupRefresh();
    setupListFilters();
    setInterval(refreshRelTimes, 30000);
  });
})();
'@
}

function Format-RelTimeHtml {
    param([string]$Iso)
    $safe = ConvertTo-SafeHtml $Iso
    if ([string]::IsNullOrWhiteSpace($Iso)) {
        return '<span class="meta">—</span>'
    }
    return "<span class=`"rel-time`" data-ts=`"$safe`"><span class=`"rel`">$safe</span><span class=`"abs meta`">$safe</span></span>"
}

function Write-ToolbarHtml {
    param([string]$Context = 'list')
    $autoId = 'auto-refresh'
    return @"
<div class="toolbar" role="group" aria-label="Refresh controls">
  <button type="button" class="btn" id="btn-refresh" title="Reload from disk">Refresh</button>
  <label class="toggle" for="$autoId">
    <input type="checkbox" id="$autoId" />
    Auto-refresh (15s)
  </label>
</div>
"@
}

function Write-ErrorPageHtml {
    param([string]$Title, [string]$Message, [string]$BackHref = '/')
    $css = Get-SharedCss
    $js = Get-SharedJs
    $t = ConvertTo-SafeHtml $Title
    $m = ConvertTo-SafeHtml $Message
    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$t</title>
<style>$css</style>
</head>
<body>
<main>
  <nav class="breadcrumbs" aria-label="Breadcrumb">
    <a href="$BackHref">Sessions</a>
    <span class="sep">/</span>
    <span class="current">$t</span>
  </nav>
  <div class="banner bad" role="alert">
    <div>
      <div class="banner-title">Something went wrong</div>
      <div class="banner-body">$m</div>
    </div>
  </div>
  <p><a class="btn" href="$BackHref">&larr; Back to sessions</a></p>
</main>
<script>$js</script>
</body>
</html>
"@
}

function Write-IndexHtml {
    param([object[]]$Sessions)
    $css = Get-SharedCss
    $js = Get-SharedJs
    $toolbar = Write-ToolbarHtml -Context 'list'
    $root = ConvertTo-SafeHtml $CodeAgent
    $count = if ($Sessions) { $Sessions.Count } else { 0 }

    # Default sort: updated descending (server-side seed; client can re-sort)
    $ordered = @()
    if ($Sessions -and $Sessions.Count -gt 0) {
        $ordered = @($Sessions | Sort-Object {
            $t = $_.updated
            try { [datetime]::Parse([string]$t, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) }
            catch {
                try { [datetime]::ParseExact([string]$t, 'yyyy-MM-dd', $null) }
                catch { [datetime]::MinValue }
            }
        } -Descending)
    }

    $bodyInner = ''
    if ($count -eq 0) {
        $bodyInner = @"
<div class="panel">
  <div class="empty">
    <strong>No sessions yet</strong>
    Create a session folder under <code>_code_agent/{session-id}/</code> with a
    <code>state.json</code>, then hit Refresh. This UI only reads local files —
    nothing is uploaded.
  </div>
</div>
"@
    } else {
        $trs = foreach ($s in $ordered) {
            $id = ConvertTo-SafeHtml $s.id
            $updatedRaw = [string]$s.updated
            $updatedHtml = Format-RelTimeHtml $updatedRaw
            $searchBits = @($s.id, $s.lane, $s.feature_directory, $s.error, $s.phase, $s.owner_agent) |
                Where-Object { $_ } |
                ForEach-Object { [string]$_ }
            $search = ConvertTo-SafeHtml (($searchBits -join ' ').ToLowerInvariant())
            $updatedAttr = ConvertTo-SafeHtml $updatedRaw

            if (-not $s.ok) {
                $laneBadge = '<span class="badge bad">bad state</span>'
                $feature = "<span class=`"badge bad`">$(ConvertTo-SafeHtml $s.error)</span>"
            } else {
                $lane = ConvertTo-SafeHtml $s.lane
                $laneClass = if ($s.lane -match 'unconfirmed|pending') { 'warn' } else { 'ok' }
                $laneBadge = "<span class=`"badge $laneClass`">$lane</span>"
                if ($s.is_latest) { $laneBadge += ' <span class="badge latest">latest</span>' }
                $feature = if ($s.feature_directory) {
                    ConvertTo-SafeHtml $s.feature_directory
                } else { '<em>not set</em>' }
            }
            $link = "<a class=`"session-link`" href=`"/session/$id`">$id</a>"
            "<tr data-session=`"1`" data-id=`"$id`" data-updated=`"$updatedAttr`" data-search=`"$search`"><td>$link</td><td>$laneBadge</td><td class=`"meta`">$feature</td><td>$updatedHtml</td></tr>"
        }

        $bodyInner = @"
<div class="panel">
  <div class="panel-head">
    <h2>Sessions</h2>
    <span class="meta" id="list-count-label">$count on disk</span>
  </div>
  <div class="filters">
    <label for="filter-q">Search name or lane
      <input type="search" id="filter-q" placeholder="e.g. stable-flow or unconfirmed" autocomplete="off"/>
    </label>
    <label for="filter-sort">Sort
      <select id="filter-sort">
        <option value="updated-desc" selected>Updated (newest)</option>
        <option value="updated-asc">Updated (oldest)</option>
        <option value="name-asc">Name (A–Z)</option>
        <option value="name-desc">Name (Z–A)</option>
      </select>
    </label>
  </div>
  <div class="panel-body tight">
    <div id="empty-filter" class="empty" hidden>
      <strong>No matching sessions</strong>
      Try a different name or lane filter, or clear the search box.
    </div>
    <table>
      <thead>
        <tr><th>Session</th><th>Lane</th><th>Spec Kit feature</th><th>Updated</th></tr>
      </thead>
      <tbody id="session-tbody">$($trs -join '')</tbody>
    </table>
  </div>
  <div class="list-status" id="list-status" aria-live="polite">$count sessions</div>
</div>
"@
    }

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Pipeline sessions</title>
<style>$css</style>
</head>
<body>
<main>
  <div class="topbar">
    <div class="brand-block">
      <h1>Pipeline sessions</h1>
      <p class="lead">Local read-only browser for <code>_code_agent/</code>. No cloud, no tokens required.</p>
    </div>
    $toolbar
  </div>
  $bodyInner
  <p class="footer-meta meta">Source: $root</p>
</main>
<script>$js</script>
</body>
</html>
"@
}

function Write-DetailHtml {
    param($Detail)
    $css = Get-SharedCss
    $js = Get-SharedJs
    $toolbar = Write-ToolbarHtml -Context 'detail'
    $id = ConvertTo-SafeHtml $Detail.id

    if (-not $Detail.ok -and $Detail.error -match 'not found') {
        return (Write-ErrorPageHtml -Title 'Session not found' -Message $Detail.error -BackHref '/')
    }

    $errBanner = ''
    if ($Detail.error) {
        $errBanner = @"
<div class="banner warn" role="status">
  <div>
    <div class="banner-title">Soft-fail — partial data</div>
    <div class="banner-body">$(ConvertTo-SafeHtml $Detail.error). Other sections below may still be useful.</div>
  </div>
</div>
"@
    }

    $feature = if ($Detail.feature_directory) {
        $fd = ConvertTo-SafeHtml $Detail.feature_directory
        "<code class=`"meta`">$fd</code>"
    } else { '<em>not set</em>' }

    $blockers = ($Detail.blockers | ForEach-Object { ConvertTo-SafeHtml $_ }) -join ', '
    $laneClass = if ($Detail.lane -match 'unconfirmed|pending') { 'warn' } else { 'ok' }
    $laneStatus = if ($Detail.lane_status) { ConvertTo-SafeHtml $Detail.lane_status } else { 'not set' }
    $flowVal = if ($Detail.flow) { ConvertTo-SafeHtml $Detail.flow } else { 'not set' }

    $stepsRows = ''
    if (-not $Detail.steps -or $Detail.steps.Count -eq 0) {
        $stepsRows = '<div class="empty"><strong>No steps yet</strong><br/>No files under <code>steps/</code>, <code>checkpoints/</code>, or <code>gates/</code>.</div>'
    } else {
        $trs = foreach ($st in $Detail.steps) {
            $mod = Format-RelTimeHtml ([string]$st.modified)
            "<tr><td class=`"meta`">$(ConvertTo-SafeHtml $st.path)</td><td>$mod</td><td class=`"meta`">$($st.size)</td></tr>"
        }
        $stepsRows = "<table><thead><tr><th>Path</th><th>Modified</th><th>Bytes</th></tr></thead><tbody>$($trs -join '')</tbody></table>"
    }

    $eventsSection = ''
    if ($Detail.events -and $Detail.events.Count -gt 0) {
        $note = if ($Detail.events_truncated) {
            '<p class="hint" style="padding:0 1rem 0.5rem">Showing last 100 events (truncated).</p>'
        } else { '' }
        $eventsSection = @"
<section class="panel" id="events">
  <div class="panel-head"><h2>Events</h2><span class="meta">events.jsonl</span></div>
  $note
  <pre>$(ConvertTo-SafeHtml (ConvertTo-PrettyJson $Detail.events))</pre>
</section>
"@
    } else {
        $eventsSection = @"
<section class="panel" id="events">
  <div class="panel-head"><h2>Events</h2><span class="meta">optional</span></div>
  <div class="empty"><strong>No events.jsonl</strong><br/>This session has no event log on disk yet.</div>
</section>
"@
    }

    $stateJson = if ($Detail.state) { ConvertTo-SafeHtml (ConvertTo-PrettyJson $Detail.state) } else {
        ConvertTo-SafeHtml '{"note":"state.json unavailable"}'
    }

    $pathSafe = ConvertTo-SafeHtml $Detail.path

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Session $id</title>
<style>$css</style>
</head>
<body>
<main>
  <nav class="breadcrumbs" aria-label="Breadcrumb">
    <a href="/">Sessions</a>
    <span class="sep">/</span>
    <span class="current">$id</span>
  </nav>
  <div class="topbar">
    <div class="brand-block">
      <h1>$id</h1>
      <p class="lead">File-backed session detail — offline, secrets redacted.</p>
    </div>
    $toolbar
  </div>
  $errBanner
  <nav class="section-nav" aria-label="On this page">
    <a href="#overview">Overview</a>
    <a href="#spec-kit">Spec Kit</a>
    <a href="#lane">Lane</a>
    <a href="#agent">Agent handoff</a>
    <a href="#steps">Steps</a>
    <a href="#events">Events</a>
  </nav>

  <section class="panel" id="overview">
    <div class="panel-head"><h2>Overview</h2></div>
    <div class="panel-body">
      <div class="grid">
        <div class="field"><div class="label">Session id</div><div class="value">$id</div></div>
        <div class="field"><div class="label">Phase</div><div class="value">$(ConvertTo-SafeHtml $Detail.phase)</div></div>
        <div class="field"><div class="label">Owner agent</div><div class="value">$(ConvertTo-SafeHtml $Detail.owner_agent)</div></div>
        <div class="field"><div class="label">Path</div><div class="value">$pathSafe</div></div>
      </div>
    </div>
  </section>

  <section class="panel" id="spec-kit">
    <div class="panel-head"><h2>Spec Kit</h2></div>
    <div class="panel-body">
      <div class="field">
        <div class="label">Feature directory</div>
        <div class="value">$feature</div>
      </div>
      <p class="hint">Path is a repo-relative reference (copy from here; the browser cannot open local files).</p>
    </div>
  </section>

  <section class="panel" id="lane">
    <div class="panel-head"><h2>Lane</h2></div>
    <div class="panel-body">
      <div class="grid">
        <div class="field"><div class="label">Lane / flow</div><div class="value"><span class="badge $laneClass">$(ConvertTo-SafeHtml $Detail.lane)</span></div></div>
        <div class="field"><div class="label">Lane status</div><div class="value">$laneStatus</div></div>
        <div class="field"><div class="label">Flow field</div><div class="value">$flowVal</div></div>
      </div>
    </div>
  </section>

  <section class="panel" id="agent">
    <div class="panel-head"><h2>Agent handoff</h2></div>
    <div class="panel-body">
      <div class="grid">
        <div class="field"><div class="label">Phase</div><div class="value">$(ConvertTo-SafeHtml $Detail.phase)</div></div>
        <div class="field"><div class="label">Owner agent</div><div class="value">$(ConvertTo-SafeHtml $Detail.owner_agent)</div></div>
        <div class="field"><div class="label">Last gate</div><div class="value">$(ConvertTo-SafeHtml $Detail.last_gate)</div></div>
        <div class="field"><div class="label">Blockers</div><div class="value">$blockers</div></div>
      </div>
    </div>
    <div class="panel-head" style="border-top:1px solid var(--line); border-bottom:0"><h2 style="font-size:0.85rem">state.json (redacted)</h2></div>
    <pre>$stateJson</pre>
  </section>

  <section class="panel" id="steps">
    <div class="panel-head"><h2>Steps / checkpoints</h2><span class="meta">$($Detail.steps.Count) file(s)</span></div>
    <div class="panel-body tight">
      $stepsRows
    </div>
  </section>

  $eventsSection

  <p class="hint">$(ConvertTo-SafeHtml $Detail.usage_note)</p>
  <p class="footer-meta"><a href="/">&larr; Back to sessions</a></p>
</main>
<script>$js</script>
</body>
</html>
"@
}

function Write-StaticSite {
    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
    $sessions = @(Get-SessionSummaries)
    Set-Content -LiteralPath (Join-Path $OutDir 'index.html') -Value (Write-IndexHtml -Sessions $sessions) -Encoding utf8
    $sessionsDir = Join-Path $OutDir 'session'
    if (-not (Test-Path $sessionsDir)) { New-Item -ItemType Directory -Path $sessionsDir | Out-Null }
    foreach ($s in $sessions) {
        $detail = Get-SessionDetail -SessionId $s.id
        Set-Content -LiteralPath (Join-Path $sessionsDir "$($s.id).html") -Value (Write-DetailHtml -Detail $detail) -Encoding utf8
    }
    # Soft-fail demo: if someone asks for unknown, static site won't have it; server handles dynamically
    Write-Host "Wrote static site to $OutDir ($($sessions.Count) session(s))"
}

function Invoke-Smoke {
    Write-Host "Smoke: scanning $CodeAgent"
    $sessions = @(Get-SessionSummaries)
    Write-Host "  sessions: $($sessions.Count)"

    $indexEmpty = Write-IndexHtml -Sessions @()
    if ($indexEmpty -notmatch 'No sessions yet') { throw 'Empty state HTML missing hint' }
    if ($indexEmpty -notmatch 'btn-refresh') { throw 'list missing Refresh button' }
    if ($indexEmpty -notmatch 'auto-refresh') { throw 'list missing auto-refresh toggle' }

    $target = $sessions | Where-Object { $_.id -eq '20260719-stable-flow' } | Select-Object -First 1
    if (-not $target) {
        Write-Host "  WARN sample session 20260719-stable-flow not present — list-only smoke"
        return
    }
    if (-not $target.ok) { throw "sample session soft-failed unexpectedly: $($target.error)" }
    if ($target.feature_directory -notmatch '005-stable-flow') {
        Write-Host "  WARN feature_directory unexpected: $($target.feature_directory)"
    }

    $listHtml = Write-IndexHtml -Sessions $sessions
    if ($listHtml -notmatch 'filter-q') { throw 'list missing search filter' }
    if ($listHtml -notmatch 'filter-sort') { throw 'list missing sort control' }
    if ($listHtml -notmatch [regex]::Escape($target.id)) { throw 'list missing sample session id' }
    if ($listHtml -notmatch 'data-ts=') { throw 'list missing relative timestamp hooks' }

    $detail = Get-SessionDetail -SessionId $target.id
    if (-not $detail.feature_directory) { throw 'detail missing feature_directory' }
    if (-not ($detail.steps | Where-Object { $_.path -match 'steps/' })) {
        Write-Host '  WARN no steps/* files (ok if session has none)'
    } else {
        Write-Host "  steps: $($detail.steps.Count)"
    }
    $html = Write-DetailHtml -Detail $detail
    if ($html -notmatch 'Usage / tokens unavailable') { throw 'detail missing usage placeholder' }
    if ($html -notmatch [regex]::Escape($target.id)) { throw 'detail missing session id' }
    foreach ($section in @('overview', 'spec-kit', 'lane', 'agent', 'steps', 'events')) {
        if ($html -notmatch "id=`"$section`"") { throw "detail missing section #$section" }
    }
    if ($html -notmatch 'breadcrumbs') { throw 'detail missing breadcrumbs' }
    if ($html -notmatch 'Soft-fail' -and $detail.error) { Write-Host '  soft-fail banner present' }

    $missing = Get-SessionDetail -SessionId '__no-such-session__'
    $missHtml = Write-DetailHtml -Detail $missing
    if ($missHtml -notmatch 'Something went wrong|Session not found') {
        throw 'missing session page should be friendly'
    }

    # Soft-fail row
    $badDir = Join-Path $CodeAgent '_smoke-bad-state'
    $created = $false
    try {
        New-Item -ItemType Directory -Path $badDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $badDir 'state.json') -Value '{not-json' -Encoding utf8
        $created = $true
        $all = @(Get-SessionSummaries)
        $bad = $all | Where-Object { $_.id -eq '_smoke-bad-state' } | Select-Object -First 1
        if (-not $bad -or $bad.ok) { throw 'expected soft-fail row for bad state.json' }
        $good = $all | Where-Object { $_.id -eq '20260719-stable-flow' -and $_.ok } | Select-Object -First 1
        if (-not $good) { throw 'good session disappeared when bad row present' }
        $listWithBad = Write-IndexHtml -Sessions $all
        if ($listWithBad -notmatch 'bad state') { throw 'list should show bad-state badge' }
        Write-Host '  soft-fail bad state.json: OK'
    } finally {
        if ($created -and (Test-Path $badDir)) { Remove-Item -LiteralPath $badDir -Recurse -Force }
    }
    Write-Host 'Smoke OK'
}

function Start-SessionUiServer {
    $prefix = "http://127.0.0.1:$Port/"
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($prefix)
    try {
        $listener.Start()
    } catch {
        throw "Failed to bind $prefix — $($_.Exception.Message). Try -Port another value."
    }
    Write-Host "Session UI: $prefix  (Ctrl+C to stop)"
    Write-Host "Repo: $RepoRoot"
    Write-Host "Sessions: $CodeAgent"

    try {
        while ($listener.IsListening) {
            $ctx = $listener.GetContext()
            $req = $ctx.Request
            $res = $ctx.Response
            try {
                $path = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimEnd('/'))
                if ([string]::IsNullOrEmpty($path)) { $path = '/' }

                if ($path -eq '/' -or $path -eq '/index.html') {
                    $body = Write-IndexHtml -Sessions @(Get-SessionSummaries)
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $res.ContentType = 'text/html; charset=utf-8'
                    $res.StatusCode = 200
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                }
                elseif ($path -match '^/session/([^/]+)$') {
                    $sid = $Matches[1]
                    $detail = Get-SessionDetail -SessionId $sid
                    $body = Write-DetailHtml -Detail $detail
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $res.ContentType = 'text/html; charset=utf-8'
                    $res.StatusCode = if ($detail.error -match 'not found') { 404 } else { 200 }
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                }
                elseif ($path -eq '/health') {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('ok')
                    $res.ContentType = 'text/plain'
                    $res.StatusCode = 200
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                }
                else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('Not found')
                    $res.StatusCode = 404
                    $res.ContentType = 'text/plain'
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                }
            } catch {
                $body = Write-ErrorPageHtml -Title 'Request failed' -Message $_.Exception.Message -BackHref '/'
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $res.StatusCode = 500
                $res.ContentType = 'text/html; charset=utf-8'
                try { $res.OutputStream.Write($bytes, 0, $bytes.Length) } catch { }
            } finally {
                try { $res.OutputStream.Close() } catch { }
                try { $res.Close() } catch { }
            }
        }
    } finally {
        $listener.Stop()
        $listener.Close()
    }
}

# --- main ---
if ($Smoke) {
    Invoke-Smoke
    exit 0
}

Write-StaticSite

if ($GenerateOnly) {
    Write-Host "Open file://$((Join-Path $OutDir 'index.html') -replace ' ', '%20')"
    exit 0
}

Start-SessionUiServer
