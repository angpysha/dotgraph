# Preset: `br-task-graph`

Append-only Spec Kit preset for **`speckit.tasks`**: create/reconcile the canonical
task + dependency graph in **beads rust (`br`)** before writing `tasks.md`.

## Install

```bash
specify preset add --dev speckit-tools/presets/br-task-graph
# or
agentic-tool speckit-packages install --id br-task-graph
```

## Agent `br` patterns

See `specs/011-speckit-tasks-beads/contracts/br-task-graph-cli.md`.

```bash
pwsh core/skills/tasks-beads/scripts/Assert-BeadsReady.ps1
br create "…" -t task -d "…" -l "speckit:<feature>" --json
br dep add <issue> <depends-on>
br ready --json
# then render (render-tasks preset)
pwsh core/skills/tasks-beads/scripts/Render-TasksFromBr.ps1 -FeatureLabel 'speckit:<feature>' -OutFile 'specs/<feature>/tasks.md' -FeatureTitle '…'
```

**Hard locks:** `br` only — never `bd`. Missing beads → CRITICAL phase failure.

## Strategy

`strategy: append` on `speckit.tasks` — does not replace core Spec Kit templates.
