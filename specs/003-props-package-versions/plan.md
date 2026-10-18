# Implementation Plan: Write Package Versions to a Props File

**Branch**: `feature/42-props-package-versions` | **Date**: 2026-10-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-props-package-versions/spec.md`

Planning input: the props file path is stored on `.dotgraph.json`, the existing dotgraph settings file. It is not a second settings file.

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

The developer saves one props-file path on `.dotgraph.json` and later asks the tool to write every package in that saved list into the props file. The write adds or updates a single item group labeled `Dotgraph`. Each entry is a `PackageVersion` item whose `Include` is the package name and whose `Version` is the version already stored in the snapshot, release label included. Project files are not opened for this write, and the snapshot’s package versions are not changed.

The path is the root property `propsPath`. A missing property means the write is off. `props-path` prints, replaces, or clears that property. `export-props` is the only command that writes the props file. A rescan that replaces the snapshot must copy `propsPath` from the snapshot it loaded, so `refresh`, `sync`, and `propose` do not drop it.

## Technical Context

**Language/Version**: F# on .NET 10 (`net10.0`)

**Primary Dependencies**: None added. JSON stays on `System.Text.Json.Nodes`, already used by `GraphPersistence`. Props XML is handled as text plus `System.Xml.Linq`, already referenced by Core. Spectre.Console 0.55.2 and System.CommandLine 3.0.0-preview.3.26207.106 stay as they are.

**Storage**: `.dotgraph.json` gains an optional root property `propsPath` (`DependencyGraph.PropsPath: string option`). Absent or cleared means no path. The value is stored as the developer typed it, relative or absolute, after trimming. The props file itself is MSBuild XML. Package versions and dependency links stay in `packages`.

**Testing**: xUnit + FsUnit. `dotnet test --configuration Release`. Persistence and props-text tests live in `tests/NugetPackageHelper.Core.Tests`. They use temporary directories and XML strings. They do not scan a solution.

**Target Platform**: Local developer terminal (macOS, Linux, Windows). `dotgraph` global tool.

**Project Type**: Libraries plus a thin CLI.

**Performance Goals**: A saved list of 20 packages is written in one step in under one second on local disk (spec SC-001). The bound is file size, not a prompt.

**Constraints**: Offline. Do not rescan. Do not write project version tags. Do not write the props file from `init`, `refresh`, `diff`, `sync`, `update`, `propose`, or `review`. Do not reformat XML outside the `Dotgraph` item group. Do not create a missing parent folder. Do not delete the props file when the path is cleared. One path, one file.

**Scale/Scope**: One solution, one props path, tens to a few hundred packages. Two new commands. No new runtime project and no new package reference.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Result |
|---|---|---|
| I. Library-First | Sorting, the item-group text, and the splice that preserves the rest of the file live in `NugetPackageHelper.Core`. The CLI loads `.dotgraph.json`, checks the path on disk, and writes bytes. The scanner is not asked to read or write the props file. | Pass |
| II. CLI Interface | New subcommands `props-path` and `export-props`. Failures use `Output.error` and exit 1. A successful write and a deliberate no-op exit 0. | Pass |
| III. Test-First | Persistence and props-text tests land before `PropsExport` and the `propsPath` field are treated as done. `dotnet test --configuration Release`. | Pass |
| IV. Semver Cascade Integrity | The written version is `SemVer.toString` of the version already in the snapshot. This feature does not bump, does not call `CascadeEngine`, and does not choose a project-file tag. | Pass |
| V. Simplicity | No new project and no new dependency. One optional field, one Core module, two commands. `ProjectScanner.writeVersion` is not reused; it updates a project property, not a props item group. | Pass |

## Project Structure

### Documentation (this feature)

```text
specs/003-props-package-versions/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── props-file.md
│   └── cli-props.md
└── tasks.md             # Phase 2 (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
src/NugetPackageHelper.Core/
├── Types.fs                 # DependencyGraph gains PropsPath: string option
├── GraphPersistence.fs      # read/write propsPath; omit the property when unset
└── PropsExport.fs           # ordered entries, group text, splice, path checks

src/NugetPackageHelper.Scanner/
└── ProjectScanner.fs        # buildGraph sets PropsPath to None; callers copy the loaded value before save

src/NugetPackageHelper.Cli/
├── Program.fs               # props-path, export-props
└── Commands/
    ├── PropsPath.fs
    ├── ExportProps.fs
    ├── Refresh.fs           # copy PropsPath onto the rebuilt graph before save
    ├── Sync.fs              # same, onto the live graph that gets saved
    └── Propose.fs           # same, beside the existing CompareBranch copy

tests/NugetPackageHelper.Core.Tests/
├── GraphPersistenceTests.fs # missing, round-trip, clear, survive a later save
└── PropsExportTests.fs

docs/user-guide.md           # the two commands, after they exist
```

**Structure Decision**: Core owns the snapshot field and the props text. The CLI owns the two commands and the disk checks that need a real folder. Scanner’s `buildGraph` stays a scan result with no remembered path; `refresh`, `sync`, and `propose` copy `PropsPath` from the snapshot they loaded before they save a rebuilt graph. `update` already saves `{ graph with Packages = ... }`, so the new field survives there without a new line.

## Complexity Tracking

No constitution violations. This section is intentionally empty.

## Phase 0 — Research

Recorded in [research.md](research.md). No `NEEDS CLARIFICATION` remains.

- `propsPath` is an optional root property of `.dotgraph.json`. The planning input keeps the path on that settings file.
- The stored string is trimmed and not rewritten to an absolute path. Export resolves a relative path from the directory that contains `.dotgraph.json`.
- The props file is updated by splicing one `ItemGroup Label="Dotgraph"`. Characters outside that group stay as they were. A second identical write does not touch the file.
- `ProjectScanner.writeVersion` is the wrong writer. It updates a version property inside a project file.
- A rebuilt graph must copy `PropsPath` before save. `init` starts with no path.

## Phase 1 — Design

- [data-model.md](data-model.md) — `propsPath`, package-version entry, the `Dotgraph` item group.
- [contracts/props-file.md](contracts/props-file.md) — JSON property, path rules, and the props XML.
- [contracts/cli-props.md](contracts/cli-props.md) — `props-path` and `export-props`, exit codes.
- [quickstart.md](quickstart.md) — `dotnet test` plus the manual checks from the spec.

## Implementation sequence

Test-first, in this order:

1. Persistence tests: a missing `propsPath` loads as unset and is not inserted on an unrelated save; a relative path round-trips unchanged; clearing removes the property; a later save of package versions keeps the path. Then add `PropsPath` to `DependencyGraph` and `GraphPersistence`. Update every record literal that already sets `CompareBranch` so it also sets `PropsPath = None`.
2. Props-text tests: order ignoring letter case, release label kept, create a new file, replace only the labeled group, leave another group’s bytes unchanged, drop a package that left the list, empty list, identical second apply does not change the text, two labeled groups is an error, a package named outside the group is reported and still included. Then add `PropsExport.fs`.
3. CLI `props-path` prints, stores, and clears without writing a props file and without rescanning. `export-props` reads the snapshot only. It refuses a missing path, a missing parent folder, a directory, the settings file itself, and XML that is not a single `Project`. It does not call `buildGraph`.
4. `Refresh`, `Sync`, and `Propose` copy `PropsPath` from the loaded snapshot onto the rebuilt graph before `GraphPersistence.save`. `init` leaves the property unset.
5. Update `docs/user-guide.md` after the two commands exist.
6. Run the quickstart.

## Constitution Check (post-design)

Re-checked against the data model and both contracts. Gates I–V still pass. The props text stays in Core. The CLI still does not scan. `SemVer.toString` is the version text. `CascadeEngine` and `ProjectScanner.writeVersion` are unchanged. `export-props` is the only writer of the props file.
