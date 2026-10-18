# az-devops-query.ps1 — read-only Azure DevOps queries with JSON source + TOON projection.
param(
    [string]$Recipe = '',
    [hashtable]$Vars = @{},
    [string]$Session = '',
    [switch]$ListRecipes,
    [switch]$SaveOnly,
    [switch]$PrintToon,
    [switch]$NoToon,
    [int]$MaxChars = 0,
    [switch]$Stats,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AzArguments
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/azure-devops-common.ps1"

if (-not $PSBoundParameters.ContainsKey('PrintToon')) {
    $PrintToon = $true
}

function Get-OutputDir {
    param([string]$RepoRoot, [string]$SessionCode)
    if ($SessionCode) {
        return Join-Path $RepoRoot "_code_agent/$SessionCode/artifacts/ado"
    }
    return Join-Path $RepoRoot '_code_agent/artifacts/ado'
}

function Limit-JsonRows {
    param(
        [string]$Json,
        [int]$MaxRows
    )
    if ($MaxRows -le 0) { return $Json }
    try {
        $data = $Json | ConvertFrom-Json
        if ($data -is [System.Array] -and $data.Count -gt $MaxRows) {
            $trimmed = $data | Select-Object -First $MaxRows
            return ($trimmed | ConvertTo-Json -Depth 20 -Compress)
        }
    }
    catch { }
    return $Json
}

function Write-RecipeListToon {
    $catalog = Get-RecipeCatalog
    $rows = @()
    foreach ($prop in $catalog.recipes.PSObject.Properties) {
        $id = $prop.Name
        $r = $prop.Value
        $requiredVars = @()
        if ($r.vars) {
            foreach ($vprop in $r.vars.PSObject.Properties) {
                if ($vprop.Value.required) { $requiredVars += $vprop.Name }
            }
        }
        $rows += [ordered]@{
            id          = $id
            description = [string]$r.description
            phase       = [string]$r.phase
            vars        = ($requiredVars -join ',')
        }
    }
    $json = @{ recipes = $rows } | ConvertTo-Json -Depth 6 -Compress
    $toon = ConvertTo-Toon -Json $json
    Write-Output $toon
}

function Resolve-RecipeAzArgs {
    param(
        $RecipeDef,
        [hashtable]$Vars
    )
    $azArgs = @()
    foreach ($arg in $RecipeDef.azArgs) {
        $expanded = Expand-RecipeTemplate -Template ([string]$arg) -Vars $Vars
        $azArgs += $expanded
    }
    if ($Vars.ContainsKey('top') -and $Vars['top']) {
        $hasTop = $false
        for ($i = 0; $i -lt $azArgs.Count; $i++) {
            if ($azArgs[$i] -eq '--top') { $hasTop = $true }
        }
        if (-not $hasTop) {
            $azArgs += @('--top', [string]$Vars['top'])
        }
    }
    if ($RecipeDef.query) {
        $hasQuery = $false
        for ($i = 0; $i -lt $azArgs.Count; $i++) {
            if ($azArgs[$i] -eq '--query') { $hasQuery = $true }
        }
        if (-not $hasQuery) {
            $azArgs += @('--query', [string]$RecipeDef.query)
        }
    }
    return $azArgs
}

function Test-RequiredRecipeVars {
    param(
        $RecipeDef,
        [hashtable]$Vars,
        [string]$RecipeId
    )
    if (-not $RecipeDef.vars) { return }
    foreach ($vprop in $RecipeDef.vars.PSObject.Properties) {
        $name = $vprop.Name
        $meta = $vprop.Value
        if ($meta.required -and -not $Vars.ContainsKey($name)) {
            throw "Recipe '$RecipeId' requires -Vars @{ $name = '...' }"
        }
    }
}

# --- List recipes ---
if ($ListRecipes) {
    Write-RecipeListToon
    exit 0
}

if (-not (Test-AzCliInstalled)) {
    throw 'Azure CLI (az) not found'
}
Ensure-AzureDevOpsExtension

$repoRoot = Find-RepoRoot
$ctx = Resolve-DevOpsContext -RepoRoot $repoRoot

$recipeId = if ($Recipe) { $Recipe } else { 'passthrough' }
$azArgs = @()
$query = ''
$maxRows = 50

if ($Recipe) {
    $catalog = Get-RecipeCatalog
    if (-not $catalog.recipes.$Recipe) {
        $known = ($catalog.recipes.PSObject.Properties.Name) -join ', '
        throw "Unknown recipe '$Recipe'. Known: $known"
    }
    $recipeDef = $catalog.recipes.$Recipe
    Test-RequiredRecipeVars -RecipeDef $recipeDef -Vars $Vars -RecipeId $Recipe
    $azArgs = Resolve-RecipeAzArgs -RecipeDef $recipeDef -Vars $Vars
    if ($recipeDef.maxRows) { $maxRows = [int]$recipeDef.maxRows }
    if ($ctx.repository -and $Recipe -in @('pr-list', 'pr-show')) {
        $hasRepo = $false
        for ($i = 0; $i -lt $azArgs.Count; $i++) {
            if ($azArgs[$i] -in '--repository', '-r') { $hasRepo = $true }
        }
        if (-not $hasRepo) {
            $azArgs = @('--repository', $ctx.repository) + $azArgs
        }
    }
}
elseif ($AzArguments -and $AzArguments.Count -gt 0) {
    $azArgs = $AzArguments
    if (-not $NoToon) {
        Write-Warning 'Passthrough query: TOON savings may be limited for nested JSON. Prefer -Recipe when possible.'
    }
}
else {
    Write-Host @'
Usage:
  pwsh az-devops-query.ps1 -Recipe pr-list [-Session SESSION] [-SaveOnly] [-Stats]
  pwsh az-devops-query.ps1 -Recipe pr-show -Vars @{ id = 42 }
  pwsh az-devops-query.ps1 -ListRecipes
  pwsh az-devops-query.ps1 repos pr list --status active

Writes JSON + TOON under _code_agent/.../artifacts/ado/
'@
    exit 1
}

$jsonRaw = Invoke-AzDevOpsJson -AzArgs $azArgs -Organization $ctx.organization -Project $ctx.project
$jsonShaped = Limit-JsonRows -Json $jsonRaw -MaxRows $maxRows

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$baseName = "$timestamp-$recipeId"
$outDir = Get-OutputDir -RepoRoot $repoRoot -SessionCode $Session
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$jsonPath = Join-Path $outDir "$baseName.json"
$toonPath = Join-Path $outDir "$baseName.toon"
Set-Content -Path $jsonPath -Value $jsonShaped -Encoding UTF8

$jsonRel = $jsonPath.Substring($repoRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar, '/')
$toonRel = $toonPath.Substring($repoRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar, '/')

$toon = ''
if (-not $NoToon) {
    $toon = ConvertTo-Toon -Json $jsonShaped -Stats:$Stats
    Set-Content -Path $toonPath -Value $toon -Encoding UTF8
}

$jsonBytes = (Get-Item $jsonPath).Length
$toonBytes = if ($toonPath -and (Test-Path $toonPath)) { (Get-Item $toonPath).Length } else { 0 }

Write-Host "OK   json -> $jsonRel ($jsonBytes bytes)"
if ($toonRel) {
    Write-Host "OK   toon -> $toonRel ($toonBytes bytes)"
}
if ($Session) {
    Write-Host "HINT checkpoint link $Session <phase> <step> artifacts/ado/$baseName.toon"
}

if ($SaveOnly) {
    Write-Output "recipe=$recipeId json=$jsonRel toon=$toonRel bytes=$jsonBytes"
    exit 0
}

if ($PrintToon -and $toon) {
    $output = $toon
    if ($MaxChars -gt 0 -and $output.Length -gt $MaxChars) {
        $output = $output.Substring(0, $MaxChars) + "`n... (truncated; full: $toonRel)"
    }
    Write-Output $output
}

exit 0
