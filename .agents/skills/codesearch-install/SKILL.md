---
name: codesearch-install
description: >-
  Install flupkede/codesearch — a local Rust MCP server for multi-repo semantic code search
  (vector + BM25 hybrid, symbol nav, offline). Downloads the right latest GitHub release binary
  by platform (defaults to the C#-enabled with-csharp variant) and optionally wires the MCP server
  into the host. Use during adapt/setup to give the code-search skill a Priority-1 semantic backend.
disable-model-invocation: false
---

# codesearch-install

Installs [**codesearch**](https://github.com/flupkede/codesearch) — a fully-local, offline Rust
MCP server for semantic code search across repositories. It satisfies **Priority 1** of the
[`code-search`](../code-search/SKILL.md) discovery order (semantic search before Grep).

The `-with-csharp` release variant bundles a `scip-csharp` helper for C# semantic analysis and is
the **default**, since this pipeline targets .NET/C# projects. Pass `-NoCsharp` for the plain build.

## Supported platforms

Only these release assets exist — the installer fails clearly on anything else:

| OS | Arch | Archive |
|----|------|---------|
| Windows | x86_64 | `.zip` |
| Linux | x86_64 | `.tar.gz` |
| macOS | arm64 (Apple Silicon) | `.tar.gz` |

There is **no** Windows-ARM, Linux-ARM, or Intel-macOS build; build from source
(`cargo build --release`) on those.

## When to use

| When | Who |
|------|-----|
| During **`agentic-tool apply`** / adapt setup, to stand up local semantic search | Coordinator / devops |
| `mcp-codebase-search` is unavailable and you want an offline backend | Any agent hitting DEGRADED mode |
| Onboarding a new machine to the pipeline | Human |

## Usage

```powershell
$CS = '.cursor/skills/codesearch-install/scripts/install-codesearch.ps1'   # or .claude/... / .agents/...

# Dry run — show which asset would be downloaded for this machine, then exit
pwsh $CS -DryRun

# Install latest, with-csharp (default), to ~/.local/bin
pwsh $CS

# Plain variant, pinned version, custom dir, reinstall
pwsh $CS -NoCsharp -Version v1.1.29 -InstallDir ~/tools/bin -Force

# Install and register the MCP server in the detected host config
pwsh $CS -ConfigureMcp                 # auto-detects cursor/claude/windsurf
pwsh $CS -ConfigureMcp -McpHost claude # force a specific host
```

### Parameters

| Param | Default | Purpose |
|-------|---------|---------|
| `-Version` | `latest` | Release tag (e.g. `v1.1.29`) or `latest` |
| `-NoCsharp` | off (→ with-csharp) | Install the plain variant instead |
| `-InstallDir` | `~/.local/bin` | Where the binary + helpers land |
| `-Force` | off | Reinstall even if already present |
| `-AddToPath` | off | Add `InstallDir` to user PATH if missing (prints a hint on Unix) |
| `-ConfigureMcp` | off | Merge a `codesearch` entry into the host MCP config |
| `-McpHost` | `auto` | `auto` \| `cursor` \| `claude` \| `windsurf` |
| `-Target` | cwd | Repo root (for the report + MCP config location) |
| `-DryRun` | off | Resolve + print the asset URL, download nothing |

`$GITHUB_TOKEN` (if set) is sent as a bearer token to avoid GitHub API rate limits.

## MCP wiring

`-ConfigureMcp` merges this into the host config without clobbering other servers
(`.cursor/mcp.json`, Claude `.mcp.json`, `.windsurf/mcp.json`):

```jsonc
{ "mcpServers": { "codesearch": { "command": "codesearch", "args": ["mcp"] } } }
```

Set `pipeline.manifest.json` → `code_search.primary` to `codesearch` once wired, so the
`code-search` skill prefers it.

## Quick CLI usage (after install)

```bash
codesearch index .                 # index the current repo
codesearch search "auth middleware" # semantic CLI search
codesearch mcp                     # stdio MCP server (what -ConfigureMcp launches)
codesearch serve                   # multi-repo HTTP server
```

## Outputs

| File | Purpose |
|------|---------|
| `~/.local/bin/codesearch[.exe]` (+ helpers) | Installed binary |
| Host MCP config (with `-ConfigureMcp`) | `codesearch` server entry |
| `.agents/codesearch-install-report.json` | Audit trail: version, variant, platform, asset, paths |

## Constraints

- **pwsh 7+** and network access to GitHub Releases required.
- macOS: the installer clears the Gatekeeper quarantine attribute best-effort; if it's still
  blocked, run `xattr -d com.apple.quarantine <path>` or approve in System Settings → Privacy.
- Exit codes: `0` ok, `1` unsupported platform / asset not found, `2` download/extract/verify failed.
