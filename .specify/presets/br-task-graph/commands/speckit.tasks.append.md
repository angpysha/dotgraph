## Mandatory: `br`-first task graph (before `tasks.md`)

When this preset is installed, `/speckit.tasks` MUST treat **beads rust (`br`)** as the
canonical task graph. Do **not** invent a markdown-first task list and sync it into beads
later. **Never** use legacy `bd`.

### 1. Hard gate — beads ready

Run before any create/reconcile:

```powershell
pwsh -NoProfile -File core/skills/tasks-beads/scripts/Assert-BeadsReady.ps1
# After apply: .agents/skills/tasks-beads/scripts/Assert-BeadsReady.ps1
# or .cursor/skills/tasks-beads/scripts/Assert-BeadsReady.ps1
```

If this fails: **stop the phase**. The CRITICAL ❌ banner is the only allowed outcome —
do not write `tasks.md`, do not invent placeholder tasks.

### 2. Derive proposed work

From `spec.md`, `plan.md`, and optional `data-model.md` / `contracts/`, propose tasks with:

- Clear titles and descriptions (include file scope when known)
- Dependencies (what blocks what)
- Parent/epic when the feature has one

### 3. Create / reconcile in `br` (idempotent)

Use feature label: `speckit:<feature-directory-basename>`  
Example: `speckit:011-speckit-tasks-beads`

```bash
br create "<title>" -t task -d "<description>" -l "speckit:<feature>" --json
# Prefer --parent <epic-id> when an epic exists
br dep add <issue> <depends-on>
br ready --json
```

Before creating: search existing issues with the feature label (`br list -l … --json`) and
**update/reconcile** instead of duplicating.

Parallelism is expressed via **dependencies + `br ready`**, not markdown-only ordering.

### 4. Render projection (required to finish)

After the graph is reconciled, render `tasks.md` (see **render-tasks** preset / skill):

```powershell
pwsh -NoProfile -File core/skills/tasks-beads/scripts/Render-TasksFromBr.ps1 `
  -FeatureLabel 'speckit:<feature>' `
  -OutFile 'specs/<feature>/tasks.md' `
  -FeatureTitle '<Feature Name>'
```

Tasks phase is **not complete** until the projection exists and matches `br`.

### Out of scope

- GitHub Issues / Azure DevOps as the primary tracker for this path
- Silent markdown → `br` import
- Using `bd`
