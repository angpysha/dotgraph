#!/usr/bin/env pwsh
# Create or checkout a branch: {type}/{WW}-{slug} (ISO week, zero-padded).
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Type,

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [int]$Week = 0,

    [Parameter(Mandatory = $false)]
    [string]$Date,

    [switch]$DryRun,

    [switch]$AllowExisting,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

$AllowedTypes = @('feature', 'fix', 'chore', 'docs', 'refactor', 'test', 'spike')

if ($Help) {
    Write-Host @"
Usage: ./create-branch.ps1 -Type <type> -Description <text> [-Week N] [-Date yyyy-MM-dd] [-DryRun] [-AllowExisting]

  -Type           One of: $($AllowedTypes -join ', ')
  -Description    Short description (normalized to slug)
  -Week           Explicit ISO week 1-53 (wins over -Date)
  -Date           yyyy-MM-dd — compute ISO week from this date
  -DryRun         Print BRANCH_NAME only; no git changes
  -AllowExisting  If local branch exists, checkout instead of erroring

Example:
  pwsh ./create-branch.ps1 -Type feature -Description 'speckit branch format' -Week 33 -DryRun
"@
    exit 0
}

function ConvertTo-Slug {
    param([string]$Text)
    $s = $Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-' -replace '-{2,}', '-' -replace '^-', '' -replace '-$', ''
    if ([string]::IsNullOrWhiteSpace($s)) {
        throw "Description produced an empty slug after normalization."
    }
    # Keep branch names under common host limits (244); leave headroom for type/week
    $maxSlug = 180
    if ($s.Length -gt $maxSlug) {
        $s = $s.Substring(0, $maxSlug) -replace '-$', ''
    }
    return $s
}

function Get-IsoWeekNumber {
    param([datetime]$When)
    return [System.Globalization.ISOWeek]::GetWeekOfYear($When)
}

if ([string]::IsNullOrWhiteSpace($Type) -or [string]::IsNullOrWhiteSpace($Description)) {
    [Console]::Error.WriteLine("ERROR: -Type and -Description are required (non-interactive). Ask the user if missing from context.")
    exit 1
}

$normalizedType = $Type.Trim().ToLowerInvariant()
if ($AllowedTypes -notcontains $normalizedType) {
    [Console]::Error.WriteLine("ERROR: Invalid -Type '$Type'. Allowed: $($AllowedTypes -join ', ')")
    exit 1
}

$weekNum = 0
if ($Week -ne 0) {
    if ($Week -lt 1 -or $Week -gt 53) {
        [Console]::Error.WriteLine("ERROR: -Week must be between 1 and 53 (got $Week)")
        exit 1
    }
    $weekNum = $Week
}
elseif (-not [string]::IsNullOrWhiteSpace($Date)) {
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        [Console]::Error.WriteLine("ERROR: -Date must be yyyy-MM-dd (got '$Date')")
        exit 1
    }
    $weekNum = Get-IsoWeekNumber -When $parsed
}
else {
    $weekNum = Get-IsoWeekNumber -When (Get-Date)
}

$weekDisplay = '{0:D2}' -f $weekNum
$slug = ConvertTo-Slug -Text $Description
$branchName = "$normalizedType/$weekDisplay-$slug"

Write-Output "BRANCH_NAME: $branchName"

if ($DryRun) {
    Write-Output "DRY_RUN: true"
    exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine("ERROR: git is not on PATH")
    exit 1
}

$inside = & git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne 'true') {
    [Console]::Error.WriteLine("ERROR: not inside a git work tree")
    exit 1
}

$existingLocal = & git show-ref --verify --quiet "refs/heads/$branchName" 2>$null
$exists = ($LASTEXITCODE -eq 0)

if ($exists) {
    if (-not $AllowExisting) {
        [Console]::Error.WriteLine("ERROR: local branch '$branchName' already exists. Re-run with -AllowExisting to checkout, or choose a different description.")
        exit 1
    }
    & git checkout $branchName
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("ERROR: failed to checkout existing branch '$branchName'")
        exit $LASTEXITCODE
    }
    Write-Output "ACTION: checked_out"
    exit 0
}

& git checkout -b $branchName
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("ERROR: failed to create branch '$branchName'")
    exit $LASTEXITCODE
}

Write-Output "ACTION: created"
exit 0
