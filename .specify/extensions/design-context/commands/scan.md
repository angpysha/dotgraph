---
description: "Scan plan vs architecture; record ADRs/RFCs and task-split hints for /speckit.tasks"
---

# Design-context scan

You **MUST** consider `$ARGUMENTS` (optional focus, e.g. a module path). Follow
`core/skills/design-context/SKILL.md` (or `.agents/skills/design-context/SKILL.md` after apply).

This command **writes design documents only**. It MUST NOT modify application/source/test
code, `tasks.md`, or the beads/`br` graph.

## Preconditions

1. Resolve `FEATURE_DIR` from `.specify/feature.json` (not the git branch name).
2. If `plan.md` is missing: stop. Tell the operator to run `/speckit.plan` first.
3. Load: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/`, constitution,
   existing `design-context.md`, `docs/adr/`, `{FEATURE_DIR}/rfcs/`.

## Protocol

1. **Code-search first** (`skills/code-search/SKILL.md`) for every architecture claim in the plan.
2. Optionally spawn **architect** then **team-lead** as **readonly** Task subagents (max two
   unless the human asks for more). This command is the hub.
   - Instruct: no source edits; do not run tasks/implement; do not call other specialists;
     return findings only.
   - Architect: plan vs existing architecture; alternatives; which forks need ADRs.
   - Team-lead: parallel-safe seams and contended files for task split; do not write `tasks.md` or `br` issues.
   - If Task is unavailable: continue solo; note `degraded` under Subagent findings.
3. Classify remaining questions:
   - Answerable from code/docs → record in the pack; offer ADR only if all three
     domain-modeling criteria hold (`skills/domain-modeling/SKILL.md` + `ADR-FORMAT.md`);
     otherwise RFC (`templates/rfc.md`) or a named pack section. Do **not** grill.
   - Not answerable → **grill** (`grilling` + `grill-with-docs`), one question at a time,
     with a recommended answer. Write the decision immediately to ADR/RFC/pack.
   - **Recommend** grill when irreversible forks lack ADRs or task-split seams are ambiguous.
   - If the operator defers: list the item under Open blockers as `deferred-by-operator`.
     Do not treat that topic as decided for `/speckit.tasks`.
4. Write/update `{FEATURE_DIR}/design-context.md` from
   `core/skills/design-context/templates/design-context.md`:
   - Architecture map (cite file paths)
   - Decision index (links to ADRs/RFCs; reuse existing docs — do not duplicate numbers)
   - Task-split hints with **disjoint file ownership** and contended files
   - Subagent findings
   - Open blockers (`none` or explicit items)
   - Status `complete` only if blockers are empty or all `deferred-by-operator`
5. Add a short supplement link list on `plan.md` pointing at the pack and new ADRs/RFCs.
   Do **not** contradict Technical Context. If pack and plan disagree, fix the pack or ask
   to re-run `/speckit.plan`.
6. Report pack path, new/reused ADR/RFC paths, status, and whether grill ran or was declined.

## Done when

- Pack exists with required sections
- Open questions are decided in ADR/RFC/docs **or** marked `deferred-by-operator`
- No application source / `tasks.md` / `br` changes
