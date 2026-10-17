# dotgraph — User Guide

## Prerequisites

- .NET 8.0 SDK or later
- A .NET solution using SDK-style `.csproj` files with `<ProjectReference>` links
- Each published project must expose a version using one of these tag patterns (first match wins):
  - `<PackageVersion>` or `<Version>` (full semver string, optional `-suffix` in the value)
  - `<VersionPrefix>` with optional `<VersionSuffix>`
  - `<PackagePrefix>` with optional `<PackageSuffix>`

When you set a version, dotgraph writes back only to the tag (or prefix/suffix pair) that was read for that project. It does not add a different tag family.

---

## Console review

`update` and `sync` show every change with **prefix**, **suffix**, a **change word**, and a **reason**. An absent pre-release suffix is printed as the word `none`.

Change words are colored in the terminal (Spectre.Console). The word itself carries the meaning when color is stripped (`NO_COLOR`, redirected stdout, or a terminal without ANSI):

| Word | Color | Meaning |
|------|-------|---------|
| MAJOR | red | Major numeric bump |
| MINOR | yellow | Minor numeric bump |
| PATCH | green | Patch numeric bump |
| SUFFIX | grey | Suffix-only change (numeric prefix unchanged) |
| Error | red | Failure |
| Warning | yellow | Earlier release or other warning |

Example line (colors omitted in this doc):

```text
  MyLib.Core  prefix 1.2.0 → 2.0.0  suffix none → none  MAJOR  depends on MyLib.Abstractions (MAJOR)
```

Non-interactive `update` prints a table with columns **Package**, **Current prefix**, **Current suffix**, **Proposed prefix**, **Proposed suffix**, **Change**, and **Reason**. `diff` and cascade previews use the same prefix/suffix layout on each row.

---

## Installation

```bash
dotnet tool install --global dotgraph
```

Verify the installation:

```bash
dotgraph --version
```

---

## Example Solution

This guide uses the following example solution throughout:

```
MyApp.slnx
src/
  MyLib.Abstractions/    v1.0.0   (no dependencies)
  MyLib.Core/            v1.2.0   → depends on Abstractions
  MyLib.Http/            v1.5.0   → depends on Core
  MyLib.Caching/         v1.1.0   → depends on Core
  MyLib.Api/             v2.0.0   → depends on Http, Caching
```

Dependency graph:

```
MyLib.Abstractions
    └── MyLib.Core
            ├── MyLib.Http
            │       └── MyLib.Api
            └── MyLib.Caching
                    └── MyLib.Api
```

---

## Step 1 — Build the Initial Graph

Navigate to your solution directory and run:

```bash
cd /path/to/your/solution
dotgraph init
```

Output:

```
Scanning solution: MyApp.slnx
  ✓ MyLib.Abstractions  v1.0.0  (0 internal deps)
  ✓ MyLib.Core          v1.2.0  (1 internal deps)
  ✓ MyLib.Http          v1.5.0  (1 internal deps)
  ✓ MyLib.Caching       v1.1.0  (1 internal deps)
  ✓ MyLib.Api           v2.0.0  (2 internal deps)

Graph saved to .dotgraph.json (5 packages, 5 edges)
```

This creates `.dotgraph.json` in your solution root. **Commit this file** to source control.

If a project has no readable version tag (`PackageVersion`, `Version`, `VersionPrefix`, or `PackagePrefix`), it is listed as a warning and excluded from the graph.

---

## Step 2 — Analyze Impact Before Changing Anything

Before bumping a version, see what would be affected:

```bash
dotgraph analyze MyLib.Core
```

Output:

```
Packages affected by a version change to MyLib.Core:

  MyLib.Http      v1.5.0   (depends directly on MyLib.Core)
  MyLib.Caching   v1.1.0   (depends directly on MyLib.Core)
  MyLib.Api       v2.0.0   (depends on MyLib.Http, MyLib.Caching)

3 packages would need version bumps.
```

You can analyze multiple packages at once:

```bash
dotgraph analyze MyLib.Core MyLib.Abstractions
```

---

## Step 3 — Detect Manually Changed Versions

Use this workflow when you have already edited `<Version>` tags in one or more `.csproj` files by hand (via IDE, text editor, or a script) and want dotgraph to figure out what cascade bumps are still missing.

### 3a — See what changed

```bash
dotgraph diff
```

dotgraph compares every live `.csproj` version against the `.dotgraph.json` snapshot and groups the findings into three sections:

```
Changed packages (vs snapshot):
  MyLib.Core      prefix 1.2.0 → 2.0.0  suffix none → none  MAJOR  changed vs snapshot
  MyLib.Caching   prefix 1.1.0 → 1.2.0  suffix none → none  MINOR  changed vs snapshot

Cascade gaps (need version bumps):
  MyLib.Http      prefix 1.5.0 → 1.6.0  suffix none → none  MINOR  depends on MyLib.Core (MAJOR)
  MyLib.Api       prefix 2.0.0 → 2.1.0  suffix none → none  MINOR  depends on MyLib.Http

Already covered (no action needed):
  MyLib.Caching   prefix 1.1.0 → 1.2.0  suffix none → none  MINOR  depends on MyLib.Core

Run 'dotgraph sync' to apply the proposed cascade bumps.
```

A suffix-only edit (numeric prefix unchanged) shows **SUFFIX** instead of MAJOR/MINOR/PATCH, for example:

```text
  MyLib.Http  prefix 1.5.0 → 1.5.0  suffix beta → rc.1  SUFFIX  changed vs snapshot
```

**Changed packages** — versions you bumped manually since the last snapshot.  
**Cascade gaps** — dependents that still need a bump so they can be re-published correctly.  
**Already covered** — dependents you also bumped manually; dotgraph recognises these and skips them.

### 3b — Apply the missing bumps

```bash
dotgraph sync
```

```
  MyLib.Http  prefix 1.5.0 → 1.6.0  suffix none → none  MINOR  depends on MyLib.Core (MAJOR)
  MyLib.Api   prefix 2.0.0 → 2.1.0  suffix none → none  MINOR  depends on MyLib.Http

Apply 2 cascade version change(s)? [Y/n]:
```

Press `Y`. dotgraph writes only the **cascade** follow-ups into each `.csproj` (your manual root edits are already on disk) and updates `.dotgraph.json`.

### Options

```bash
dotgraph sync --dry-run        # print the diff preview only, write nothing
dotgraph sync --interactive    # review each cascade proposal one by one
```

With `--interactive`, dotgraph lists root packages you already changed, then one screen per follow-up (`Package N of M`) with **Accept proposed**, **Enter a version**, or **Leave unchanged**. Typed versions must be `MAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH-suffix`. A summary groups **Will change** and **Left unchanged**, then asks **Apply these version changes?** — same flow as `update --interactive` (see below). If nothing would be written, you see `Nothing will be written.` with no prompt.

---

## Step 4 — Update Packages Explicitly

Use this when you want dotgraph to both set the version and cascade — without editing `.csproj` files by hand first.

### Single package

```bash
dotgraph update MyLib.Core 1.3.0
```

```
┌─────────────┬───────────────┬───────────────┬────────────────┬────────────────┬────────┬──────────────────────────────┐
│ Package     │ Current prefix│ Current suffix│ Proposed prefix│ Proposed suffix│ Change │ Reason                       │
├─────────────┼───────────────┼───────────────┼────────────────┼────────────────┼────────┼──────────────────────────────┤
│ MyLib.Core  │ 1.2.0         │ none          │ 1.3.0          │ none           │ MINOR  │ (explicit)                   │
│ MyLib.Http  │ 1.5.0         │ none          │ 1.5.1          │ none           │ PATCH  │ depends on MyLib.Core (MINOR)│
│ MyLib.Caching│ 1.1.0        │ none          │ 1.1.1          │ none           │ PATCH  │ depends on MyLib.Core (MINOR)│
│ MyLib.Api   │ 2.0.0         │ none          │ 2.0.1          │ none           │ PATCH  │ depends on MyLib.Http, ...   │
└─────────────┴───────────────┴───────────────┴────────────────┴────────────────┴────────┴──────────────────────────────┘

Apply all 4 version change(s)? [Y/n]:
```

Press `Y`. dotgraph writes the new prefix and suffix (or full version string) into each project's winning tag and updates `.dotgraph.json`.

### Multiple packages at once

Pass several `<package> <version>` pairs. Affected sets are merged — shared dependents appear only once, receiving the largest applicable bump from all their changed ancestors:

```bash
dotgraph update MyLib.Core 2.0.0 MyLib.Abstractions 1.1.0
```

The proposal table lists both explicit roots and cascade follow-ups with prefix, suffix, change word, and reason — same columns as the single-package example. Shared dependents appear once with the largest applicable bump.

```
Apply all 5 version change(s)? [Y/n]:
```

`MyLib.Api` is listed once. Its trigger is MAJOR (from `MyLib.Core`), which outranks the MINOR from `MyLib.Abstractions`.

### Dry run

```bash
dotgraph update MyLib.Core 2.0.0 --dry-run
dotgraph update MyLib.Core 2.0.0 MyLib.Abstractions 1.1.0 --dry-run
```

Prints the proposal table without writing any files.

### Interactive mode

Use this when you want to review or override each follow-up individually:

```bash
dotgraph update MyLib.Core 2.0.0 --interactive
```

```
Root changes:
  MyLib.Core  prefix 1.2.0 → 2.0.0  suffix none → none  MAJOR

─────────────────────────────────────────────────

Package 1 of 3
Current prefix: 1.5.0
Current suffix: none
Proposed prefix: 1.6.0
Proposed suffix: none
MINOR
depends on MyLib.Core (MAJOR)

Choose:
> Accept proposed
  Enter a version
  Leave unchanged
```

- **Accept proposed** — take the cascade suggestion.
- **Enter a version** — type `1.2.3` or `1.2.3-beta.1`; invalid input shows `Invalid version. Example: 1.2.3 or 1.2.3-beta.1` and asks again on the same package. Typing the current version counts as **Leave unchanged**.
- **Leave unchanged** — skip this follow-up.

An earlier typed version prints **Warning** with both versions and asks **Apply this earlier version?** unless you passed `--force` on `update`.

After all packages, a summary runs before any write:

```
Will change
  MyLib.Core      prefix 1.2.0 → 2.0.0  suffix none → none  MAJOR  (explicit)
  MyLib.Http      prefix 1.5.0 → 1.6.0  suffix none → none  MINOR  (accepted)
  MyLib.Caching   prefix 1.1.0 → 1.2.0  suffix none → none  MINOR  (typed)

Left unchanged
  MyLib.Api       prefix 2.0.0  suffix none

Apply these version changes? [Y/n]:
```

Answering **no** prints `Nothing was written.` Project files and `.dotgraph.json` stay unchanged. If every choice leaves versions as-is, you see `Nothing will be written.` with no confirmation prompt.

Non-interactive downgrades without `--force` print **Warning**, exit code `1`, and write nothing.

---

## Step 5 — Keeping the Graph Up to Date

After adding new projects or changing `<ProjectReference>` links in your solution, refresh the graph:

```bash
dotgraph refresh
```

This rescans all `.csproj` files and updates `.dotgraph.json` without changing any version numbers.

---

## Workflow Integration

### Typical release workflow — explicit

```
1. dotgraph analyze <package>           # Check impact before touching anything
2. Edit the package (fix bug / add feature)
3. dotgraph update <package> <version>  # dotgraph sets the version and cascades
4. Review and apply
5. Build + test the solution
6. Publish all affected packages to NuGet feed
7. git commit -- .dotgraph.json src/   # Commit all version bumps together
```

### Typical release workflow — manual edits first

```
1. Edit one or more <Version> tags in .csproj files (via IDE or directly)
2. dotgraph diff                        # See what changed and what's missing
3. dotgraph sync                        # Apply cascade bumps for gaps
4. Review and apply
5. Build + test the solution
6. Publish all affected packages to NuGet feed
7. git commit -- .dotgraph.json src/   # Commit all version bumps together
```

### Multiple simultaneous changes

**Already edited `.csproj` files by hand?** Run `dotgraph diff` then `dotgraph sync` — dotgraph detects all changed packages automatically and merges their cascade in one pass (see Step 3).

**Want dotgraph to do the edits?** Pass all packages in one `update` call:

```bash
dotgraph update MyLib.Abstractions 1.1.0 MyLib.Core 2.0.0
```

Either approach merges the affected sets correctly so each dependent is bumped exactly once with the right version.

---

## Step 6 — Propose versions from a branch diff

dotgraph can compare your current files with a saved branch and propose one patch above the version stored on that branch. The `git` executable is not required. The tool reads the repository itself.

The saved name lives in `.dotgraph.json` as `compareBranch`. If that property has never been stored, the name is `main`.

```bash
dotgraph compare-branch          # print the saved name (main when it was never stored)
dotgraph compare-branch release/1.4
```

Setting a name does not check that the branch exists and does not rescan packages. An empty name is rejected and the file is left unchanged. A missing snapshot still tells you to run `dotgraph init` first.

Preview the proposal without writing:

```bash
dotgraph propose --dry-run
```

Selected packages show the compare-branch version, the current version when it differs, the proposed version, a change word (MAJOR, MINOR, PATCH, or SUFFIX), and a reason (`code changed` or `new package`). A package already at the proposal is marked already current. Follow-ups are the usual cascade from each dependent's live version. Removed packages and packages with no numeric version on the branch are warnings.

```text
Compare branch: main

Selected:
  MyLib.Core     branch 1.4.2   current 9.0.0   → 1.4.3   PATCH   code changed

Follow-ups:
  MyLib.Http     3.0.0 → 3.0.1   PATCH   depends on MyLib.Core (PATCH bump)
```

`dotgraph propose` prints that report, then asks before it writes. An earlier release (the proposed version is below the live version) asks once per package unless you pass `--force`. Answering no drops only that package. If nothing remains, you see `Nothing will be written.` and no files change. Otherwise one yes/no applies the remaining set. After a yes, project files are updated and `.dotgraph.json` is rescanned so versions and dependency links match the solution. The saved branch name is kept.

`dotgraph review` walks only that selected set and its follow-ups. It is separate from `update --interactive` and `sync --interactive`. Those reviews are unchanged and still focus **Accept proposed** first. In `review`, **Leave unchanged** is focused first, then **Accept proposed**, then **Enter a version**. A package is shown only after selected dependencies that are also in the review. Later proposals are recalculated after you accept or type a version. Leaving a package unchanged while it is still at the branch version does not bump its dependents. A package already at the proposed patch still feeds that patch and is not written again.

The summary groups **Will change** and **Left unchanged**. Nothing is written unless **Will change** is non-empty and you confirm. Quitting, declining, or leaving every package unchanged prints `Nothing will be written.`

```bash
dotgraph review
dotgraph review --force
```

---

## Flags Reference

| Flag | Commands | Description |
|---|---|---|
| `--dry-run` | `update`, `sync`, `propose` | Print proposals only, write nothing |
| `--interactive` | `update`, `sync` | Walk through each proposal interactively |
| `--force` | `update`, `propose`, `review` | Accept an earlier release without the extra question |
| `--solution <path>` | `init`, `refresh` | Specify solution file when multiple `.sln`/`.slnx` exist |

---

## Common Errors

### `Graph file not found`

```
Error: .dotgraph.json not found.
Run 'dotgraph init' first to build the dependency graph.
```

**Fix**: Run `dotgraph init` in the solution root directory.

---

### `Unknown package: MyLib.Foo`

```
Error: 'MyLib.Foo' is not in the graph.
Did you mean: MyLib.Core, MyLib.Http?
```

**Fix**: Check the package name (it must match the `<PackageId>`, `<AssemblyName>`, or project file name). Run `dotgraph refresh` if you recently renamed a project.

---

### `Circular dependency detected`

```
Error: Circular dependency detected:
  MyLib.Core → MyLib.Http → MyLib.Core
```

**Fix**: Remove the circular `<ProjectReference>` in your `.csproj` files. A package cannot (directly or transitively) depend on itself.

---

### `Version downgrade`

```
Warning: MyLib.Core: 1.2.0 → 1.1.0 is a downgrade. Use --force to apply.
```

**Fix**: Use `--force` if intentional. Otherwise verify you typed the correct version.

---

## Tips

- **Commit `.dotgraph.json`** — `git diff .dotgraph.json` gives a clean view of what changed in each release.
- **Use `--dry-run` in CI** — run `dotgraph analyze` in your build pipeline to detect if any package was bumped without bumping its dependents.
- **Use `--interactive` for major bumps** — when making breaking changes, interactive mode lets you give each dependent a more meaningful version than the automatic proposal.
- **Scripts and CI** — set `NO_COLOR=1` or redirect stdout; MAJOR, MINOR, PATCH, and SUFFIX words remain readable without ANSI color.
