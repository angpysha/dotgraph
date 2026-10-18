# Preset: `render-tasks`

Append-only Spec Kit preset for **`speckit.tasks`**: render `tasks.md` (checklist,
`[P]` batches, Mermaid) from the canonical **`br`** graph.

## Install

```bash
specify preset add --dev speckit-tools/presets/render-tasks
agentic-tool speckit-packages install --id render-tasks
```

## Render I/O

| Input | Meaning |
|-------|---------|
| `-FeatureLabel` | Beads label scope, e.g. `speckit:011-speckit-tasks-beads` |
| `-OutFile` | Usually `specs/<feature>/tasks.md` |
| `-FeatureTitle` | Document title |

Script: `core/skills/tasks-beads/scripts/Render-TasksFromBr.ps1`  
Contract: `specs/011-speckit-tasks-beads/contracts/tasks-md-projection.md`

Empty label scope fails clearly — create the `br` graph first (`br-task-graph`).
