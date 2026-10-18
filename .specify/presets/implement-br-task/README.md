# Preset: `implement-br-task`

Append-only Spec Kit preset for **`speckit.implement`**: claim/start and finish/close
in **`br`**, then refresh `tasks.md`. Prevents “forgot the tracker” implement runs.

## Install

```bash
specify preset add --dev speckit-tools/presets/implement-br-task
agentic-tool speckit-packages install --id implement-br-task
```

## Operator steps

**Start**

1. `Assert-BeadsReady.ps1`
2. `br update <id> --claim --json`
3. `Render-TasksFromBr.ps1 …`
4. Code the single issue

**Finish**

1. `Assert-BeadsReady.ps1`
2. `br close <id> --reason "Completed: …" --json`
3. Re-render `tasks.md`
4. `br sync --flush-only` when `.beads/` git handoff is required

Contract: `specs/011-speckit-tasks-beads/contracts/implement-lifecycle.md`
