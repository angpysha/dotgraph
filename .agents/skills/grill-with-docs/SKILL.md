---
name: grill-with-docs
description: >-
  Relentless interview to sharpen a plan or design. All resolved information is written via
  Spec Kit (/speckit.* → spec.md/plan.md). Glossary (CONTEXT.md) and ADRs supplement only.
  Composes grilling + domain-modeling + spec-kit.
disable-model-invocation: true
---

Run a **`grilling`** session using **`domain-modeling`** and **`spec-kit`**.

Before asking the human, answer code-backed questions via **`code-search`** (MCP
[mcp-codebase-search](https://github.com/teknologika/mcp-codebase-search/) first, then default tools if needed,
then default tools).

Read `skills/grilling/SKILL.md`, `skills/domain-modeling/SKILL.md`, and
`skills/spec-kit/SKILL.md` before starting.

---

## Golden rule — write everything via Spec Kit

During **`grill-with-docs`**, every resolved decision, edge case, functional option, and
design alternative must be **written into Spec Kit artifacts** using the matching `/speckit.*`
command. Do **not** leave outcomes only in chat or ad-hoc markdown.

| What you resolve | Where it goes | How |
|------------------|---------------|-----|
| Business requirements, edge cases, functional options | **`specs/NNN-slug/spec.md`** | `/speckit.clarify` (Phase 2) or `/speckit.specify` |
| Technical design, stack, architecture, alternatives | **`specs/NNN-slug/plan.md`** | `/speckit.plan` (Phase 5) |
| Spike question / exploration scope | **`specs/NNN-slug/spec.md`** | `/speckit.specify` (spike only) |
| Ubiquitous language (terms only) | **`CONTEXT.md`** | domain-modeling — glossary, not a spec |
| Hard-to-reverse technical fork | **ADR** + link from `plan.md` | domain-modeling — supplements `plan.md` |

**`spec.md` and `plan.md` are canonical.** `CONTEXT.md`, ADRs, and session REQ/SDD supplements
**link to** Spec Kit files — they must never contradict them.

Ensure the feature branch `NNN-slug` exists and `pipeline.manifest.json` has
`spec_kit.enabled: true`. If Spec Kit is unavailable, state **SPEC-KIT DEGRADED** and write
equivalent content to the session folder (`_code_agent/{session}/artifacts/sdlc/`), keeping
the same structure.

---

## Session loop (one question at a time)

For **each** grilling question:

1. **Explore** — `code-search` if answerable from the codebase.
2. **Ask** — one question; offer your recommended answer (`grilling` discipline).
3. **Resolve** — human confirms or refines.
4. **Write to Spec Kit immediately** — run the phase `/speckit.*` command with the resolved
   answer (do not batch until end of session).
5. **Supplement** — update `CONTEXT.md` for new terms; offer ADR only when criteria met
   (`domain-modeling`).
6. **Confirm in chat** — cite the Spec Kit path only (e.g. `specs/003-rate-limit/spec.md`),
   not the full text.

```text
Question → resolve → /speckit.clarify|plan|specify → CONTEXT.md (if term) → next question
```

---

## Phase rules

| Phase | Glossary (`CONTEXT.md`) | ADRs | Spec Kit (required writes) |
|-------|-------------------------|------|----------------------------|
| **2 — BA business grilling** | Yes — terms only | No | **`/speckit.clarify`** after each resolved fork → `spec.md`; finalize with **`/speckit.specify`** |
| **5 — Architect design** | Yes — terms only | Yes — link from `plan.md` | **`/speckit.plan`** with stack + alternatives; **`/speckit.checklist`** when plan is stable |
| **Spike** | Yes — terms only | Sparingly | **`/speckit.specify`** for the exploration question only (no `plan`/`implement`) |

### Phase 2 — what goes into `spec.md`

Via `/speckit.clarify` and `/speckit.specify`, capture in **`spec.md`**:

- Problem statement and scope (in/out)
- Functional requirements and acceptance criteria
- **Edge cases** (from grilling)
- **Functional options** — chosen option + rejected alternatives per behavior
- Open questions (resolved / blocking / deferred)

Stay in **business language** — no implementation stack in Phase 2 (`spec.md` is *what* and
*why*, not *how*).

### Phase 5 — what goes into `plan.md`

Via `/speckit.plan`, capture in **`plan.md`**:

- Stack and architecture choices
- **Design alternatives** — chosen approach + rejected options
- Data model, interfaces, migration impact (high level)
- Testing strategy pointers

ADRs and session SDD/TDD files **supplement** `plan.md` and must **reference** it.

---

## Prerequisites

- Feature branch `NNN-slug` checked out (Spec Kit keys artifacts to the branch).
- `.specify/` initialized (`specify init . --integration cursor`).
- Constitution present (`.specify/memory/constitution.md` from `/speckit.constitution`).

---

## Constraints

- **One question at a time** — never dump a questionnaire (`grilling`).
- **Write after every resolution** — no "we'll document at the end."
- **Paths in chat** — cite `specs/NNN-slug/spec.md` or `plan.md`; never paste full specs.
- **No secrets** in spec/plan/constitution.
- **CONTEXT.md** is glossary only — not a substitute for `spec.md`.
