---
name: agents-adapt
description: >-
  Adapt the universal agent pipeline to THIS project. On greenfield repos, ensure PROJECT.md
  exists (project-intake), then code-search (semantic MCP → default tools),
  stack-selector, human confirm, agentic-tool apply. Run after `agentic-tool install`.
disable-model-invocation: true
---

# .agents — Adapt Skill

Run **after** `agentic-tool install`. Install copies this adapt skill + **project-intake**
skill + manifest stub; **adapt** captures the project brief (if needed), explores the codebase,
preselects configuration, and extracts required assets from the tool catalog
(`.agents/pipeline.home`).

Entry: **`Run .agents adapt`** or **`Run .agents adapt --update`**

---

## Prerequisites

- Repo root as working directory
- `agentic-tool install` completed (`.agents/SKILL.md` + `project-intake` skill + manifest stub)
- Tool catalog at path in `.agents/pipeline.home`
- Registry at `{catalog_home}/core/packs/registry.json`
- **Recommended:** [mcp-codebase-search](https://github.com/teknologika/mcp-codebase-search/) MCP
  configured and repo ingested (see `skills/code-search/SKILL.md`)

---

## Step 0 — Project brief (`PROJECT.md`) — **before stack detection on greenfield**

Mechanical check:

```powershell
pwsh .agents/skills/project-intake/scripts/ensure-project-md.ps1
```

| Exit | Meaning | Action |
|------|---------|--------|
| `0` | `PROJECT.md` OK, code present | Continue to Step 1 |
| `3` | `PROJECT.md` OK, **empty/greenfield repo** | Continue — stack-selector uses brief as primary signal |
| `1` | Missing `PROJECT.md` | **Stop** → run **project-intake** (below) |
| `2` | Incomplete (no Vision/Stack content) | **Stop** → ask human, fix `PROJECT.md` |

### project-intake (when exit `1` or `2`)

Follow `.agents/skills/project-intake/SKILL.md`:

1. Ask structured questions: **name**, **vision**, **stack** (+ optional CI/CD, tracker).
2. Write **`PROJECT.md`** at repo root (template:
   `.agents/skills/project-intake/templates/PROJECT.md.template`).
3. Set `pipeline.manifest.json` → `project.name`, `project.brief: "PROJECT.md"`.
4. Re-run `ensure-project-md.ps1` until exit `0` or `3`.

**Do not run stack-selector until `PROJECT.md` passes** (when intake is required).

---

## Step 1 — Explore codebase (code-search priority)

Follow **`skills/code-search/SKILL.md`**. Order:

> **Codebase Dedupe Protocol:** adapt writes the protocol into the repo `AGENTS.md` and ships
> the always-on `rules/code-search.mdc`. From now on, **codebase-search is the only valid
> source** for "does X exist?" claims, and **no new file/module/function is created without a
> Dedupe Ticket** (`reuse | extend | new`). If MCP is unavailable, state **DEGRADED MODE** and
> stop before changes. Full rule: `rules/code-search.mdc`.


| Priority | Tool | Adapt action |
|----------|------|--------------|
| **1** | **mcp-codebase-search** MCP | `list_codebases` → `update_codebase_scan` if stale → `list_files` + `get_codebase_stats` + `search_codebases` for stack hints |
| **2** | **Default tools** | Grep/Glob/Read when MCP unavailable |
| **3** | **Default** | Filesystem globs only |

### MCP first-time setup (if not indexed)

```bash
npm install -g @teknologika/mcp-codebase-search
mcp-codebase-ingest --path . --name <project-name>
```

Set `pipeline.manifest.json`:

```json
"code_search": {
  "primary": "mcp-codebase-search",
  "codebase_name": "<project-name>",
  "primary": "codesearch"
}
```

### Default tools (priority 2)

When MCP is unavailable, use Grep/Glob/Read.


## Step 2 — Stack selector (preselect)

Invoke the **`stack-selector`** agent (coordinator routes). Inputs (in priority order):

1. **mcp-codebase-search** — languages, `list_files`, semantic hits
3. **`PROJECT.md`** — Vision/Stack keywords
4. **Filesystem** globs

Writes:

- `.agents/pipeline.recommendation.json` — includes `code_search_source`
- `.agents/install-report.md` — human-readable Detection table

Scoring: MCP/graph community (3) > filesystem glob (2) > `PROJECT.md` keyword (2) > report keyword (1).

Respect manifest overrides: `packs_extra`, `agents_extra`, `agents_disable`, `features`.

If `confidence` is **low** or packs conflict → **ask the human** before proceeding.

---

## Step 3 — Human confirm

Present the recommendation table. Human may:

- Approve as-is
- Edit `PROJECT.md` and re-run stack-selector
- Add packs/agents via `pipeline.manifest.json` (`packs_extra`, `agents_extra`)
- Enable features (e.g. `features: { "dotnet-minimal": ["native-aot"] }`)

Update `pipeline.recommendation.json` if edited.

---

## Step 4 — Apply (extract from tool catalog)

```bash
agentic-tool apply --target .
```

---

## Step 4.5 — Initialize Spec Kit (SDD backbone)

The pipeline runs on **GitHub Spec Kit**. After `apply`, initialize it in the repo so all
agents get the `/speckit.*` commands. Full playbook: `skills/spec-kit/SKILL.md`.

```bash
# One-time on the machine (needs uv / Python 3.11+):
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git

# In the repo (use the manifest host, default cursor):
specify init . --integration cursor      # add --script ps on Windows, --ignore-agent-tools if offline
```

This creates `.specify/` (scripts, `memory/constitution.md`, templates) and the host command
files. Then set the manifest and seed the constitution from `PROJECT.md`:

```json
"spec_kit": { "enabled": true, "integration": "cursor", "dir": ".specify", "specs_dir": "specs" }
```

In the agent, run **`/speckit.constitution`** seeded from `PROJECT.md` (Vision + principles).
If `specify` cannot be installed (offline / no uv), set `spec_kit.enabled: false` and the
pipeline runs in **SPEC-KIT DEGRADED** mode (hand-written SDLC docs, same gates).

---

## Step 5 — Sync to host + verify

```bash
agentic-tool sync --target . --host auto
agentic-tool verify --target .
```

---

## Output checklist

- [ ] `PROJECT.md` with Vision + Stack (Step 0)
- [ ] Code explored via **semantic MCP** and/or default tools (Step 1)
- [ ] `.agents/pipeline.recommendation.json` + `.agents/install-report.md`
- [ ] Human confirmed recommendation
- [ ] `agentic-tool apply` completed
- [ ] **Spec Kit initialized** (`.specify/` present, `spec_kit.enabled: true`, constitution seeded) — or DEGRADED noted
- [ ] `pipeline.manifest.json` `status: ready`, `code_search.codebase_name` set if MCP used
- [ ] host synced + verify PASS
- [ ] `catalog_version` in manifest matches `agentic-tool version`

## Re-adapt & catalog refresh & catalog refresh

### When the tool package was updated

After `agentic-tool` is upgraded (new skills, agents, rules, or packs in the catalog), **always
re-extract** into the repo so `.agents/` and the host projection stay current:

```bash
agentic-tool apply --target .
agentic-tool sync --target . --host auto
agentic-tool verify --target .
```

`apply` overwrites skills, agents, rules, pack overlays, the adapt skill, and scripts from
the catalog. `sync` pushes them to `.cursor/` (or other host). Check
`pipeline.manifest.json` → `catalog_version` matches `agentic-tool version`.

`agentic-tool verify` warns when `catalog_version` is behind the tool package.

### Re-adapt (stack or manifest changes)

```text
Run .agents adapt --update
```

Re-read `PROJECT.md`, refresh MCP/codesearch index if used,
refresh recommendation, **re-apply** + **sync**.

Always run **`apply` + `sync`** at the end of `--update` — not just stack re-detection.

Rule: `rules/catalog-refresh.mdc` (always-on).

## Constraints

- **PROJECT.md** before stack-selector when missing or incomplete.
- **Spec Kit** initialized after apply (`specify init . --integration <host>`); seed the
  constitution from `PROJECT.md`. See `skills/spec-kit/SKILL.md`.
- **human-review** before `apply` when confidence is low.
- **Catalog refresh:** after any `agentic-tool` upgrade, run `apply` + `sync` + `verify` so
  skills/agents/rules match the package (`rules/catalog-refresh.mdc`).
- **No secrets** in manifest, recommendation, or reports.
