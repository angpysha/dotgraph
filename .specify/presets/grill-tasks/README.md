# Preset: `grill-tasks`

Append-only Spec Kit preset for **`speckit.tasks`**: after graph + render, offer
**optional** grilling; **recommend** it when parallel-ready batches or cross-story
dependencies introduce false-parallelism / missed-blocker risk.

## Install

```bash
specify preset add --dev speckit-tools/presets/grill-tasks
agentic-tool speckit-packages install --id grill-tasks
```

## Timing

1. `br` graph created (`br-task-graph`)
2. `tasks.md` rendered (`render-tasks`)
3. Optional grill prompt → if risk → warn + recommend
4. Accept → mutate `br` first → re-render; decline → note risks, continue

Uses existing **grilling** / **grill-with-docs** skills — this preset only mandates when/how.
