---
name: design-context
description: >-
  Scan a Spec Kit plan against existing architecture; record ADRs/RFCs and
  task-split hints. Readonly critique after plan / before tasks recommends scan
  when coverage is thin. Never edits application source. Use after /speckit.plan
  or when /speckit.tasks would otherwise guess architecture.
disable-model-invocation: true
---

# Design Context

Maximum **readonly-propose then document** pass between `/speckit.plan` and
`/speckit.tasks`. Makes architecture and decisions obvious for the next developer
and the tasks agent. Spec Kit artifacts stay canonical (`plan.md` wins).

**Contracts**: `specs/013-speckit-design-context/contracts/`

| Piece | Path |
|-------|------|
| Extension | `speckit-tools/extensions/design-context/` |
| Sufficiency CLI | `scripts/Test-PlanSufficiency.ps1` |
| Pack template | `templates/design-context.md` |
| RFC template | `templates/rfc.md` |
| ADRs | `core/skills/domain-modeling/ADR-FORMAT.md` |

## Commands

| Slash (host) | Spec Kit | Writes |
|--------------|----------|--------|
| `/speckit-design-context-scan` | `speckit.design-context.scan` | Design docs only |
| `/speckit-design-context-critique` | `speckit.design-context.critique` | **Nothing** |

Hooks (optional, never fail the phase if declined):

- `after_plan` → **critique**
- `before_tasks` → **critique**

If critique is **insufficient**, **do not** start tasks/implement/other mutating agents.
Recommend **scan** (and grill when forks/seams are unclear). A third-party critic
extension, if installed, is an extra optional readonly pass — it does not replace this
command.

## Critique (readonly)

1. Run:

```powershell
pwsh core/skills/design-context/scripts/Test-PlanSufficiency.ps1
# After apply: .agents/skills/design-context/scripts/Test-PlanSufficiency.ps1
```

2. Parse `STATUS` / `REASONS` / `RECOMMEND`. Helper **always exits 0**.
3. Add human-readable gap notes in chat only.
4. **Forbidden**: any repo write; invoking `/speckit.tasks`, `/speckit.implement`, `br`, or scan unless the human asked to scan in that message.

Emit:

```text
STATUS: sufficient|insufficient|blocked
REASONS:
- …
RECOMMEND: none|scan|scan+grill
```

`blocked` (no plan) → tell the operator to run `/speckit.plan` first.

## Scan (design docs only)

### Forbidden writes

Application/source/test code, `tasks.md`, beads/`br` graph.

### Allowed writes

- `{FEATURE_DIR}/design-context.md` (overwrite in place)
- `{FEATURE_DIR}/rfcs/NNNN-slug.md`
- `docs/adr/NNNN-slug.md` when the three ADR criteria apply (domain-modeling)
- Link list on `plan.md` (supplement; do not contradict Technical Context)

### Protocol

1. Resolve `FEATURE_DIR` from `.specify/feature.json` (not the git branch name). Abort if `plan.md` is missing.
2. Load spec, plan, research, data-model, contracts, constitution, existing pack/ADRs/RFCs.
3. **Code-search first** (`skills/code-search/SKILL.md`) for every architecture claim.
4. Optionally spawn **architect** then **team-lead** as **readonly** Task subagents (max two unless the human asks). This command is the hub. Instruct: no source edits, no tasks/implement, no calling other specialists, return findings only. If Task is unavailable, continue solo and note `degraded`.
5. Close questions in documents:
   - Answerable from code/docs → write pack (+ ADR/RFC if needed); do **not** grill.
   - Not answerable → **grill** (`grilling` + `grill-with-docs`), one question at a time, recommended answer.
   - **Recommend** grill when irreversible forks lack ADRs or task-split seams are ambiguous.
   - Operator deferral → leave item in Open blockers as `deferred-by-operator`. Do not claim complete for that topic.
6. ADR only when all three domain-modeling criteria hold; otherwise RFC or a named section in the pack. Reuse existing docs; do not duplicate numbers for the same fork.
7. Fill the pack from `templates/design-context.md` (architecture map, decision index, task-split hints with **disjoint file ownership**, subagent findings, open blockers).
8. Pack `complete` only if open blockers are empty or every leftover is `deferred-by-operator`.
9. Tell `/speckit.tasks` it may split using the hints; it MUST NOT invent missing architecture decisions.

## Hub-and-spoke

Specialists talk only to this command. Constitution IV still applies. Coordinator may
invoke this skill; this skill must not become a second coordinator for the whole SDLC.

## Lanes

Always-on after `agentic-tool apply` (spike through full). Optional hooks still skippable
on micro/spike; recommend scan when a plan exists but coverage is thin.
