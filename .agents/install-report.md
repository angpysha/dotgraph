# dotgraph — Adapt Report

**Date:** 2026-08-30  
**Code search:** Serena MCP (`--use-serena-mcp`)  
**Confidence:** high

## Detection

| Signal | Source | Match |
|--------|--------|-------|
| F# / .NET 10 CLI | PROJECT.md + `*.fsproj` | dotnet-minimal |
| Solution | `NugetPackageHelper.slnx` | dotnet-minimal |
| xUnit tests | `tests/*Tests.fsproj` | dotnet-minimal |
| GitHub CI | `.github/workflows/` | pr: github |
| Serena project | `.serena/project.yml` | code_search: serena |
| NuGet tool publish | `publish.yml` + PackAsTool | dotnet-minimal |

## Recommended packs

| Pack | Score | Features |
|------|-------|----------|
| dotnet-minimal | 0.95 | — |

## Recommended agents

coordinator, ba-analyst, architect, team-lead, developer, tester, tech-writer

## Build / test

```bash
dotnet build --configuration Release --verbosity minimal
dotnet test --configuration Release --verbosity minimal
```

## Code search (Serena)

- **Primary:** `serena`
- **Project:** `package_helper` (`.serena/project.yml`)
- **Discovery tools:** `activate_project`, `find_symbol`, `search_for_pattern`, `get_symbols_overview`, `find_file`, `list_dir`, `read_file`
- **After edits:** restart LSP if symbols stale (`restart_language_server`)

## Next steps

1. `agentic-tool apply --target .`
2. `agentic-tool sync --target . --host auto`
3. `agentic-tool verify --target .`
4. Seed `/speckit.constitution` from `PROJECT.md` if not already done
