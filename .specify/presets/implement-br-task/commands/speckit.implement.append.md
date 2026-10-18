## Mandatory: sync `br` on implement start/finish

When this preset is installed, `/speckit.implement` MUST update **beads rust (`br`)** for
the single task unit, then refresh `tasks.md`. Do not close only the markdown checkbox.
**Never** use `bd`.

### Hard gate

```powershell
pwsh -NoProfile -File core/skills/tasks-beads/scripts/Assert-BeadsReady.ps1
```

On failure: CRITICAL ❌ banner → **stop the phase**.

### Start / claim

1. Assert beads ready
2. Select **one** `br` issue (one developer = one issue)
3. Claim/start: `br update <id> --claim --json` (or equivalent in_progress)
4. Refresh projection:

```powershell
pwsh -NoProfile -File core/skills/tasks-beads/scripts/Render-TasksFromBr.ps1 `
  -FeatureLabel 'speckit:<feature>' `
  -OutFile 'specs/<feature>/tasks.md' `
  -FeatureTitle '<name>'
```

5. Implement only that issue’s scope

### Finish / close

1. Assert beads ready
2. Verify acceptance evidence
3. `br close <id> --reason "Completed: <concrete proof>" --json`
4. Re-render `tasks.md`
5. Remind: `br sync --flush-only` when git handoff of `.beads/` is required
6. Do not force-close blocked issues without surfacing the failure to the operator

### Partial sync

If `br` update and markdown refresh disagree on success:

```text
PARTIAL SYNC
- br: <updated|stale|failed>
- tasks.md: <updated|stale|failed>
```

Do **not** claim full synchronization.
