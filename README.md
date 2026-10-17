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

# --- Branch-diff workflow (git compare) ---

# 4c. After editing code on your branch, bump from the compare-branch baseline (see below)
dotgraph propose --dry-run
dotgraph propose              # or: dotgraph review
```

## Commands

| Command | Description |
|---|---|
| `dotgraph init` | Scan solution, build initial graph, save `.dotgraph.json` |
| `dotgraph refresh` | Rescan solution and update the snapshot (versions + structure) |
| `dotgraph diff` | Compare live `.csproj` versions to **snapshot** — show what changed and what's missing |
| `dotgraph sync` | Auto-detect all version changes and propose/apply cascade bumps for gaps |
| `dotgraph sync --interactive` | Same, but walk through each proposal interactively |
| `dotgraph sync --dry-run` | Show detected changes and proposals without writing any files |
| `dotgraph compare-branch [<name>]` | Print the saved compare branch, or store a new name in `.dotgraph.json` |
| `dotgraph propose [--dry-run] [--force]` | Propose patches from **git changes vs compare branch**, then confirm and apply |
| `dotgraph review [--force]` | Walk through branch proposals interactively; writes only after you confirm |
| `dotgraph analyze <pkg> [<pkg>...]` | Show affected upstream packages for named packages (dry run) |
| `dotgraph update <pkg> <version> [<pkg> <version>...]` | Bump one or more packages and cascade all affected dependents |
| `dotgraph update ... --interactive` | Walk through each proposal interactively |
| `dotgraph update ... --dry-run` | Show proposals without applying any changes |

### Snapshot workflow vs branch-diff workflow

| | `diff` / `sync` | `propose` / `review` |
|---|---|---|
| Detects | Version tags you changed since the last `.dotgraph.json` snapshot | Files that differ from a **git compare branch** (default `main`) |
| Root version basis | Whatever you already wrote in `.csproj` | **One patch above the version on the compare branch** (not the live version) |
| Typical use | You bumped `<Version>` manually, need cascade only | You changed code; let dotgraph pick roots and cascade |

Details: [docs/user-guide.md](docs/user-guide.md) (Step 6).

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

## Branch-diff workflow (git compare)

Use this when you work on a feature branch and want dotgraph to find which internal packages changed (vs `main` or another baseline), propose a patch bump from each package’s version on that branch, and cascade dependents from their live versions.

Prerequisites:

- Run `dotgraph init` once and commit `.dotgraph.json`.
- The solution must live inside a git repository (dotgraph reads the repo directly; the `git` CLI is not required).
- The compare branch name is stored in `.dotgraph.json` as `compareBranch` (default `main` if never set).

Optional — change the baseline branch (does not rescan packages or verify the branch exists):

```bash
dotgraph compare-branch              # print saved name
dotgraph compare-branch release/1.4  # store new name
```

End-to-end example (e.g. you shipped `MyLib.*` at 0.3.1 on `main`, developed on a branch, and want consistent bumps before release):

```bash
cd /path/to/your/solution

# One-time (if not already done)
dotgraph init
git add .dotgraph.json && git commit -m "Add dotgraph snapshot"

# Optional baseline (default is main)
# dotgraph compare-branch main

# Implement features — edit source and/or .csproj; manual version bumps are optional
# dotgraph only selects packages whose non-version project files changed vs the compare branch

# Preview: selected packages, branch vs live versions, patch proposals, cascade follow-ups, warnings
dotgraph propose --dry-run

# Apply after review (non-interactive confirm)
dotgraph propose

# Or review each selected package and follow-up interactively (Leave unchanged is the default focus)
dotgraph review
```

How proposals are calculated: for each selected package, the proposed root version is derived from the semver on the compare branch (e.g. branch `1.4.2` → propose `1.4.3`), not from the version currently in your working tree. If live is already `9.0.0` but branch was `1.4.2`, the proposal is still `1.4.3` from the branch baseline. Cascade follow-ups use the usual rules from each dependent’s live version. Packages with only version-tag edits (no other file changes) are not selected as roots.

`dotgraph propose` prints the report, may ask about earlier releases (proposed below live) unless you pass `--force`, then applies confirmed writes and rescans the solution into `.dotgraph.json`. `dotgraph propose --dry-run` prints the same report and writes nothing.

### Releasing the `dotgraph` CLI (not your solution packages)

Version 0.3.x → 0.4.0 for the tool itself is the `<Version>` in `src/NugetPackageHelper.Cli/NugetPackageHelper.Cli.fsproj` (currently `0.4.0`). Publishing to NuGet.org is triggered by pushing a git tag `v*.*.*` (see `.github/workflows/publish.yml`); the workflow sets `PackageVersion` from the tag. That release path is separate from `propose` / `diff` / `sync` on your own multi-package solution.

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
