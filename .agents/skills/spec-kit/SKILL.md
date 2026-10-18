---
name: spec-kit
description: >-
  Spec-Driven Development backbone via GitHub Spec Kit (specify CLI + /speckit.* commands).
  Every SDLC phase drives the matching /speckit command; spec.md/plan.md/tasks.md are the
  machine-checkable source of truth. Use during install/adapt (constitution) and every phase.
disable-model-invocation: true
---

# spec-kit

**GitHub Spec Kit** (<https://github.github.com/spec-kit/>) is the **Spec-Driven Development
(SDD) backbone** for this pipeline. Instead of ad-hoc prompts, every phase produces or
consumes a Spec Kit Markdown artifact (`spec.md` → `plan.md` → `tasks.md`) that the next
phase reads. Our agents, gates, checkpoints, packs, and session artifacts wrap around it.

> **Golden rule:** if a phase has a matching `/speckit.*` command, the agent **runs that
> command** and treats its artifact as canonical. Our SDLC docs (REQ/SDD/TDD/TEST, ADRs,
> API contracts) *supplement and reference* the Spec Kit artifacts — they never contradict them.

---

## Install (once per machine)

Requires **Python 3.11+** and **uv** (`brew install uv` / `pipx`).

```bash
# Persistent install (recommended)
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git

# Verify
specify version
```

One-time (no install):

```bash
uvx --from git+https://github.com/github/spec-kit.git specify init . --integration cursor
```

## Initialize in a repo (during install / adapt)

Run **after** `agentic-tool install --host cursor`, from the repo root:

```bash
# Cursor host (this pipeline's default). --here / . = current repo.
specify init . --integration cursor
# Force script variant if needed: --script ps (Windows) | --script sh (macOS/Linux)
# Offline / no agent-tool check: add --ignore-agent-tools
```

Non-interactive default integration is `copilot`; **always pass `--integration cursor`** here
(or the host from `pipeline.manifest.json` → `host`). If a host has no dedicated integration,
use `--integration generic`.

`specify init` creates:

- `.specify/scripts/{bash,powershell}/` — SDD helper scripts
- `.specify/memory/constitution.md` — project principles (our `PROJECT.md` feeds this)
- `.specify/templates/` — spec/plan/tasks templates
- Host command files so `/speckit.*` appear in the agent (Cursor: `.cursor/commands/`)

After init, set `pipeline.manifest.json`:

```json
"spec_kit": {
  "enabled": true,
  "integration": "cursor",
  "dir": ".specify",
  "specs_dir": "specs",
  "constitution": ".specify/memory/constitution.md"
}
```

## Slash commands (run inside the agent)

| Command | Purpose |
|---------|---------|
| `/speckit.constitution` | Create/update project principles (`.specify/memory/constitution.md`) |
| `/speckit.specify` | Create the feature spec (`specs/NNN-slug/spec.md`) |
| `/speckit.clarify` | Resolve ambiguities in the spec (interactive) |
| `/speckit.plan` | Technical implementation plan (`specs/NNN-slug/plan.md`) |
| `/speckit.design-context.critique` | Readonly sufficiency check (optional after plan / before tasks) |
| `/speckit.design-context.scan` | Architecture scan: ADRs/RFCs + task-split pack for tasks |
| `/speckit.checklist` | Quality checklists validating the spec/plan |
| `/speckit.tasks` | Break plan into actionable tasks (`specs/NNN-slug/tasks.md`) |
| `/speckit.analyze` | Cross-artifact consistency check (spec ↔ plan ↔ tasks) |
| `/speckit.implement` | Execute the tasks |
| `/speckit.converge` | Assess codebase vs artifacts; append remaining tasks |
| `/speckit.taskstoissues` | Convert tasks to tracker issues |

Feature **directories** live under `specs/NNN-slug/` (see `.specify/feature.json`). When the
**branch-format** preset is installed, create/switch the **git branch** with the always-on
`branch-format` skill (`{type}/{ISO-week}-{slug}`) — mandatory for specify-time branches;
do not invent `NNN-slug` git branch names. Spec dirs and git branches are independent.

When the **tasks-beads** presets are installed (`br-task-graph`, `render-tasks`,
`grill-tasks`, `implement-br-task`), `/speckit.tasks` is **`br`-first**: create/reconcile
the beads graph, optionally grill (recommend on parallel/cross-story risk), then render
`tasks.md` as a projection. `/speckit.implement` claims/closes in `br` and refreshes
`tasks.md`. Missing beads → CRITICAL phase failure. See `core/skills/tasks-beads/SKILL.md`.

When the **design-context** extension is installed, `/speckit.plan` offers an **optional**
readonly critique hook. If architecture/ADRs are thin, **recommend**
`/speckit.design-context.scan` (ADRs/RFCs/task-split hints) **before** `/speckit.tasks` or
other mutating agents. Critique writes nothing. See `core/skills/design-context/SKILL.md`.

---

## Phase ↔ Spec Kit map (how the pipeline drives SDD)

| SDLC phase | Agent | Spec Kit command | Canonical artifact |
|-----------|-------|------------------|--------------------|
| adapt / intake | project-intake, coordinator | `/speckit.constitution` | `.specify/memory/constitution.md` |
| 1 Intake | coordinator | `branch-format` skill + seed `/speckit.specify` | `specs/NNN-slug/spec.md` |
| 2 Business grilling | ba-analyst | `/speckit.clarify` | updates `spec.md` |
| 4 Requirements | ba-analyst | `/speckit.specify` (finalize) | `spec.md` (+ our REQ supplements) |
| 5 Design | architect | `/speckit.plan` | `plan.md` (+ SDD/TDD/ADR/API contracts) |
| 5 → 6 design-context | architect / design-context | `/speckit.design-context.critique` then scan if recommended | `design-context.md` + ADRs/RFCs (supplements) |
| 5 → 6 quality | architect / team-lead | `/speckit.checklist` | checklists |
| 6 Planning | team-lead | `/speckit.tasks` then `/speckit.analyze` | `tasks.md` (+ IMPLEMENTATION-PLAN) |
| 6 tracker | team-lead / coordinator | `/speckit.taskstoissues` | tracker issues |
| 7 Implementation | developer | `/speckit.implement` (one task) | code |
| 8 Testing | tester | verify AC; re-run `/speckit.analyze` | TEST report |
| 8→9 Convergence | coordinator / tester | `/speckit.converge` | appended tasks until converged |
| 9 Review / 10 Closeout | tech-writer / coordinator | (docs sync; PR) | published docs |

**Gate coupling:** our gate scripts (`validate-requirements/design/tasks`, dev/test gates)
still run and are authoritative. `/speckit.analyze` and `/speckit.checklist` run **before**
the corresponding gate as a machine pre-check; a gate never passes on a red `analyze`.

**Convergence loop (Phase 8→9):** after implementation, run `/speckit.converge`. If it
appends tasks, loop to `/speckit.implement` (Phase 7) and converge again until it reports the
feature has converged. Only then advance to Phase 9.

---

## Artifact locations — Spec Kit vs session

| Layer | Path | Owner |
|-------|------|-------|
| Constitution | `.specify/memory/constitution.md` | long-lived; from `PROJECT.md` |
| Spec / Plan / Tasks | `specs/NNN-slug/{spec,plan,tasks}.md` | Spec Kit (canonical) |
| Supplements (working) | `_code_agent/{session}/artifacts/sdlc/…` | our agents (grilling records, ADRs, contracts, TEST) |
| Published finals | `docs/sdlc/…` | after Phase 9 (`publish-sdlc.ps1`) |

Session SDLC docs **link to** the `specs/NNN-slug/` files rather than duplicating them.
Cite paths in chat — never paste full specs.

---

## Lanes

- **Full / Fast:** run the full SDD chain (`constitution → specify → clarify → plan →
  checklist → tasks → analyze → implement → converge`).
- **Short:** `specify` (light) → `plan` → `tasks` → `implement` → `converge`; skip clarify if
  unambiguous.
- **Micro:** may skip `plan`; still create a minimal `spec.md` and use `/speckit.implement`.
- **Spike:** `/speckit.specify` for the question only; no `implement`.

## Degraded mode

If `specify` / `/speckit.*` is unavailable (not installed, offline, host without support):
state **SPEC-KIT DEGRADED** and fall back to writing the equivalent SDLC docs
(`REQ/SDD/TDD/tasks`) by hand under the session folder, keeping the same phase gates. Re-sync
to Spec Kit artifacts once available.

## Constraints

- Spec Kit artifacts are **canonical**; our docs supplement, never contradict.
- Always `--integration cursor` (or manifest `host`) on init; `generic` only as a fallback.
- Keep `spec.md/plan.md/tasks.md` under version control; no secrets in them.
- Re-run `/speckit.analyze` after edits before the matching gate.
- One developer = one task still holds during `/speckit.implement`.
