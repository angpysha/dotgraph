# dotgraph — NuGet Package Graph Tool

A .NET CLI tool for managing version cascades across internally published NuGet packages within a solution.

## The Problem

When you own a suite of packages that reference each other via `<ProjectReference>`, publishing becomes tricky:

- Package **C** (v1.0.0) is published to your NuGet feed
- Package **B** depends on C → its published `.nuspec` declares `<dependency id="C" version="1.0.0" />`
- You bump C to **v1.1.0** and publish it
- Now B must be re-published so consumers get the correct C version
- But the NuGet feed **rejects re-publishing the same version** — B's `<Version>` must also change
- This cascades: if A depends on B, A may also need a version bump

`dotgraph` automates detecting and applying this cascade.

## Quick Start

```bash
# 1. Install
dotnet tool install --global dotgraph

# 2. Navigate to your solution directory
cd /path/to/your/solution

# 3. Build the initial dependency graph
dotgraph init

# --- Auto-detect workflow (recommended) ---

# 4. Edit <Version> in one or more .csproj files manually, then:
dotgraph diff              # see what changed and what cascade bumps are missing
dotgraph sync              # apply the missing bumps
dotgraph sync --interactive # review each proposal one by one

# --- Explicit workflow ---

# 4b. Let dotgraph bump a specific package and cascade for you
dotgraph update MyLib.Core 2.1.0
dotgraph update MyLib.Core 2.1.0 --interactive
```

## Commands

| Command | Description |
|---|---|
| `dotgraph init` | Scan solution, build initial graph, save `.dotgraph.json` |
| `dotgraph refresh` | Rescan solution and update the snapshot (versions + structure) |
| `dotgraph diff` | Compare live `.csproj` versions to snapshot — show what changed and what's missing |
| `dotgraph sync` | Auto-detect all version changes and propose/apply cascade bumps for gaps |
| `dotgraph sync --interactive` | Same, but walk through each proposal interactively |
| `dotgraph sync --dry-run` | Show detected changes and proposals without writing any files |
| `dotgraph analyze <pkg> [<pkg>...]` | Show affected upstream packages for named packages (dry run) |
| `dotgraph update <pkg> <version> [<pkg> <version>...]` | Bump one or more packages and cascade all affected dependents |
| `dotgraph update ... --interactive` | Walk through each proposal interactively |
| `dotgraph update ... --dry-run` | Show proposals without applying any changes |

## Auto-detect Workflow

The most common workflow: you manually edit one or more `<Version>` tags in `.csproj` files, then let `dotgraph` figure out the rest.

```bash
# After editing MyLib.Core.csproj and MyLib.Caching.csproj manually:

dotgraph diff
```

```
Changed packages (vs snapshot):
  MyLib.Core      1.2.0 → 2.0.0   [MAJOR]
  MyLib.Caching   1.1.0 → 1.2.0   [MINOR]  ← also manually bumped

Cascade gaps (need version bumps):
  MyLib.Http      1.5.0   → propose 1.6.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Api       2.0.0   → propose 2.1.0   [MINOR]  depends on MyLib.Http

Already covered (no action needed):
  MyLib.Caching   1.1.0 → 1.2.0   [MINOR]  depends on MyLib.Core ✓

Run 'dotgraph sync' to apply the proposed cascade bumps.
```

```bash
dotgraph sync
```

```
  MyLib.Http    1.5.0 → 1.6.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Api     2.0.0 → 2.1.0   [MINOR]  depends on MyLib.Http

Apply 2 version changes? [Y/n]
```

## Explicit Update Examples

### Single package

```
$ dotgraph update MyLib.Core 2.1.0

  MyLib.Core        1.2.0 → 2.1.0   [MAJOR]  (explicit)
  MyLib.Http        1.5.0 → 1.6.0   [MINOR]  depends on MyLib.Core
  MyLib.Caching     1.1.0 → 1.2.0   [MINOR]  depends on MyLib.Core
  MyLib.Api         2.0.0 → 2.1.0   [MINOR]  depends on MyLib.Http, MyLib.Caching

Apply all proposals? [Y/n]
```

### Multiple packages at once

Pass several `<package> <version>` pairs in one command. Their affected sets are merged — each dependent receives the largest applicable bump from all its changed ancestors, and shared dependents appear only once:

```
$ dotgraph update MyLib.Core 2.0.0 MyLib.Abstractions 1.1.0

  MyLib.Abstractions  1.0.0 → 1.1.0   [MINOR]  (explicit)
  MyLib.Core          1.2.0 → 2.0.0   [MAJOR]  (explicit)
  MyLib.Http          1.5.0 → 1.6.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Caching       1.1.0 → 1.2.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Api           2.0.0 → 2.1.0   [MINOR]  depends on MyLib.Http, MyLib.Caching

Apply all proposals? [Y/n]
```

Note that `MyLib.Api` appears once even though it is transitively affected by both explicit changes. Its trigger bump is MAJOR (from `MyLib.Core`, which outranks `MyLib.Abstractions`'s MINOR).

```bash
# Same flags apply
dotgraph update MyLib.Core 2.0.0 MyLib.Abstractions 1.1.0 --dry-run
dotgraph update MyLib.Core 2.0.0 MyLib.Abstractions 1.1.0 --interactive
```

## Cascade Version Rules

| Trigger bump | Proposed bump for dependents |
|---|---|
| MAJOR | MINOR |
| MINOR | PATCH |
| PATCH | PATCH |

In interactive mode you can override any proposed version manually.

## Graph Snapshot

The tool stores the dependency graph in `.dotgraph.json` at the solution root. Commit this file — it enables `git diff` to show exactly what changed between graph states.

```json
{
  "solutionPath": "MyApp.slnx",
  "createdAt": "2026-05-07T12:00:00Z",
  "packages": {
    "MyLib.Core": {
      "version": "2.1.0",
      "projectPath": "src/MyLib.Core/MyLib.Core.csproj",
      "dependencies": []
    },
    "MyLib.Http": {
      "version": "1.6.0",
      "projectPath": "src/MyLib.Http/MyLib.Http.csproj",
      "dependencies": ["MyLib.Core"]
    }
  }
}
```

## Project Structure

```
NugetPackageHelper.slnx
src/
  NugetPackageHelper.Core/      # Domain types, SemVer logic, graph algorithms
  NugetPackageHelper.Scanner/   # .slnx/.sln and .csproj file parsing
  NugetPackageHelper.Cli/       # CLI entry point, commands, interactive mode
docs/
  design/
    software-design.md          # Architecture and design decisions
    data-model.md               # Type definitions and JSON schema
  user-guide.md                 # End-user walkthrough
```

## Requirements

- .NET 8.0 or later
- Solutions using `<ProjectReference>` with `<Version>` tags in `.csproj` files (SDK-style)

## License

MIT
