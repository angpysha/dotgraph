# Implementation Plan: Package Prefix and Suffix Updates

**Branch**: `feature/42-prefix-suffix-console` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-prefix-suffix-console/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Developers need every in-solution package version — including a numeric prefix and an optional release suffix — to update in the project tag that already holds it, and they need the existing console review to show those two parts clearly with or without color.

The work extends the current F# libraries. `SemVer` gains pre-release ordering and stops clearing the suffix on a follow-up bump. `CascadeEngine` does not cascade a suffix-only change or an earlier release. `ProjectScanner` appends `PackagePrefix` / `PackageSuffix` after the three tag pairs it already supports. The CLI review, already on `update` and `sync`, shows prefix, suffix, progress, and a single confirmation, using the Spectre.Console colors already in `Output`.

## Technical Context

**Language/Version**: F# on .NET 10 (`net10.0`)

**Primary Dependencies**: Spectre.Console 0.55.2 (CLI markup and prompts), System.CommandLine 3.0.0-preview.3 (existing commands). No new package.

**Storage**: SDK-style project files for the version tags; `.dotgraph.json` for the snapshot. The snapshot already stores `SemVer.toString`, so the suffix is already in the file format.

**Testing**: xUnit + FsUnit. `dotnet test --configuration Release`. New cases go in `tests/NugetPackageHelper.Core.Tests` and `tests/NugetPackageHelper.Scanner.Tests`.

**Target Platform**: Local developer terminal (macOS, Linux, Windows). `dotgraph` global tool.

**Project Type**: Libraries plus a thin CLI.

**Performance Goals**: A preview of a solution of at least 20 packages appears in one report in under 2 seconds on local disk. Interactive review of 10 packages is limited by reading the prompts, not by the tool (spec SC-004: under 3 minutes).

**Constraints**: Offline. No network. Color is never the only signal. `NO_COLOR` and redirected stdout stay plain text. Write only after confirmation. Do not create a version tag that lost the read.

**Scale/Scope**: One solution on one workstation. Tens to a few hundred projects. Four existing commands gain behavior (`diff`, `update`, `sync`, and the shared review). No new command.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
|---|---|---|
| I. Library-First | Version rules and tag IO live in `NugetPackageHelper.Core` and `NugetPackageHelper.Scanner`. The CLI only prompts and prints. | Pass |
| II. CLI Interface | Existing `dotgraph` subcommands. Failures stay on stderr via `Output.error` and exit 1. | Pass |
| III. Test-First | Behavior changes land with tests in the two library test projects before the implementation is treated as done. `dotnet test --configuration Release`. | Pass |
| IV. Semver Cascade Integrity | Read and write share one tag order. The constitution's order `PackageVersion` → `Version` → `VersionPrefix`/`VersionSuffix` is unchanged. `PackagePrefix`/`PackageSuffix` is appended after it, as clarified. `CascadeEngine` remains the only bump source. `applyBump` keeps the suffix instead of clearing it. | Pass |
| V. Simplicity | Extend `SemVer`, `BumpType`, `ProjectScanner`, and `Interactive`. No new project, package, or command. | Pass |

Post-design re-check: the contracts and data model use those same types and the same tag order. No gate failed. Principle IV's sentence in `.specify/memory/constitution.md` should gain the fourth pair during implementation so the written principle matches the clarified order. That is a one-line alignment, not a violation.

## Project Structure

### Documentation (this feature)

```text
specs/001-prefix-suffix-console/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── version-tags.md
│   └── cli-review.md
└── tasks.md             # Phase 2 (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
src/NugetPackageHelper.Core/
├── Types.fs                 # BumpType gains Suffix
├── SemVer.fs                # compare, detectBump, applyBump
├── CascadeEngine.fs        # skip suffix-only and downgrade roots
├── DiffEngine.fs            # suffix-only rows become Changed
└── GraphPersistence.fs      # unchanged format; already stores toString

src/NugetPackageHelper.Scanner/
└── ProjectScanner.fs        # fourth tag pair; shared read/write winner

src/NugetPackageHelper.Cli/
├── Output.fs                # prefix/suffix columns; shared change-size markup
├── Interactive.fs           # N of M, choices, summary groups, downgrade confirm
├── Commands/Update.fs       # interactive downgrade stays in the review
└── Commands/Sync.fs         # same review; dry-run text through Output

tests/NugetPackageHelper.Core.Tests/
├── SemVerTests.fs
├── CascadeEngineTests.fs
└── DiffEngineTests.fs

tests/NugetPackageHelper.Scanner.Tests/
└── ProjectScannerTests.fs

docs/user-guide.md           # console examples updated with the review
.specify/memory/constitution.md  # append PackagePrefix/PackageSuffix to principle IV
```

**Structure Decision**: The repo is already three projects (Core, Scanner, CLI) plus two test projects. This feature stays inside them. Core owns ordering and bumps. Scanner owns XML tags. CLI owns Spectre prompts. Tests stay on the libraries; the console walk-through is the quickstart.

## Complexity Tracking

No constitution violations. This section is intentionally empty.

## Phase 0 — Research

Recorded in [research.md](research.md). No `NEEDS CLARIFICATION` remains.

- Follow-up bumps keep `PreRelease` inside `applyBump`.
- `Suffix` is a change size and does not cascade. An earlier release does not cascade.
- Pre-release compare uses dotted identifier rules.
- Tag winner order matches the 2026-10-16 clarification.
- Spectre.Console 0.55 stays the renderer and honors `NO_COLOR`.

## Phase 1 — Design

- [data-model.md](data-model.md) — version, change size, winning tag, proposal, review decision, snapshot, diff.
- [contracts/version-tags.md](contracts/version-tags.md) — read, write, and the examples from the spec.
- [contracts/cli-review.md](contracts/cli-review.md) — preview, interactive steps, exit codes.
- [quickstart.md](quickstart.md) — `dotnet test` plus nine manual checks.

## Implementation sequence

Test-first, in this order:

1. Core tests for compare, `isDowngrade`, `detectBump` (`Suffix`), and `applyBump` preserving the suffix. Then implement them in `SemVer.fs`.
2. Core tests that a suffix-only root and a downgrade root produce no proposals, and that a dependent at `1.2.0-beta` keeps `beta` on a patch follow-up. Then implement that in `CascadeEngine.fs`.
3. Core test that a suffix-only live version is `Changed` with `BumpType.Suffix`. `DiffEngine` already uses `compare` and `detectBump`, so this follows from step 1.
4. Scanner tests for the `PackagePrefix` / `PackageSuffix` examples in the version-tag contract, including "earlier tag wins" and "do not create an earlier tag". Then extend `ProjectScanner`.
5. CLI: `Output` prints prefix, suffix, and the shared color words. `Interactive` implements the review contract as soon as those helpers exist. It displays the proposal it is given and does not wait for `CascadeEngine`. `Update` and `Sync` wait for both the review and the suffix-preserving cascade before they write. `Update` lets an interactive downgrade reach that review. `Sync` uses the same summary rule for an empty write set.
6. Update `.specify/memory/constitution.md` principle IV as soon as the tag order is accepted. It does not wait for `ProjectScanner`. Update `docs/user-guide.md` after the review commands exist. The guide does not wait for `ProjectScanner`; it follows the tag and review contracts. The quickstart still waits for the scanner implementation, the suffix-preserving cascade, the diff, the review commands, and both docs.
7. Run the quickstart.

## Constitution Check (post-design)

Re-checked against the data model and both contracts. Gates I–V still pass. The appended tag pair and the `Suffix` bump case stay inside Core and Scanner. The CLI does not compute bumps or choose tags.
