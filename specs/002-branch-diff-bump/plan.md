# Implementation Plan: Branch Diff Version Bump

**Branch**: `feature/42-branch-diff-bump` | **Date**: 2026-10-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-branch-diff-bump/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Developers compare the current solution with a saved branch (default `main`), see which packages have code changes, and get a patch proposal taken from that branch’s version. Confirming writes those versions, cascades dependents, and refreshes `.dotgraph.json`. A separate review edits only that set and writes nothing unless the developer opts in.

Git facts come from NuGet packages, not from the `git` executable. `LibGit2Sharp` 0.32.0 reads the branch tip and the working tree; it brings `LibGit2Sharp.NativeBinaries` 2.0.324. Selection and the patch math stay in Core and call the existing `SemVer.applyBump` and `CascadeEngine`. The scanner is the only project that references the git packages.

## Technical Context

**Language/Version**: F# on .NET 10 (`net10.0`)

**Primary Dependencies**: LibGit2Sharp 0.32.0 and LibGit2Sharp.NativeBinaries 2.0.324 (branch tip, tree diff, file text at that tip). Spectre.Console 0.55.2 and System.CommandLine 3.0.0-preview.3.26207.106 stay as they are. LibGit2Sharp targets `net8.0`; the `net10.0` tool consumes that asset. No `PublishAot`.

**Storage**: SDK-style project files for versions. `.dotgraph.json` gains an optional root field `compareBranch`. Missing means `main`. Package versions and dependency links stay in the same snapshot.

**Testing**: xUnit + FsUnit. `dotnet test --configuration Release`. Selection and proposal tests in `tests/NugetPackageHelper.Core.Tests` take plain inputs and do not load the native library. Scanner tests create a temporary repository through LibGit2Sharp and read it back.

**Target Platform**: Local developer terminal (macOS, Linux, Windows). `dotgraph` global tool. The `git` executable is not required.

**Project Type**: Libraries plus a thin CLI.

**Performance Goals**: A preview of a solution of at least 20 packages, including the tree diff, appears in one report in under 2 seconds on local disk. A review of 10 packages stays under 3 minutes and is limited by the prompts (spec SC-006).

**Constraints**: Offline. No fetch, no network, no `git` process. Untracked paths do not select an existing package. Write only after confirmation. Leave the existing `update` and `sync` reviews unchanged. Native binaries must load inside `dotnet test` and inside the packed tool.

**Scale/Scope**: One solution on one workstation. Tens to a few hundred projects. Three new commands. No new runtime project.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
|---|---|---|
| I. Library-First | Which packages are selected, and which version is proposed, live in `NugetPackageHelper.Core`. Reading the repository and the project XML lives in `NugetPackageHelper.Scanner`. The CLI only prints, prompts, and writes through the scanner. | Pass |
| II. CLI Interface | New `dotgraph` subcommands `compare-branch`, `propose`, and `review`. Failures use `Output.error` and exit 1. | Pass |
| III. Test-First | Core cases land before the proposal module is treated as done. Scanner cases that open a real repository land before `GitWorktree` is treated as done. `dotnet test --configuration Release`. | Pass |
| IV. Semver Cascade Integrity | A patch uses `SemVer.applyBump Patch`. Follow-ups still come only from `CascadeEngine.computeProposals`. Tag order stays `PackageVersion` → `Version` → `VersionPrefix`/`VersionSuffix` → `PackagePrefix`/`PackageSuffix`. | Pass |
| V. Simplicity | No new project. One new git library plus the native package it already depends on. Existing `Interactive.run` is not retuned; the branch review is a separate function. | Pass |

## Project Structure

### Documentation (this feature)

```text
specs/002-branch-diff-bump/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── branch-selection.md
│   └── cli-branch.md
└── tasks.md             # Phase 2 (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
src/NugetPackageHelper.Core/
├── Types.fs                 # DependencyGraph gains CompareBranch
├── SemVer.fs                # unchanged bump rules; callers use applyBump
├── CascadeEngine.fs        # unchanged; follow-ups only
├── GraphPersistence.fs      # read/write compareBranch; missing means main
└── BranchProposal.fs        # select, patch-from-branch, cascade inputs

src/NugetPackageHelper.Scanner/
├── NugetPackageHelper.Scanner.fsproj   # LibGit2Sharp 0.32.0
├── ProjectScanner.fs        # versionFromXml reuses resolveVersion
└── GitWorktree.fs           # branch lookup, changed paths, blob text

src/NugetPackageHelper.Cli/
├── Program.fs               # compare-branch, propose, review
├── Output.fs                # same change-size words; show both versions
├── Interactive.fs           # runBranchReview; existing run stays as it is
└── Commands/
    ├── CompareBranch.fs
    ├── Propose.fs
    └── Review.fs

tests/NugetPackageHelper.Core.Tests/
└── BranchProposalTests.fs

tests/NugetPackageHelper.Scanner.Tests/
└── GitWorktreeTests.fs      # temp repository via LibGit2Sharp

docs/user-guide.md           # the three commands, after they exist
```

**Structure Decision**: Core, Scanner, and CLI stay the three runtime projects. Core does not reference LibGit2Sharp, so proposal tests stay free of native binaries. Scanner owns repository IO the same way it owns project-file IO. The CLI does not compute a bump or parse a tree.

## Complexity Tracking

No constitution violations. This section is intentionally empty.

## Phase 0 — Research

Recorded in [research.md](research.md). No `NEEDS CLARIFICATION` remains.

- LibGit2Sharp 0.32.0 reads the compare-branch tree and the working tree. The `git` executable is not called.
- `compareBranch` is a root field on `.dotgraph.json`. Absence means `main`.
- A path selects an existing package only when that path exists on the compare branch and differs now. A project that is absent from that branch is new and proposed as `1.0.0`.
- Version-tag-only edits are detected by comparing project XML with the version tags removed, not by a line-number heuristic.
- Follow-ups reuse `CascadeEngine` against live versions. Selected packages use the compare-branch version as their base.
- The branch review is a new interactive function. `Interactive.run` keeps Accept focused first.

## Phase 1 — Design

- [data-model.md](data-model.md) — compare branch, changed path, selected package, proposal, review decision.
- [contracts/branch-selection.md](contracts/branch-selection.md) — which paths count, and how a version is chosen.
- [contracts/cli-branch.md](contracts/cli-branch.md) — `compare-branch`, `propose`, `review`, exit codes.
- [quickstart.md](quickstart.md) — `dotnet test` plus the manual checks from the spec.

## Implementation sequence

Test-first, in this order:

1. Core tests for path-to-package mapping, version-tag-only exclusion, patch-from-branch, a new package at `1.0.0`, “already at the proposal still cascades”, and “leave unchanged at the branch version does not cascade”. Then implement `BranchProposal.fs`. Root pairs passed into `CascadeEngine` are `(name, compareBranchVersion, chosenVersion)` on a graph whose node versions are the live ones.
2. Persistence tests: missing `compareBranch` loads as `main`; a saved name round-trips; a later `save` of versions does not drop the name. Then extend `DependencyGraph` and `GraphPersistence`.
3. Scanner tests: a temporary repository whose `main` commit contains a project file; a dirty tracked file is returned; an untracked file is not; blob text at `main` parses through `versionFromXml`; a missing branch name is an error. Then add the LibGit2Sharp reference, `versionFromXml`, and `GitWorktree.fs`.
4. CLI `compare-branch` reads and writes only that field. `propose --dry-run` prints the contract report and writes nothing. `propose` asks once, plus an extra confirm for each earlier release unless `--force`. `review` uses `runBranchReview`, focuses Leave unchanged, recalculates before later packages, and writes only after a non-empty summary is confirmed.
5. Update `docs/user-guide.md` after the three commands exist.
6. Run the quickstart, including one packed-tool launch that opens a repository, so a missing native binary fails here rather than after publish.

## Constitution Check (post-design)

Re-checked against the data model and both contracts. Gates I–V still pass. LibGit2Sharp stays in the scanner. Core still owns the proposal. `CascadeEngine` is still the only follow-up calculator. The new commands do not change `update` or `sync`.

## Design-context supplement

Links only. Technical Context above stays the source of truth.

- [design-context.md](design-context.md) — file map, task-split ownership, and the rescan-after-write seam.
- No ADR and no RFC. Alternatives stay in [research.md](research.md).
