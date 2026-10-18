## Mandatory: render `tasks.md` from `br`

When this preset is installed, after the canonical beads graph exists, agents MUST
**generate** `specs/<feature>/tasks.md` as a projection of `br` — not as an independent
database. **Never** use `bd`.

### 1. Hard gate

```powershell
pwsh -NoProfile -File core/skills/tasks-beads/scripts/Assert-BeadsReady.ps1
```

On failure: CRITICAL banner → **stop**. Do not write `tasks.md`.

### 2. Render

```powershell
pwsh -NoProfile -File core/skills/tasks-beads/scripts/Render-TasksFromBr.ps1 `
  -FeatureLabel 'speckit:<feature-directory-basename>' `
  -OutFile 'specs/<feature-directory>/tasks.md' `
  -FeatureTitle '<name from plan/spec>'
```

Required projection content (contract):

1. Authority notice (`br` canonical)
2. Parallel execution section (`[P]` / ready batches)
3. Checklist lines with **`br` ids** (friendly `T###` optional)
4. Mermaid dependency graph matching `br dep`

### 3. Drift / refresh

- Manual markdown edits that conflict with `br` → **report drift** and refresh from `br`
- **Never** silently import conflicting markdown into `br` (v1)
- Missing `tasks.md` → regenerate from `br` only

### 4. When to re-render

- After initial graph create/reconcile
- After accepted grilling changes
- After implement start/claim or finish/close
