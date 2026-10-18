# Research: Write Package Versions to a Props File

## 1. Where the path is stored

**Decision**: Optional root property `propsPath` on `.dotgraph.json`, mapped to `DependencyGraph.PropsPath: string option`. The planning input says the file path lives on the dotgraph settings JSON. There is no second settings file.

When the property is absent, loaders use `None` and do not rewrite the file just to add it. When the developer clears the path, the next save omits the property. It is not written as `null` or `""`. A saved value is the trimmed string the developer typed. A relative value stays relative in the JSON. An absolute value stays absolute.

**Rationale**: `.dotgraph.json` is already the settings file for this solution (`solutionPath`, `compareBranch`, `packages`). The spec asks for one remembered path. Keeping the typed string means a committed relative path still works on another machine. Absence is the off switch, which is different from `compareBranch`, where absence means `main`.

**Alternatives considered**: A separate JSON file for the path. Rejected because the planning input puts it on the existing settings file. An environment variable or a CLI flag on every export. Rejected because the path would not be remembered. Rewriting relative paths to absolute paths on save. Rejected because the snapshot is committed and an absolute path is machine-specific.

## 2. Which packages and which version

**Decision**: `export-props` reads `Packages` from the loaded snapshot and does not call `ProjectScanner.buildGraph`. Every map entry is written. Projects the scan excluded are already absent. The version text is `SemVer.toString`, so a release label stored in `PreRelease` is included and a missing label is not invented.

Order is ordinal case-insensitive by package name. Names that still tie are ordered by ordinal comparison, which matches `Map` key order.

**Rationale**: The spec says the saved list is the only source. Rescanning would copy unsaved project edits and would contradict that. `SemVer.toString` is already the snapshot’s version text.

**Alternatives considered**: Reading the live project files at export time. Rejected by the spec. Exporting only packages changed by the last bump. Rejected by the spec’s “every package in the saved list”.

## 3. How the props file is updated

**Decision**: Do not load the props file and save it back through `XDocument.Save`. That rewrites quotes, indentation, and the XML declaration, so other item groups would not stay byte-for-byte the same.

`PropsExport` works on the original text:

- Parse it to prove it is a single root element with local name `Project`, and to find `ItemGroup` elements whose `Label` attribute is exactly `Dotgraph`.
- Build one canonical group:

```xml
  <ItemGroup Label="Dotgraph">
    <PackageVersion Include="{name}" Version="{version}" />
  </ItemGroup>
```

- If that group is absent, insert the canonical group immediately before the root end tag. Copy every other character.
- If one such group is present, replace only that element’s outer text with the canonical group. Copy every other character.
- If the canonical text is already in place, return unchanged and do not write.
- If the text is not XML, the root is not an unprefixed `Project`, or more than one `Dotgraph` group exists, return an error and do not write.

Attribute values are XML-escaped. A new file uses the same group inside `<Project>` … `</Project>`, UTF-8, LF, no BOM. An existing file keeps its own bytes outside the group, including a BOM if one was present.

A package `Include` that appears on a `PackageVersion` outside the `Dotgraph` group is reported by name. The write still happens, and that other group is not edited.

**Rationale**: Spec FR-007 and the story 2 test require the rest of the file to stay unchanged. A splice does that. The canonical group makes the second write a no-op. Refusing a prefixed root avoids inserting an unprefixed group into a document where it would land in the wrong namespace. SDK props files use an unprefixed `Project`, with or without a default XML namespace; an unprefixed child then belongs to that default namespace, which is what MSBuild reads.

**Alternatives considered**: `ProjectScanner.writeVersion`. Rejected because it finds a property element (`PackageVersion`, `Version`, prefix/suffix) inside a project and saves the whole document. This feature writes `PackageVersion` items with `Include` and `Version` attributes. Rewriting the whole props file from a template. Rejected because it would drop other item groups. Merging by `Include` inside every item group. Rejected because the spec owns only the labeled group.

## 4. When the path is checked

**Decision**: `props-path` stores the trimmed string without checking that the folder exists, that the path is a file, or that it is not `.dotgraph.json`. `export-props` checks at write time and leaves the stored path unchanged when the check fails.

Resolution: if `Path.IsPathRooted` is true, use that path; otherwise combine it with the directory that contains `.dotgraph.json` (the same directory `GraphPersistence.load` already uses). Then reject, without creating anything, when the parent folder is missing, the path is an existing directory, or the full path is the settings file.

The write itself goes to a temporary file in that parent folder and then replaces the target, so a failed write does not truncate an existing props file. If the new text equals the current text, the file is not opened for write.

**Rationale**: `compare-branch` stores a name before it knows the branch exists. The spec uses the same split: saving the path does not write the props file, and a bad path at export time does not clear the setting.

**Alternatives considered**: Validating the folder when the path is saved. Rejected because a path may be saved before the folder is created, and the spec still wants that save to succeed. Creating missing parent folders. Rejected by the spec.

## 5. How a rescan keeps the setting

**Decision**: `ProjectScanner.buildGraph` sets `PropsPath` to `None`. It does not know the saved path. Before a rebuilt graph is saved over `.dotgraph.json`, the caller copies `PropsPath` from the snapshot it loaded.

Call sites that save a rebuilt graph today:

| Caller | What it saves | Required copy |
|---|---|---|
| `Refresh` | `buildGraph` result | Copy `PropsPath` from the loaded snapshot |
| `Sync` | `applyChanges` on the `buildGraph` result | Copy `PropsPath` onto that live graph before save |
| `Propose` | `buildGraph` result after a confirmed apply | Copy `PropsPath` next to the existing `CompareBranch` copy |
| `Update` | `{ graph with Packages = ... }` on the loaded snapshot | No new line; `with` keeps the field |
| `Init` | a new graph | Leave `PropsPath` as `None` |

`diff` and `analyze` do not save. `export-props` does not save.

**Rationale**: `buildGraph` hardcodes `CompareBranch = "main"` because a scan is not the settings file. Saving that record as-is would delete `propsPath`. The spec forbids existing versioning commands from writing the props file; it also requires the saved path to stay until the developer clears it. Copying one field at the three replace sites does that. `update` already updates the loaded record in place.

**Alternatives considered**: Teaching `buildGraph` to accept the previous settings. Rejected because most tests call it with only a solution path, and the scan still should not invent a path. A second file that rescan never touches. Rejected in section 1.
