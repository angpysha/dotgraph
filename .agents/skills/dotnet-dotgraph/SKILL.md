---
name: dotnet-dotgraph
description: >-
  Manage internal NuGet package version cascades with the dotgraph CLI. Use when a solution
  has multiple packable projects with ProjectReference + Version tags. Commands init, diff,
  sync, update, analyze, refresh. Interactive sync/update for human review.
disable-model-invocation: true
---

# dotnet-dotgraph

Deterministic wrapper for **[dotgraph](https://www.nuget.org/packages/dotgraph)** — a .NET global
tool that detects and applies **version cascade bumps** when internal NuGet packages reference
each other.

Use when your solution publishes **multiple packages** to a feed and dependents must bump when
an upstream `<Version>` changes (NuGet rejects republishing the same version).

## When to use

| Situation | Command |
|-----------|---------|
| First time on a multi-package solution | `init` |
| You edited `<Version>` in one or more `.csproj` manually | `diff` → `sync` |
| You want dotgraph to bump a package + cascade dependents | `update` |
| Rescan solution structure after project changes | `refresh` |
| Preview affected upstream packages | `analyze` |

**Not needed** for single-app repos with only external NuGet references.

## Prerequisites

- SDK-style `.csproj` with `<Version>` tags
- Internal dependencies via `<ProjectReference>` (not only `PackageReference`)
- Commit **`.dotgraph.json`** at the solution root (created by `init`)

Install tool once (script auto-installs global tool if missing):

```powershell
pwsh .cursor/skills/dotnet-dotgraph/scripts/dotnet-dotgraph.ps1 ensure-tool
```

Or local manifest:

```bash
dotnet new tool-manifest
dotnet tool install --local dotgraph --version 0.3.0
```

## Commands

```powershell
$DG = '.cursor/skills/dotnet-dotgraph/scripts/dotnet-dotgraph.ps1'

# Bootstrap graph snapshot
pwsh $DG init

# After manual Version edits — show gaps
pwsh $DG diff

# Propose cascade (no writes)
pwsh $DG sync -DryRun

# Apply cascade (prompts Y/n)
pwsh $DG sync

# Human reviews each bump
pwsh $DG sync -Interactive

# Explicit bump + cascade
pwsh $DG update MyLib.Core 2.1.0 -DryRun
pwsh $DG update MyLib.Core 2.1.0 -Interactive

# Multiple packages
pwsh $DG update MyLib.Core 2.0.0 MyLib.Abstractions 1.1.0 -DryRun

# Rescan solution
pwsh $DG refresh

# Dry-run affected set
pwsh $DG analyze MyLib.Core MyLib.Http
```

## Interactive workflow (recommended)

1. Developer or human edits `<Version>` in `.csproj` file(s).
2. Run **`diff`** — agent shows cascade gaps vs `.dotgraph.json` snapshot.
3. Run **`sync -DryRun`** — show proposals without writing.
4. **Human confirms** → `sync` or `sync -Interactive`.
5. Run **`dotnet-format`** + **`dotnet-unit-tests`** + `build.command`.
6. Commit `.csproj` version changes **and** `.dotgraph.json`.

Never run `sync` without human approval when the pipeline is in a gated phase.

## Cascade rules (dotgraph)

| Upstream bump | Dependent proposal |
|---------------|-------------------|
| MAJOR | MINOR |
| MINOR | PATCH |
| PATCH | PATCH |

Override per package in `-Interactive` mode.

## Outputs

| File | Purpose |
|------|---------|
| `.dotgraph.json` | Graph snapshot — **commit to git** |
| `.agents/dotgraph-report.json` | Last command, exit code, paths |
| `.agents/dotgraph-last-run.log` | Full CLI output (token-saving handoff) |

Cite report + log paths in chat; do not paste full diff output.

## Manifest override (optional)

```json
"dotgraph": {
  "toolVersion": "0.3.0",
  "snapshot": ".dotgraph.json"
}
```

## Checkpoint

```powershell
pwsh $DG diff 2>&1 | pwsh .cursor/skills/checkpoint/scripts/save-artifact.ps1 `
  -Session <session> -ArtifactRel gates/dotgraph-diff.log -Mode --stdin
```

## Constraints

- Requires **.NET 8+** (tool targets .NET 10; install via [NuGet](https://www.nuget.org/packages/dotgraph)).
- Only for **internal** package graphs — not a general `dotnet add package` replacement.
- After `sync` / `update`, always verify build + tests.
