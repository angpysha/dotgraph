# Quickstart: Branch Diff Version Bump

Proves [spec.md](spec.md) against [branch-selection.md](contracts/branch-selection.md) and [cli-branch.md](contracts/cli-branch.md). The tool reads Git through LibGit2Sharp. The `git` executable is not required for the automated tests.

## Prerequisites

- .NET 10 SDK
- Repository root as the working directory
- For the manual checks: a solution that already has `.dotgraph.json` and a local `main` branch

## Automated

```bash
dotnet test --configuration Release
```

Expected: Core tests cover selection, version-tag-only exclusion, patch-from-branch, `1.0.0` for a new package, cascade when the live version is already the proposal, and no cascade when a package is left at the branch version. Scanner tests open a temporary repository with LibGit2Sharp, return a dirty tracked file, ignore an untracked file, and parse a version from the branch blob.

## Packed tool

From the repository root, pack the CLI and run `compare-branch` once against this repository. Expected: the command starts and either prints the saved branch or the existing missing-snapshot error. It must not fail with a missing native library.

## Manual checks

Use a copy or a branch of a solution with at least one internal package at a known version on `main`. Do not use the only copy of a solution you cannot revert.

| # | Do | Expect |
|---|---|---|
| 1 | `dotgraph compare-branch` on a snapshot that has never stored a branch | Prints `main`. Snapshot versions unchanged. |
| 2 | Change a tracked source file. Set that package’s live version to something else, such as `9.0.0`. `dotgraph propose --dry-run` | Proposes one patch above the `main` version, shows `9.0.0`, writes nothing. |
| 3 | Change only the version tag of another package. `dotgraph propose --dry-run` | That package is absent. |
| 4 | Add an untracked file under an existing package and do not change tracked files. | That package is not selected because of the new file. |
| 5 | `dotgraph propose`, answer no | No project file and no snapshot change. Exit 0. |
| 6 | `dotgraph propose`, confirm | Selected packages and follow-ups match the report. Snapshot matches the solution. |
| 7 | `dotgraph review`, accept every default | `Nothing will be written.` No file change. |
| 8 | `dotgraph review`, type a major version for a selected package | The dependent shown later is a minor follow-up from its live version, not a patch. Decline the summary. Nothing written. |
| 9 | `dotgraph compare-branch does-not-exist`, then `dotgraph propose --dry-run` | The name is saved. Propose names the missing branch, writes nothing, and does not clear the name. |
| 10 | `dotgraph compare-branch main` | The next preview uses `main` again. |
| 11 | `dotgraph update --interactive` or `dotgraph sync --interactive` on a normal version edit | Accept proposed is still focused first. The package list is not limited to the branch diff. |

## Done

Automated tests pass, the packed tool loads the native library, and checks 1–11 match the expected column.
