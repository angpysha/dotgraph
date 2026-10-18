# Extension: `design-context`

Spec Kit extension that sits between **plan** and **tasks**: scan architecture, record
ADRs/RFCs, and emit task-split hints. A separate **critique** command is **readonly**
(propose only) and is wired as optional `after_plan` / `before_tasks` hooks.

## Install

```bash
specify extension add --dev speckit-tools/extensions/design-context
# or
agentic-tool speckit-packages install --id design-context
```

## Commands

| Command | Slash | Writes |
|---------|-------|--------|
| `speckit.design-context.scan` | `/speckit-design-context-scan` | Design docs only (`design-context.md`, ADRs, RFCs, plan links) |
| `speckit.design-context.critique` | `/speckit-design-context-critique` | **Nothing** |

Follow `core/skills/design-context/SKILL.md` (always-on after apply).

## Hooks

Both **optional** (`optional: true`). Declining MUST NOT fail the phase.

- **after_plan** → critique. If the plan is thin, critique **recommends** scan.
- **before_tasks** → critique. If insufficient, **do not** start `/speckit.tasks` or other
  mutating agents until the operator runs scan or explicitly declines.

Third-party critic extensions may be added as extra optional readonly hooks; they do not
replace this critique as the pipeline default.

## Scan I/O

**Reads**: `{FEATURE_DIR}/{spec,plan,research,data-model}.md`, contracts, constitution, codebase (code-search).

**Writes**: `{FEATURE_DIR}/design-context.md`, `{FEATURE_DIR}/rfcs/`, `docs/adr/` (when ADR criteria apply), links on `plan.md`.

**Forbidden**: application source, `tasks.md`, beads/`br`.

## Critique

Runs `Test-PlanSufficiency.ps1` (exit 0 always). Emits `STATUS` / `REASONS` / `RECOMMEND`.
If `insufficient`, recommend `/speckit.design-context.scan` (and grill when `RECOMMEND: scan+grill`).

## Strategy

This is an **extension** (new commands + hooks), not an append preset.
