# Data Model: Package Prefix and Suffix Updates

Entities match `specs/001-prefix-suffix-console/spec.md`. Field names below are the existing F# records in `src/NugetPackageHelper.Core/Types.fs` unless noted.

## Version (`SemVer`)

| Field | Meaning | Rules |
|---|---|---|
| `Major`, `Minor`, `Patch` | Numeric prefix | Integers ≥ 0. Displayed as `MAJOR.MINOR.PATCH`. |
| `PreRelease` | Release suffix | `None` or empty means no suffix. Displayed as `none` when absent. Stored in JSON as the full `toString` value (`1.2.0` or `1.2.0-beta.1`). |

**Identity**: Two versions are the same only when the triple and the suffix match.

**Ordering**: Higher major, then minor, then patch. Same triple: a version with a suffix is earlier than the stable version; suffix identifiers use dotted pre-release order (`beta.2` before `beta.10`; `beta.2` before `rc.1` only when the identifier rules say so).

**Transitions**:

- Explicit set: replace both the triple and the suffix with the supplied version.
- Follow-up bump: `Major` resets minor and patch and adds one major; `Minor` resets patch and adds one minor; `Patch` adds one patch. `PreRelease` is copied unchanged.
- `Suffix` and an earlier release do not produce a follow-up bump.

## Change size (`BumpType`)

| Case | When | Console word | Color |
|---|---|---|---|
| `Major` | Numeric major increases | MAJOR | red |
| `Minor` | Numeric minor increases, major unchanged | MINOR | yellow |
| `Patch` | Numeric patch increases, major and minor unchanged | PATCH | green |
| `Suffix` | Triple unchanged, suffix different, not an earlier release | SUFFIX | grey |

An earlier release is not a `BumpType`. Callers use `isDowngrade` and the word Warning.

`cascadeBump` is unchanged for the three numeric cases (`Major` → `Minor`, `Minor` or `Patch` → `Patch`). `Suffix` is never cascaded.

## Package (`PackageNode`)

| Field | Meaning |
|---|---|
| `Name` | Package id, then assembly name, then project file name |
| `Version` | Version read from the winning tag |
| `ProjectPath` | Absolute project path |
| `Dependencies` | Names of in-solution project references |

**Winning tag** (first non-empty numeric version):

1. `PackageVersion` — single value, suffix stays inside that value
2. `Version` — single value, same rule
3. `VersionPrefix` plus optional `VersionSuffix`
4. `PackagePrefix` plus optional `PackageSuffix`

A project with only a suffix tag has no version, is listed in the scan warning, and is absent from `Packages`.

## Version storage (project file)

Not a new record. The write target is the winner from the read:

| Winner | Prefix written | Suffix written | Tags left alone |
|---|---|---|---|
| `PackageVersion` or `Version` | Full `toString` in that element | Inside the same element. No suffix element is created. | Every later tag |
| `VersionPrefix` / `VersionSuffix` | `MAJOR.MINOR.PATCH` on `VersionPrefix` | Label on `VersionSuffix`, or the element cleared when the suffix is absent. Element added beside the prefix when a suffix is new. | `PackagePrefix`, `PackageSuffix` |
| `PackagePrefix` / `PackageSuffix` | `MAJOR.MINOR.PATCH` on `PackagePrefix` | Label on `PackageSuffix`, same add/clear rules | None later |

## Proposal (`VersionProposal`)

| Field | Meaning |
|---|---|
| `PackageName` | Dependent package |
| `CurrentVersion` | Live version |
| `ProposedVersion` | `applyBump` of the cascade size, suffix preserved |
| `BumpType` | `Minor` or `Patch` only (cascade result) |
| `Reason` | Dependencies that triggered it and the largest trigger size |

## Review decision

Held in the console session, not persisted.

| Decision | Result |
|---|---|
| Accept | `ProposedVersion` |
| Enter a version | Parsed `MAJOR.MINOR.PATCH` with optional `-suffix`. Invalid text is rejected and the same package is asked again. Same as current version counts as Leave unchanged. Earlier than current asks for confirmation unless `--force`. |
| Leave unchanged | Omitted from the write set |

The summary has two groups: versions that will change (explicit roots that differ, plus Accept and typed decisions) and versions left unchanged (skipped proposals and unchanged roots). The write set is empty when the first group is empty.

## Snapshot (`DependencyGraph`)

| Field | Meaning |
|---|---|
| `SolutionPath` | Solution file |
| `CreatedAt` | UTC time of the last save |
| `Packages` | Map keyed by package name |

`GraphPersistence` already writes `version` as `SemVer.toString`. After a confirmed apply, each saved version equals the version just written, including the suffix. No JSON shape change.

## Diff (`SnapshotDiff`)

| Field | Meaning |
|---|---|
| `Changed` | Live version differs from the snapshot, including suffix-only |
| `CascadeGaps` | Dependents still on the snapshot version whose trigger is a numeric bump |
| `AlreadyCovered` | Dependents already moved off the snapshot version |

`PackageChange.BumpType` may be `Suffix`. Those rows do not create cascade gaps.
