# Data Model: Branch Diff Version Bump

Entities match `specs/002-branch-diff-bump/spec.md`. Existing records live in `src/NugetPackageHelper.Core/Types.fs`. New names are marked.

## Compare branch

Stored on `DependencyGraph` as `CompareBranch: string` and in `.dotgraph.json` as root property `compareBranch`.

| Rule | Effect |
|---|---|
| Property missing | Value is `main`. The file is not rewritten just to insert it. |
| Developer saves a name | That string is stored as given, after trimming. Empty is rejected and the file is unchanged. |
| Name has no local branch | The stored string stays. `propose` and `review` stop before any version write. |
| Version save | `compareBranch` is written again with the versions. |

This is not a package version and not a dependency link.

## Changed path

A path returned by the scanner for one repository comparison. Not stored in the snapshot.

| Field | Meaning |
|---|---|
| Old path | Path in the compare-branch tree. Required for an existing file. |
| New path | Path in the current files. Empty when the file was deleted. |
| Kind | Modified, Deleted, Renamed, Copied, or TypeChanged. Added and untracked are not in this list. |

A path belongs to the package with the longest project-directory prefix. The package’s own project file belongs to that package. A path with no prefix belongs to no package.

## Selected package

A package in the live solution that the proposal will consider. Not a new stored record. It is one of:

| Kind | When | Base version |
|---|---|---|
| Code change | At least one changed path maps to it, and the set is not version-tag-only | Version parsed from the project blob on the compare branch |
| New | Its project file is absent from the compare-branch tree | None. Proposal is `1.0.0` |
| Skipped | On the branch, but the blob has no numeric version | None. Named and left unchanged |
| Removed | In the saved snapshot, absent from the live solution | None. Named and not versioned |

Version-tag-only: the only changed path is the project file, and both XML documents match after the six version tags are removed.

## Proposal

Uses the existing `VersionProposal` for dependents. A selected package adds the compare-branch version beside the live version when those two differ. The report shows both.

| Situation | Proposed version | Written? | Cascade root? |
|---|---|---|---|
| Code change, live version differs from branch+patch | `applyBump Patch` of the branch version | Yes, after confirm | Yes, pair is `(branch version, proposed version)` |
| Code change, live version already equals that patch | That same version | No | Yes |
| Developer leaves it unchanged and live version equals the branch version | None | No | No |
| Developer accepts or types a version different from live | The accepted or typed version | Yes, after confirm | Yes, unless the chosen version is an unconfirmed earlier release |
| New package | `1.0.0`, or the typed replacement | Only if confirmed and different from live | Yes, when it will be written or is already at the chosen version |
| Pure dependent | `computeProposals` from live `node.Version` | Only if confirmed and different from live | The engine records it for further dependents |

An earlier release is `isDowngrade` of the live version toward the chosen version. It is a warning, not a `BumpType`. It is not a cascade root until the developer confirms it.

When a selected package depends on another selected package that was given a version, its offer is the higher of:

- the patch of its compare-branch version, and
- the follow-up bump applied to that same compare-branch version.

Pure dependents are not in the selected set. Their base stays the live version. Their release label stays unless the developer types a different version.

## Review decision

| Choice | Focus in `review` | Effect |
|---|---|---|
| Leave unchanged | First | No write for this package. No cascade from it when live version equals the branch version. Cascade still runs when live version already equals the proposal. |
| Accept proposed | | Chosen version becomes the proposal above. |
| Enter a version | | `MAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH-label`. Invalid input asks again. Equal to live counts as Leave unchanged. |

Order: selected packages so that a package is shown after selected packages it lists as dependencies; then pure dependents. Later rows are rebuilt from decisions already made. Cycles do not repeat a package; a package already shown keeps its decision.

`update` and `sync` keep the existing decision order and still focus Accept proposed. They do not use this table’s focus.

## Saved snapshot

The existing package map plus `compareBranch`. After a confirmed write of at least one version, the snapshot is rebuilt from the solution so versions and dependency links match the files just written. When nothing is written, the snapshot bytes that hold versions stay as they were. Saving a compare branch does not rescan versions.

## Relationships

```text
compare branch
    └── tree blob ── version ── selected package ── proposal
current files
    └── live version ── pure dependent ── follow-up proposal
saved snapshot
    ├── compareBranch
    └── packages (versions + links), replaced only after a confirmed version write
```
