---
name: tasks-beads
description: >-
  br-first Spec Kit tasks helpers: CRITICAL beads readiness gate and tasks.md
  projection renderer. Use when tasks-beads presets are installed or before
  /speckit.tasks / /speckit.implement that mutate beads.
disable-model-invocation: true
---

# Tasks Beads Skill (`br`-first)

Canonical task graph lives in **beads rust (`br`)**. `tasks.md` is a **generated
projection**. Never use legacy **`bd`**.

**Contracts** (feature `011-speckit-tasks-beads`):

- `specs/011-speckit-tasks-beads/contracts/beads-ready-gate.md`
- `specs/011-speckit-tasks-beads/contracts/tasks-md-projection.md`
- `specs/011-speckit-tasks-beads/contracts/br-task-graph-cli.md`
- `specs/011-speckit-tasks-beads/contracts/implement-lifecycle.md`

## Order of operations

1. **Assert beads ready** (hard gate)
2. Create/reconcile task + dependency graph in `br`
3. Optional grill (recommend when parallel-ready or cross-story deps)
4. **Render** `tasks.md` from `br`
5. During implement: claim/close in `br`, then **re-render**

## Assert beads ready (CRITICAL)

```powershell
# Catalog / pipeline home
$ASSERT = 'core/skills/tasks-beads/scripts/Assert-BeadsReady.ps1'

# After agentic-tool apply
# $ASSERT = '.agents/skills/tasks-beads/scripts/Assert-BeadsReady.ps1'
# $ASSERT = '.cursor/skills/tasks-beads/scripts/Assert-BeadsReady.ps1'

pwsh -NoProfile -File $ASSERT
```

- Exit `0` → continue
- Non-zero → phase **FAILED**; banner must include `CRITICAL` and ❌ lines
- Do **not** write `tasks.md` or invent a markdown-first fallback

### Banner self-check

Expected title line: `CRITICAL — BEADS NOT INITIALIZED`  
Expected cause bullet mentions beads rust (`br`)  
Expected STOP line forbids markdown-first fallback  
Compare against `contracts/beads-ready-gate.md` if the banner drifts.

## Render `tasks.md` from `br`

```powershell
$RENDER = 'core/skills/tasks-beads/scripts/Render-TasksFromBr.ps1'

pwsh -NoProfile -File $RENDER `
  -FeatureLabel 'speckit:011-speckit-tasks-beads' `
  -OutFile 'specs/011-speckit-tasks-beads/tasks.md' `
  -FeatureTitle 'Spec Kit Tasks Presets & Beads Tracker'
```

Requires issues labeled with `-FeatureLabel`. Idempotent overwrite of the projection.

## Presets

Install via `speckit-tools/packages.yml`:

| Preset | Role |
|--------|------|
| `br-task-graph` | Append `speckit.tasks` — create graph in `br` first |
| `render-tasks` | Append `speckit.tasks` — render projection |
| `grill-tasks` | Append `speckit.tasks` — optional / risk-recommended grill |
| `implement-br-task` | Append `speckit.implement` — start/finish sync |

## Hard locks

- **`br` only** — never `bd`
- `br` is authoritative; markdown drift → refresh from `br`
- Missing beads → CRITICAL gate, fail the phase
