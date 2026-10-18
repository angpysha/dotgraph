---
name: api-local-test
description: >-
  Locally test a backend API at runtime with mcp2cli — turn any OpenAPI, GraphQL, or MCP
  endpoint into a CLI (zero codegen, token-efficient). Use to smoke-test a running local
  server, exercise endpoints against acceptance criteria / API contracts, and verify
  responses during Phase 7 integration tests and Phase 8 testing.
disable-model-invocation: false
---

# api-local-test — local backend API testing with mcp2cli

[**mcp2cli**](https://github.com/knowsuchagency/mcp2cli) turns any **OpenAPI spec**, **GraphQL
endpoint**, or **MCP server** into a CLI **at runtime** — no client codegen. It is the fastest
way to exercise a **locally running backend** and assert responses, and it emits token-efficient
output (`--json` / `--toon`) for agent consumption.

> Use this to **test the API you just built or changed** against its contract and acceptance
> criteria — not as a production client.

---

## Install (once per machine)

Requires **uv** (Python). No project dependency added.

```bash
uvx mcp2cli --help              # run without installing
uv tool install mcp2cli         # or install globally → `mcp2cli`
```

## Core workflow (local backend)

1. **Start the local server** using the project's run command (stack-specific): e.g.
   `dotnet run`, `npm run dev`, `uvicorn app:app --port 8000`, `flutter`/emulator backend, etc.
   Note the base URL (e.g. `http://localhost:8000`) and the spec/endpoint path.
2. **Point mcp2cli at the local API** and list operations:

```bash
# OpenAPI (remote spec served by the app)
mcp2cli --spec http://localhost:8000/openapi.json --list

# OpenAPI (local spec file + base URL)
mcp2cli --spec ./openapi.json --base-url http://localhost:8000 --list

# GraphQL
mcp2cli --graphql http://localhost:8000/graphql --list

# MCP server (HTTP/SSE or stdio)
mcp2cli --mcp http://localhost:8000/sse --list
mcp2cli --mcp-stdio "node server.js" --list
```

3. **Call endpoints** and assert. Map each call to an **acceptance criterion** (`AC-N`) and, when
   a contract exists, to the locked `operationId` / GraphQL field / RPC.

```bash
# GET with params
mcp2cli --spec http://localhost:8000/openapi.json list-pets --status available

# POST body from stdin
echo '{"name":"Fido","tag":"dog"}' | mcp2cli --spec http://localhost:8000/openapi.json create-pet --stdin

# GraphQL query / mutation
mcp2cli --graphql http://localhost:8000/graphql users --limit 10
mcp2cli --graphql http://localhost:8000/graphql create-user --name "Alice" --email "alice@example.com"
```

4. **Refresh the spec** after you change the API surface (specs are cached 1h):

```bash
mcp2cli --spec http://localhost:8000/openapi.json --refresh --list
```

## Machine-readable output (for agents & assertions)

```bash
# Force valid JSON for every command (list + calls). MCP calls emit the full
# CallToolResult envelope incl. structuredContent + isError.
mcp2cli --spec http://localhost:8000/openapi.json --json list-pets

# TOON — token-efficient for large uniform arrays (40-60% fewer tokens than JSON)
mcp2cli --spec http://localhost:8000/openapi.json --toon list-records

# Truncate large arrays; pipe to jq for assertions
mcp2cli --spec http://localhost:8000/openapi.json --json list-pets --head 5 | jq '.[].name'
```

Prefer `--json` for scripted checks and `--toon`/`--head` when summarizing results in chat.

## Bake a local profile (skip repeating flags)

```bash
# Save localhost connection + auth once
mcp2cli bake create localapi --spec ./openapi.json --base-url http://localhost:8000

# Use with @ prefix
mcp2cli @localapi --list
mcp2cli @localapi list-pets --limit 10
mcp2cli bake show localapi     # secrets masked
```

Baked configs live in `~/.config/mcp2cli/baked.json` (override `MCP2CLI_CONFIG_DIR`).

## Auth & secrets (never pass secrets as bare args)

Use `env:` / `file:` prefixes so secrets don't appear in process listings, and OAuth for
protected APIs (tokens cached in `~/.cache/mcp2cli/oauth/`).

```bash
mcp2cli --spec http://localhost:8000/openapi.json \
  --auth-header "Authorization:env:LOCAL_API_TOKEN" list-pets

mcp2cli --spec http://localhost:8000/openapi.json --oauth --list   # PKCE browser flow
mcp2cli --spec http://localhost:8000/openapi.json \
  --oauth-client-id "env:OAUTH_CLIENT_ID" \
  --oauth-client-secret "env:OAUTH_CLIENT_SECRET" --list           # client credentials
```

**Never** hardcode tokens in commands, checkpoints, or reports.

## Pipeline integration

| Phase | Use |
|-------|-----|
| **7.6 Integration tests** (developer) | Smoke-test the changed endpoints against the local server before handoff; log calls run |
| **8 Testing** (tester) | Exercise every AC against the running API; capture `--json` responses in the TEST report; map calls → `AC-N` |
| **Design/Planning** | Cross-check the running API against the locked contract (`openapi-contract`, `graphql-contract`, `grpc-contract`) — the spec URL should match `artifacts/sdlc/api/` |

Complements the **contract** skills: contracts define the *spec*, `api-local-test` verifies the
*running implementation* matches it. Automated test suites (from the pack's `test.command`)
remain the source of truth for the test gate; mcp2cli is for **fast, exploratory local
verification** and agent-driven endpoint checks.

## Degraded mode

If `mcp2cli` / `uv` is unavailable, state **API-TEST DEGRADED** and fall back to `curl` /
`httpie` against the local base URL, keeping the same AC → call mapping.

## Constraints

- Test against a **local / non-production** base URL unless the human explicitly approves otherwise.
- No secrets in CLI args, chat, or reports — use `env:` / `file:` / `--oauth`.
- Refresh the spec (`--refresh`) after changing the API surface.
- Cite endpoint + status/shape in chat; save bulky responses to session artifacts, don't paste.
