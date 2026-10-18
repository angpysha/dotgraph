# Contract: Props commands

Two new commands. `init`, `refresh`, `diff`, `sync`, `update`, `propose`, `review`, and `compare-branch` do not write the props file. Their version behavior stays as it is. `refresh`, `sync`, and `propose` copy `propsPath` when they save a rebuilt snapshot, so the property survives. `init` still creates a snapshot with no `propsPath`.

Renderer stays Spectre.Console. Errors go through `Output.error`. Warnings go through `Output.warn`. Color is never the only signal.

## `dotgraph props-path`

No argument: print the stored path. When none is stored, print:

```text
No props path is saved.
```

Exit 0. Does not create `.dotgraph.json` and does not create or edit a props file.

`dotgraph props-path <path>`: store the trimmed path, then print that stored string. Exit 0. Does not check the folder. Does not rescan. Does not write the props file.

Whitespace-only path: print `Props path cannot be empty.`, leave `.dotgraph.json` unchanged, exit 1.

`dotgraph props-path --clear`: omit `propsPath` and print `No props path is saved.` Exit 0. Does not delete a props file. Clearing an already unset path prints the same line and leaves the file unchanged.

`--clear` together with a path: print that the path and `--clear` cannot be used together, change nothing, exit 1.

Missing `.dotgraph.json`: print `.dotgraph.json not found. Run 'dotgraph init' first.`, exit 1.

## `dotgraph export-props`

Loads the snapshot. Does not scan the solution and does not save the snapshot.

1. No `propsPath`: `No props path is saved.` Write nothing. Exit 1.
2. Parent folder missing, path is a directory, or path is `.dotgraph.json`: name the path and the reason. Write nothing. Leave `propsPath` stored. Exit 1.
3. Props file missing, and the parent folder exists: create it from the saved packages.
4. Props file present: splice the `Dotgraph` group as in [props-file.md](props-file.md).
5. Unreadable XML, a root that is not an unprefixed `Project`, or more than one `Dotgraph` group: explain, leave the file unchanged, exit 1.
6. A name that also appears outside the `Dotgraph` group: warn with that name, then continue.

Success text:

| Result | Printed line | Exit |
|---|---|---|
| File created or updated, one or more packages | `Wrote {count} package versions to {stored path}` | 0 |
| File already matched, one or more packages | `Props file already matches the saved list.` | 0 |
| Saved list empty | `No packages to write.` | 0 |

An empty list still creates or updates the group so that it has no entries, unless that empty group is already in place. The empty-list line is used in both cases. The file is not touched when it already matches.

A write uses a temporary file in the same folder, then replaces the target. A failure to write leaves the existing props file in place and exits 1.

## Exit codes

| Result | Code |
|---|---|
| Path printed, path stored, path cleared, props file written, props file already matching, or no packages to write | 0 |
| Missing snapshot, empty path, `--clear` combined with a path, no path at export, path cannot be used, props file unreadable or not a single `Project`, write failure | 1 |

## Sample export

Stored path `build/PackageVersions.props`. Saved list: `MyLib.Core` `1.2.0`, `MyLib.Abstractions` `1.0.0`, `MyLib.Http` `1.5.0-beta.1`.

```text
Wrote 3 package versions to build/PackageVersions.props
```

Group order inside the file: `MyLib.Abstractions`, `MyLib.Core`, `MyLib.Http`.
