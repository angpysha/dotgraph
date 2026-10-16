# Contract: Project version tags

Reader and writer: `NugetPackageHelper.Scanner.ProjectScanner`.

## Read

The first matching row wins. "Present" means the element exists and its trimmed text is non-empty.

| Order | Tags | Parsed version |
|---|---|---|
| 1 | `PackageVersion` | `SemVer.parse` of the element text |
| 2 | `Version` | `SemVer.parse` of the element text |
| 3 | `VersionPrefix`, optional `VersionSuffix` | Prefix text, plus `-` and the suffix text when the suffix is present |
| 4 | `PackagePrefix`, optional `PackageSuffix` | Same combination as row 3 |

If the winning text is not a version, the project has no version.

If no row matches, the scan warning is:

```text
  ⚠  {name}: no <PackageVersion>, <Version>, <VersionPrefix>, or <PackagePrefix> tag — excluded from graph
```

The project is not added to the graph. Other projects still load.

An empty `VersionSuffix` or `PackageSuffix` is not present.

## Write

Input: absolute project path and one `SemVer`.

| Winner at read time | Write |
|---|---|
| Row 1 or 2 | Set that element to `SemVer.toString`. Do not add a suffix element. |
| Row 3 | Set `VersionPrefix` to `MAJOR.MINOR.PATCH`. Set `VersionSuffix` to the label, clear it when the label is absent, or add `VersionSuffix` after the prefix when the label is new and the element is missing. |
| Row 4 | Same as row 3, using `PackagePrefix` and `PackageSuffix`. |

Elements that lost the read are byte-stable except for XML formatting the serializer already applies to the document. The writer does not create `PackageVersion`, `Version`, or `VersionPrefix` because a later row won.

## Errors

| Condition | Result |
|---|---|
| No winning element at write time | Error naming the path. No file save. |
| The file cannot be read or saved | Error naming the path and the IO reason. |

## Examples

| Project contains | Set version | Result |
|---|---|---|
| `PackagePrefix` 1.5.0, `PackageSuffix` beta.1 | `1.6.0-beta.2` | Prefix `1.6.0`, suffix `beta.2`. No `PackageVersion`, `Version`, or `VersionPrefix` added. |
| `PackagePrefix` 1.5.0, `PackageSuffix` beta.1 | `1.6.0` | Prefix `1.6.0`, suffix cleared. |
| `PackageVersion` 2.0.0 and `PackagePrefix` 1.0.0 | `2.1.0` | `PackageVersion` is `2.1.0`. `PackagePrefix` stays `1.0.0`. |
| `VersionPrefix` 1.0.0 and `PackagePrefix` 9.0.0 | `1.1.0-rc.1` | `VersionPrefix` `1.1.0`, `VersionSuffix` `rc.1`. `PackagePrefix` stays `9.0.0`. |
| `Version` `2.0.0-rc.1` only | `2.0.1-rc.1` | `Version` is `2.0.1-rc.1`. No suffix element added. |
