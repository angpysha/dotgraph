# Validates a requirements document has required sections and structure.
param([Parameter(Mandatory)][string]$ReqFile)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ReqFile)) {
    Write-Host "FAIL: File not found: $ReqFile"
    exit 1
}

$content = Get-Content $ReqFile -Raw
$missing = 0

$required = @(
    '## Meta',
    '## Problem Statement',
    '## Scope',
    '## Functional Requirements',
    '## Acceptance Criteria',
    '## Open Questions',
    '## Migration Flags'
)

foreach ($section in $required) {
    if ($content -notlike "*$section*") {
        Write-Host "FAIL: Missing section: $section"
        $missing++
    }
}

if ($content -notmatch 'FR-[0-9]+') {
    Write-Host 'FAIL: No functional requirements (FR-N) found'
    $missing++
}

if ($content -notmatch 'AC-[0-9]+') {
    Write-Host 'FAIL: No acceptance criteria (AC-N) found'
    $missing++
}

if ($content -match 'open questions' -and $content -match '\| OQ-[0-9]+') {
    Select-String -InputObject $content -Pattern '\| OQ-[0-9]+' -AllMatches |
        ForEach-Object { $_.Matches } |
        ForEach-Object {
            $line = $_.Value
            if ($line -notmatch 'resolved|blocking|deferred') {
                Write-Warning "WARN: Open question may lack status: $line"
            }
        }
}

if ($missing -gt 0) {
    Write-Host "FAIL: $missing validation error(s)"
    exit 1
}

Write-Host "PASS: Requirements validation OK — $ReqFile"
