<!-- agentic-pipeline:begin -->
# Agent index

Universal agent-orchestrated SDLC pipeline for this repository.

## Bootstrap

If `pipeline.manifest.json` shows `"status": "needs_adapt"`:

```text
Run .agents adapt
```

Adapt skill: [.agents/SKILL.md](.agents/SKILL.md)

**Greenfield / empty repo:** adapt runs **project-intake** first — ensures `PROJECT.md`
(Vision + Stack) exists before recommending packs and agents.

## Spec-Driven Development (Spec Kit)

This pipeline runs on **[GitHub Spec Kit](https://github.github.com/spec-kit/)**. Every phase
drives the matching `/speckit.*` command; `spec.md`/`plan.md`/`tasks.md` are canonical.
Install once and initialize per repo:

```text
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
specify init . --integration cursor        # then /speckit.constitution from PROJECT.md
```

All agents follow `rules/spec-kit.mdc`. Playbook: `skills/spec-kit/SKILL.md`. If Spec Kit is
unavailable, the pipeline runs in **SPEC-KIT DEGRADED** mode (hand-written SDLC docs, same gates).

## After adapt (`status: ready`)

```text
Run SDLC for: {your feature}
```

Coordinator playbook: `.cursor/skills/sdlc-orchestrator/SKILL.md` (or `.agents/skills/sdlc-orchestrator/SKILL.md`)

## Specialist agents

| Agent | Role |
|-------|------|
| coordinator | Hub — routing, gates, checkpoints, closeout |
| ba-analyst | Business grilling + requirements |
| architect | SDD, TDD, ADR |
| team-lead | Planning + TL code review |
| developer | Implementation (one task at a time) |
| tester | Adversarial testing + report |
| security-reviewer | Auth/token/storage review (conditional) |
| devops | Infra planning + IaC (conditional) |
| tech-writer | Docs sync (Phase 9) |
| stack-selector | Stack detection during adapt only |

Contract: [pipeline.manifest.json](pipeline.manifest.json)

## Catalog refresh (keep skills/agents/rules current)

After any `agentic-tool` upgrade, refresh from the package catalog:

```bash
agentic-tool apply --target .
agentic-tool sync --target . --host auto
agentic-tool verify --target .
```

`verify` warns when `catalog_version` in the manifest is behind the tool. Rule:
`rules/catalog-refresh.mdc`. Coordinator stops SDLC if the catalog is stale.

## Codebase Dedupe Protocol

### Goal

Prevent duplicate implementations and "wrong file" edits by making **Serena MCP** the
*only valid source* for claims about what already exists in this repo during this session.

### Tools you MUST use for codebase discovery

Activate project `package_helper` (`.serena/project.yml`) then prefer:

- `activate_project`
- `find_symbol` / `find_referencing_symbols`
- `search_for_pattern`
- `get_symbols_overview`
- `find_file` / `list_dir`
- `read_file`

After structural edits, refresh symbols if stale (`restart_language_server`).

**Fallback (DEGRADED MODE only):** Grep, Glob, Read — when Serena MCP is unavailable.

### Hard rule: No creation without a Dedupe Ticket

Before adding a new file, module, class, function, or helper, produce a **Dedupe Ticket**:

- **Intent signature** — one sentence describing what you are about to add
- **Queries** — 2–4 searches you will run
- **Top matches** — up to 5 file paths returned by the tool
- **Decision** — `reuse | extend | new`
- **Rationale** — why

### Graceful degradation

If the MCP server is unavailable: state **DEGRADED MODE** and stop before making changes.
Full priority chain (semantic MCP → default tools): `rules/code-search.mdc` +
`skills/code-search/SKILL.md`.

## Beads issue tracker (`br` only)

Local planning and issue tracking use **beads_rust**. The CLI is **`br`** — **never `bd`**
(legacy CLI). Triage via `bv --robot-triage`. Full rule: `rules/beads.mdc`.

**Client install:** `agentic-tool install` copies `beads.mdc` into `.agents/rules/`;
`apply` refreshes all core rules + every enabled agent (each agent persona includes the
same hard lock); `sync` projects agents/rules to the host (`.cursor/`, `.claude/`, …).
Every specialist in this repo MUST follow **`br` only**.
<!-- agentic-pipeline:end -->
