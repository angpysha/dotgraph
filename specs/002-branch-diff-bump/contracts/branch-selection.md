# Contract: Branch selection and proposal

Library behavior behind `dotgraph propose` and `dotgraph review`. Command text is in [cli-branch.md](cli-branch.md).

Git access is LibGit2Sharp inside the scanner. Tests of this contract in Core pass paths, XML strings, and versions in memory. Scanner tests cover the repository read against a temporary repository.

## Repository read

Given a solution directory and a branch name:

1. Open the repository that contains that directory. If there is none, stop. Write nothing.
2. Resolve a local branch with that exact name. If there is none, stop. Write nothing. Do not fetch and do not substitute `origin/<name>`.
3. Diff that branch’s tip tree against the index and the working directory.
4. Return only changes whose previous path exists in that tree. Do not return untracked files. Do not return files that exist only as additions.
5. Read a project file’s text from that same tip by its path relative to the repository root. Absence means the project is not on the branch.

## Path mapping

| Input | Result |
|---|---|
| File under a package directory, or the project file itself | That package. Longest directory prefix wins. |
| File under no package directory | No package. |
| Only change is the project file, and XML matches after removing `PackageVersion`, `Version`, `VersionPrefix`, `VersionSuffix`, `PackagePrefix`, and `PackageSuffix` | Package is not selected. |
| Project file missing on the branch, present in the live solution | New package. |
| Package in the snapshot, missing from the live solution | Removed. Named. No version. |
| Project not in the snapshot’s package map | Named. No version. |

## Versions

Tag order for a blob and for a current file is the existing order: `PackageVersion`, then `Version`, then `VersionPrefix` with optional `VersionSuffix`, then `PackagePrefix` with optional `PackageSuffix`.

| Case | Proposal | Write target |
|---|---|---|
| Blob parses, live version differs | One patch above the blob, same release label | The tag that already holds the version in the current file |
| Blob parses, live version already equals that patch | That patch, nothing to write on this package | None |
| Blob does not parse | Skip this package, name it, continue | None |
| New package | `1.0.0` | The current file’s winning tag, or the blob’s winning tag when the current file has none |
| Pure dependent | Follow-up from the live version via the existing cascade | The current file’s winning tag |

Examples:

| Branch | Live | Selected because | Proposal |
|---|---|---|---|
| `1.4.2` | `9.0.0` | a known source file changed | `1.4.3`, and `9.0.0` is an earlier-release warning if written |
| `2.0.0-beta.1` | `2.0.0-beta.1` | a known source file changed | `2.0.1-beta.1` |
| `1.4.2` | `1.4.3` | a known source file changed | already `1.4.3`; dependents still get a patch follow-up |
| `1.4.2` | `1.5.0` | only `Version` changed | not selected |
| (no project file) | `0.1.0` | project is new | `1.0.0` |

A follow-up keeps the dependent’s own release label. Two triggers: the larger change size wins. A selected package omitted because the developer left it unchanged at the branch version contributes no trigger. A selected package already at the proposal contributes a patch trigger.

The chosen version for a selected package that also depends on another chosen package is the higher of “patch of the branch version” and “the follow-up size applied to the branch version”.

## Cascade inputs

Roots passed to the existing cascade are pairs of compare-branch version → chosen version, for packages that actually count as a bump. The graph versions used for dependents are the live versions. The cascade does not invent a release label and does not read the branch for a pure dependent.
