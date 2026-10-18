---
name: code-search
description: >-
  Codebase discovery priority for all agents: (1) semantic code-search MCP (codesearch /
  configured primary), (2) default tools (Grep/Glob/Read). Use before claiming code exists,
  before adapt stack detection, and when grilling/domain-modeling cross-checks the repo.
disable-model-invocation: false
---

# Code Search — discovery priority

**Always follow this order** when exploring a repo, answering "does X exist?", stack detection,
or cross-checking user claims against code.

| Priority | Source | When to use |
|----------|--------|-------------|
| **1** | **Semantic MCP** (codesearch / mcp-codebase-search) | MCP server available in the host |
| **2** | **Default tools** | Grep, Glob, Read, shell `find`/`rg` — when MCP unavailable |

State **DEGRADED MODE** in chat when priority 1 is unavailable before making
structural claims about the codebase.

---

## Priority 1 — semantic MCP (preferred)

Prefer **codesearch** (flupkede/codesearch) when configured; mcp-codebase-search remains a valid alternate if present.

### codesearch (recommended)

```bash
# see skills/codesearch-install
codesearch index .
```

Cursor MCP (example):

```json
{ "mcpServers": { "codesearch": { "command": "codesearch", "args": ["mcp"] } } }
```

### mcp-codebase-search (alternate)

```bash
npm install -g @teknologika/mcp-codebase-search
mcp-codebase-ingest --path . --name <project-name>
```

Set `pipeline.manifest.json` → `code_search.primary` / `codebase_name` as appropriate.

### Workflow

1. Confirm the index/server is available.
2. Refresh the index if stale after large edits.
3. Semantic search with descriptive queries; cite **file paths + line ranges**.

### Dedupe Ticket — hard rule

Before adding **any** new file, module, class, function, or helper, produce a
**Dedupe Ticket** (intent, queries, top matches, reuse|extend|new). If MCP is
unavailable, state **DEGRADED MODE** and stop before making structural claims.

---

## Priority 2 — default tools

When MCP is unavailable:

- **Glob** — find files by name pattern
- **Grep** — exact symbol/string matches
- **Read** — file contents after narrowing

---

## Adapt / stack-selector

During `.agents adapt` (after `PROJECT.md` intake):

1. **Semantic MCP** — languages, file layout, targeted searches
2. **Filesystem globs** — `*.csproj`, `pubspec.yaml`, `Package.swift`, etc.
3. **`PROJECT.md` Stack** — primary on greenfield

Record `adapt.code_search_source`: `codesearch` | `mcp-codebase-search` | `filesystem` | `project-brief`.

---

## Constraints

- Cite paths; do not dump large files into chat.
- Refresh MCP index after significant local edits when available.
- MCP runs locally — no code leaves the machine.
