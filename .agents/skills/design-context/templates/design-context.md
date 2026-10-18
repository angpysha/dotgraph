# Design-context pack

**Feature**: `{FEATURE_DIR}`  
**Status**: `blocked` | `complete`  
**Canonical plan**: [plan.md](./plan.md) · **Spec**: [spec.md](./spec.md)

This pack **supplements** Spec Kit artifacts. If it disagrees with `plan.md`, fix the pack
or update the plan via `/speckit.plan` — never fork architecture here.

## Architecture map

How the plan maps onto existing modules and files (cite paths):

- …

## Decision index

| Doc | Intent | Link |
|-----|--------|------|
| ADR-NNNN | … | [docs/adr/NNNN-slug.md](../../docs/adr/NNNN-slug.md) |
| RFC-NNNN | … | [rfcs/NNNN-slug.md](./rfcs/NNNN-slug.md) |

## Task-split hints

Groups with **disjoint file ownership** (safe to mark `[P]` in `/speckit.tasks`):

| Group | Files | Notes |
|-------|-------|-------|
| A | `path/a`, `path/b` | |
| B | `path/c` | |

**Contended files** (must stay sequential — do not parallelize):

- `path/shared`

## Subagent findings

- **architect**: `not-run` | summary
- **team-lead**: `not-run` | summary

## Open blockers

- none
