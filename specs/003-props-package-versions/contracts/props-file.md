# Contract: Props path and props file

The path is a property of `.dotgraph.json`. The props file is a separate XML document. Export reads the snapshot and writes only the props file.

## `.dotgraph.json`

Root property `propsPath`, string.

```json
{
  "solutionPath": "MyApp.slnx",
  "createdAt": "2026-10-17T12:00:00.0000000Z",
  "compareBranch": "main",
  "propsPath": "build/PackageVersions.props",
  "packages": {}
}
```

| JSON | Loaded value |
|---|---|
| Property absent | Unset |
| `""` or whitespace | Unset. The next save of that graph omits the property. |
| `"build/PackageVersions.props"` | That relative string |
| An absolute path | That absolute string |

Unknown properties stay ignored on read, as they are today. The writer still emits only known fields, so a save does not preserve a property this tool does not model.

Package objects are unchanged: `version`, `projectPath`, `dependencies`. Export does not add a field there.

## Resolution

Base directory: the directory that contains `.dotgraph.json`.

| Stored value | Resolved path |
|---|---|
| Relative | Combined with the base directory |
| Rooted | The stored path itself |

Export then refuses, and does not create or delete anything, when:

- the parent directory does not exist
- the resolved path exists and is a directory
- the resolved full path is the `.dotgraph.json` file being read

## Props document

A new file:

```xml
<Project>
  <ItemGroup Label="Dotgraph">
    <PackageVersion Include="MyLib.Abstractions" Version="1.0.0" />
    <PackageVersion Include="MyLib.Core" Version="1.2.0-beta.1" />
  </ItemGroup>
</Project>
```

UTF-8, LF, no byte-order mark, one entry per line, two-space indent as shown. `Include` is the package name. `Version` is the snapshot version, including a release label when `SemVer.toString` includes one.

An existing file keeps every byte outside the one `ItemGroup` with `Label="Dotgraph"`. That group is replaced by the canonical block above, without the wrapping `Project` lines. Insertion, when the group is missing, is immediately before the end tag of the unprefixed root `Project`.

The group matches the saved list exactly:

- a package in the list is present once
- a package that left the list is absent from this group
- a version change updates `Version`
- names are ordered A to Z, ignoring letter case
- an empty list leaves the group with no child elements

A second export of the same list against the same surrounding bytes does not change the file.

`PackageVersion` items in any other item group are not added, removed, or reordered. If one of those items has an `Include` equal to a name in the `Dotgraph` group, export reports that name and still writes its own group.

These are errors, and the props file is left unchanged:

- the file is not well-formed XML
- the root element is not an unprefixed `Project`
- more than one item group has `Label="Dotgraph"`

## What export does not change

- `.dotgraph.json`
- project files and their version tags
- parent folders that are not already there
- the props file, when the path is cleared or when export is refused
