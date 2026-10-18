# Data Model: Write Package Versions to a Props File

Entities match `specs/003-props-package-versions/spec.md`. Existing records live in `src/NugetPackageHelper.Core/Types.fs`. New names are marked.

## Props path

New. Stored on `DependencyGraph` as `PropsPath: string option` and in `.dotgraph.json` as root property `propsPath`.

| Rule | Effect |
|---|---|
| Property missing | `None`. The file is not rewritten just to insert it. |
| Developer saves a path | Trimmed string stored as typed. Relative stays relative. Empty is rejected and the file is unchanged. |
| Developer clears it | Property omitted on the next save. The props file on disk is left in place. |
| Export | A relative value is resolved from the directory that contains `.dotgraph.json`. An absolute value is used as stored. |
| Rescan that saves a new graph | The loaded `PropsPath` is copied onto the graph being saved. `init` starts as `None`. |

This is not a package version and not a dependency link. It is not `compareBranch`.

## Saved package

The existing `PackageNode` inside `DependencyGraph.Packages`. Export uses `Name` and `Version` only. `ProjectPath` and `Dependencies` are not written to the props file.

A project with no version tag never becomes a node, so it cannot appear in the props group.

## Package-version entry

Not stored in `.dotgraph.json`. It is one line inside the props file, derived at export time.

| Field | Source |
|---|---|
| Package name | `PackageNode.Name`, XML-escaped, placed in `Include` |
| Version | `SemVer.toString` of `PackageNode.Version`, XML-escaped, placed in `Version` |

One entry per package name. Order is ordinal case-insensitive, then ordinal.

## Dotgraph item group

The single `ItemGroup` whose `Label` is `Dotgraph` in the props file. After a successful export, its children are exactly the package-version entries and nothing else. Comments that were inside that group are not kept.

| Situation | Group afterwards | Rest of the file |
|---|---|---|
| Props file does not exist | New file containing only this group | Not applicable |
| Group absent | Group inserted before the `Project` end tag | Unchanged bytes |
| One group present | That element replaced with the canonical group | Unchanged bytes |
| Canonical group already matches | No write | Unchanged bytes |
| Zero packages | Group present with no children | Unchanged bytes |
| More than one `Dotgraph` group, or the file is not one unprefixed `Project` | No write | Unchanged bytes |

A `PackageVersion` with the same `Include` in some other item group is not part of this entity. Export names it and leaves it.

## Settings snapshot

The existing `.dotgraph.json` document. Export does not change `solutionPath`, `createdAt`, `compareBranch`, or `packages`. `props-path` changes only `propsPath`.

## State of the path

```text
unset --save--> saved --replace--> saved
  ^                |
  |               clear
  +----------------+
```

Export is allowed only in `saved`. It does not change this state, including when the props file cannot be written.
