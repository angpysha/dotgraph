# Validates implementation plan exists and beads has open issues.
param(
    [Parameter(Mandatory)][string]$Nnnn,
    [string]$Session = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/sdlc-session.ps1"

$plan = Join-Path (Get-DesignDir -Session $Session) "IMPLEMENTATION-PLAN-$Nnnn.md"
$errors = 0

if (-not (Test-Path $plan)) {
    Write-Host "FAIL: Implementation plan not found: $plan"
    $errors++
}
else {
    $text = Get-Content $plan -Raw
    if ($text -notmatch '```mermaid') {
        Write-Host 'FAIL: Implementation plan missing dependency graph (Mermaid)'
        $errors++
    }
}

if (Get-Command br -ErrorAction SilentlyContinue) {
    & br lint 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'WARN: br lint reported issues (non-fatal)'
    }

    $openJson = & br list --status=open --json 2>$null
    $openCount = 0
    if ($openJson) {
        try {
            $items = $openJson | ConvertFrom-Json
            if ($items -is [array]) { $openCount = $items.Count }
            elseif ($items) { $openCount = 1 }
        }
        catch { $openCount = ([regex]::Matches($openJson, '"id"')).Count }
    }

    if ($openCount -eq 0) {
        Write-Host 'FAIL: No open beads issues found — Team Lead must create tasks'
        $errors++
    }
    else {
        Write-Host "INFO: $openCount open issue(s) in beads"
    }
}
else {
    Write-Warning 'WARN: br not found — skipping beads validation'
}

if ($errors -gt 0) {
    Write-Host "FAIL: $errors task validation error(s)"
    exit 1
}

Write-Host "PASS: Task validation OK — $plan"
