# Design-context pack

**Feature**: `specs/002-branch-diff-bump`  
**Status**: `complete`  
**Canonical plan**: [plan.md](./plan.md) · **Spec**: [spec.md](./spec.md)

This pack **supplements** Spec Kit artifacts. If it disagrees with `plan.md`, fix the pack
or update the plan via `/speckit.plan` — never fork architecture here.

## Architecture map

The plan matches the three runtime projects. No fourth project. No `git` process.

| Plan claim | Where it already lives |
|---|---|
| Patch and follow-up math | `SemVer.applyBump` and `CascadeEngine.computeProposals` in `src/NugetPackageHelper.Core/`. `findUpstreamOrdered` in `Graph.fs` returns dependents only, not the roots. |
| Tag order | `ProjectScanner.resolveVersion` / `resolveVersionWriteTarget` in `src/NugetPackageHelper.Scanner/ProjectScanner.fs`. |
| Snapshot file | `GraphPersistence` in `src/NugetPackageHelper.Core/GraphPersistence.fs` reads and writes `.dotgraph.json`. There is no `compareBranch` field today. |
| Live graph for cascade | `DiffEngine` builds `{ snapshot with Packages = updatedPackages }`. `Update.applyAll` and `Sync` do the same. Those copies keep every other record field, including a future `CompareBranch`. |
| Full rescan | `Refresh.run` and `ProjectScanner.buildGraph` rebuild packages and dependency links from the solution. `buildGraph` constructs the record with `SolutionPath`, `CreatedAt`, and `Packages` only. |
| Existing review | `Interactive.run` in `src/NugetPackageHelper.Cli/Interactive.fs` focuses Accept proposed, then Enter a version, then Leave unchanged. It does not recalculate later rows. `confirmSummary` is the shared yes/no summary. |
| Failures | Commands return `1` after `Output.error`. Missing snapshot text is already `".dotgraph.json not found. Run 'dotgraph init' first."` |
| Commands already registered | `init`, `refresh`, `analyze`, `diff`, `sync`, `update` in `src/NugetPackageHelper.Cli/Program.fs`. |
| Tests | xUnit + FsUnit. Graph literals are built in `GraphTests.fs`, `DiffEngineTests.fs`, `CascadeEngineTests.fs`, and `GraphPersistenceTests.fs`. |
| Native AOT | `NugetPackageHelper.Cli.fsproj` has `PackAsTool` and no `PublishAot`. |

`propose` and `review` must not save the graph the way `Update.applyAll` does. That path patches versions and leaves old dependency links. The spec wants links as they are after the write. After the project files are written, rescan with `SolutionScanner.scan` and `ProjectScanner.buildGraph`, copy `CompareBranch` from the loaded snapshot onto that fresh graph, and save. If `Graph.detectCycle` returns a cycle, stop with the same error `Refresh` uses and do not save.

`compare-branch` only loads, replaces `CompareBranch`, and saves. It does not rescan.

## Decision index

No ADR and no RFC. None of the forks are a quarter-long lock-in, and [research.md](./research.md) already records the alternatives. Replacing LibGit2Sharp later means replacing `GitWorktree.fs`, not a platform choice.

| Doc | Intent | Link |
|-----|--------|------|
| Research §1–2 | LibGit2Sharp 0.32.0 plus NativeBinaries 2.0.324, scanner only, no `git` process | [research.md](./research.md) |
| Research §3 | `compareBranch` on the snapshot; missing means `main` | [research.md](./research.md) |
| Research §4–5 | Which paths select a package, and patch-from-branch | [research.md](./research.md) |
| Research §6 | New `runBranchReview`; do not change `Interactive.run` | [research.md](./research.md) |
| Selection contract | In-memory rules the Core tests assert | [contracts/branch-selection.md](./contracts/branch-selection.md) |
| CLI contract | `compare-branch`, `propose`, `review` | [contracts/cli-branch.md](./contracts/cli-branch.md) |

The sentence “No `NEEDS CLARIFICATION` remains” in `plan.md` is a closed note. It is not an open question.

## Task-split hints

Plan step 2 adds a required `CompareBranch` field. F# record construction then fails everywhere the record is built. That step owns every existing literal, not only persistence. `versionFromXml` and `GitWorktree.fs` stay in the scanner step after those literals compile.

Groups with **disjoint file ownership** (safe to mark `[P]` in `/speckit.tasks` only after the record step has landed):

| Group | Files | Notes |
|---|---|---|
| Record | `src/NugetPackageHelper.Core/Types.fs`, `src/NugetPackageHelper.Core/GraphPersistence.fs`, the `DependencyGraph` literal in `src/NugetPackageHelper.Scanner/ProjectScanner.fs` (`buildGraph` only), `tests/NugetPackageHelper.Core.Tests/GraphTests.fs`, `DiffEngineTests.fs`, `CascadeEngineTests.fs`, `GraphPersistenceTests.fs` | One task. Missing JSON loads as `main`. Saves keep the name. `buildGraph` may set `main`; callers that already loaded a snapshot overwrite with `{ fresh with CompareBranch = loaded.CompareBranch }` before save. |
| Proposal | `src/NugetPackageHelper.Core/BranchProposal.fs`, `src/NugetPackageHelper.Core/NugetPackageHelper.Core.fsproj`, `tests/NugetPackageHelper.Core.Tests/BranchProposalTests.fs` | New file, listed after `CascadeEngine.fs`. No LibGit2Sharp. Calls `applyBump` and `computeProposals`. |
| Git IO | `src/NugetPackageHelper.Scanner/GitWorktree.fs`, `versionFromXml` in `src/NugetPackageHelper.Scanner/ProjectScanner.fs`, `src/NugetPackageHelper.Scanner/NugetPackageHelper.Scanner.fsproj`, `tests/NugetPackageHelper.Scanner.Tests/GitWorktreeTests.fs` | Package reference only on the scanner project. Temporary repository in the test. |
| CLI | `src/NugetPackageHelper.Cli/Program.fs`, `Interactive.fs`, `Output.fs`, `Commands/CompareBranch.fs`, `Commands/Propose.fs`, `Commands/Review.fs`, `NugetPackageHelper.Cli.fsproj` | `runBranchReview` is new. `Interactive.run` stays Accept-first. After a confirmed write, rescan and copy `CompareBranch`. |
| Guide | `docs/user-guide.md` | After the three commands exist. |

Proposal and Git IO may run in parallel with each other. They must not run in parallel with Record. CLI waits for both. The guide waits for CLI.

**Contended files** (must stay sequential — do not parallelize):

- `src/NugetPackageHelper.Scanner/ProjectScanner.fs` — Record touches the `buildGraph` literal; Git IO adds `versionFromXml` later.
- `src/NugetPackageHelper.Core/Types.fs` — Record only.
- `src/NugetPackageHelper.Cli/Interactive.fs` — CLI only. Do not split `run` and `runBranchReview` across tasks.
- `src/NugetPackageHelper.Cli/Program.fs` — CLI only.

## Subagent findings

- **architect**: `not-run` — hub checked the plan against `CascadeEngine`, `GraphPersistence`, `ProjectScanner.buildGraph`, `Refresh`, `Update.applyAll`, and `Interactive.run`.
- **team-lead**: `not-run` — file ownership above is from those same construction sites. No `tasks.md` and no `br` issues were written.

## Open blockers

- none
