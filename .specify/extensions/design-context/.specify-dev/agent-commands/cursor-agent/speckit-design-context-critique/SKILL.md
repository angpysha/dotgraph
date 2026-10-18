---
name: speckit-design-context-critique
description: Readonly sufficiency check after plan / before tasks; recommend scan if thin
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: design-context:commands/critique.md
---

# Design-context critique (readonly)

You **MUST** consider `$ARGUMENTS`. Follow `core/skills/design-context/SKILL.md`
(or `.agents/skills/design-context/SKILL.md` after apply).

This command is a **critic**. It **MUST NOT** write any files. It **MUST NOT** invoke
`/speckit.tasks`, `/speckit.implement`, `/speckit.design-context.scan`, `br`, or other
mutating agents. It only **proposes**.

If a third-party critic extension is installed, you MAY mention it as an extra optional
readonly pass. It does **not** replace this command.

## Steps

1. Resolve `FEATURE_DIR` from `.specify/feature.json`.
2. Run the helper (do not treat non-zero as a phase failure — the helper is specified to
   exit 0; if it cannot run, report that in chat and still write no files):

```powershell
pwsh core/skills/design-context/scripts/Test-PlanSufficiency.ps1
# After apply:
# pwsh .agents/skills/design-context/scripts/Test-PlanSufficiency.ps1
```

3. Optionally skim `plan.md` and `design-context.md` to phrase gaps for a developer.
   Still **no writes**.
4. Emit:

```text
STATUS: sufficient|insufficient|blocked
REASONS:
- …
RECOMMEND: none|scan|scan+grill
```

5. If `blocked`: tell the operator to run `/speckit.plan` first.
6. If `insufficient`: **recommend** `/speckit.design-context.scan` before any other agent.
   If `RECOMMEND: scan+grill`, say grilling is recommended during that scan.
   Explicitly: do not start `/speckit.tasks` as if architecture were settled.
7. If the operator declines: note the decline in chat; **do not fail** the Spec Kit phase.

## Done when

- STATUS block printed
- Workspace diff from this command is empty
- Next step is a recommendation, not a silent handoff to another agent