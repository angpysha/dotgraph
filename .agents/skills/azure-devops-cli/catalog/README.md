# Azure DevOps query recipes

Named read-only queries for `az-devops-query.ps1`. Each recipe applies a JMESPath `--query`
projection before TOON encoding for maximum token savings.

## Usage

```powershell
$Q = '.cursor/skills/azure-devops-cli/scripts/az-devops-query.ps1'

pwsh $Q -ListRecipes
pwsh $Q -Recipe pr-list -Session 20260610-my-feature -Stats
pwsh $Q -Recipe pr-show -Vars @{ id = 42 } -SaveOnly
pwsh $Q -Recipe pipeline-runs -Vars @{ pipelineId = 12; top = 5 }
pwsh $Q -Recipe work-item-show -Vars @{ id = 12345 }
```

## Recipes

### pr-list

List pull requests in the manifest `pr.repo` repository.

- **Phase:** 10 (closeout / review)
- **Vars:** none
- **Output:** id, title, status, source/target branches, author, url

### pr-show

Single pull request details.

- **Phase:** 10
- **Vars:** `id` (required)
- **Output:** id, title, status, description, branches, merge status, url

### pipeline-list

All pipeline definitions in the project.

- **Phase:** 7 (devops verify)
- **Vars:** none

### pipeline-runs

Recent runs for one pipeline.

- **Phase:** 7
- **Vars:** `pipelineId` (required), `top` (optional)

### pipeline-run-show

Single pipeline run status.

- **Phase:** 7
- **Vars:** `runId`, `pipelineId` (both required)

### work-item-show

Work item by id.

- **Phase:** 6 (planning link)
- **Vars:** `id` (required)

### work-item-query

WIQL query results.

- **Phase:** 6
- **Vars:** `wiql` (required) — e.g. `"SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project"`

### repo-list

Git repositories in the project.

- **Phase:** 6
- **Vars:** none

## Token workflow

1. Query writes **JSON** (source of truth) + **TOON** (LLM view) under `_code_agent/.../artifacts/ado/`
2. Cite **paths** in chat during SDLC sessions — do not paste full TOON bodies
3. Use `-SaveOnly` for index lines only; `-MaxChars 2000` to cap stdout TOON

## Adding recipes

Edit `catalog/recipes.json`. Each entry needs:

- `description`, `phase`, `azArgs`, optional `query`, `maxRows`, `vars`
