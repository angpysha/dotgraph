# Quickstart: Write Package Versions to a Props File

Proves [spec.md](spec.md) against [props-file.md](contracts/props-file.md) and [cli-props.md](contracts/cli-props.md). Export reads `.dotgraph.json` only. It does not scan project files.

## Prerequisites

- .NET 10 SDK
- Repository root as the working directory
- For the manual checks: a solution that already has `.dotgraph.json` with at least two packages, and a folder where a props file may be written

## Automated

```bash
dotnet test --configuration Release
```

Expected: persistence tests load a missing `propsPath` as unset, round-trip a relative path unchanged, omit the property when cleared, and keep it across a later save of package versions. Props-text tests cover case-insensitive order, a release label, a new file, a splice that leaves another item group’s bytes unchanged, removal of a package that left the list, an empty group, an identical second apply, a duplicate `Dotgraph` group refused, and a same-named package outside the group reported but still written.

## Manual checks

Use a copy of a solution. Do not point `propsPath` at a props file you cannot restore.

| # | Do | Expect |
|---|---|---|
| 1 | `dotgraph props-path` before any path is stored | `No props path is saved.` No props file created. `.dotgraph.json` package versions unchanged. |
| 2 | `dotgraph props-path build/PackageVersions.props` | Prints that relative path. The JSON contains `"propsPath": "build/PackageVersions.props"`. The props file does not exist yet. |
| 3 | `dotgraph export-props` with the parent folder missing | Names the missing folder, exit 1. `propsPath` still stored. No folder created. |
| 4 | Create the parent folder. `dotgraph export-props` | One `ItemGroup Label="Dotgraph"` with every saved package, versions matching `.dotgraph.json`, release labels kept, names A to Z. Project files unchanged. |
| 5 | Run `dotgraph export-props` again | `Props file already matches the saved list.` File bytes unchanged. |
| 6 | Add another item group to the props file by hand. Change one saved version, add one package, and remove one package in `.dotgraph.json` only. Export again. | The `Dotgraph` group matches the new list. The other item group is unchanged. |
| 7 | `dotgraph props-path --clear`, then `dotgraph export-props` | Clear does not delete the props file. Export prints `No props path is saved.` and does not change it. |
| 8 | `dotgraph refresh` after storing the path again | `.dotgraph.json` still has the same `propsPath`. Refresh does not write the props file. |
