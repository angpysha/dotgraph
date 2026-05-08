# dotgraph — User Guide

## Prerequisites

- .NET 8.0 SDK or later
- A .NET solution using SDK-style `.csproj` files with `<ProjectReference>` links
- Each published project must have a `<Version>` tag in its `.csproj`

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

If any projects are missing a `<Version>` tag, they are listed as warnings and excluded from the graph.

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
  MyLib.Core      1.2.0 → 2.0.0   [MAJOR]   ← you edited this
  MyLib.Caching   1.1.0 → 1.2.0   [MINOR]   ← you edited this too

Cascade gaps (need version bumps):
  MyLib.Http      1.5.0 → propose 1.6.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Api       2.0.0 → propose 2.1.0   [MINOR]  depends on MyLib.Http

Already covered (manually bumped, no action needed):
  MyLib.Caching   1.1.0 → 1.2.0   [MINOR]  depends on MyLib.Core ✓

Run 'dotgraph sync' to apply the proposed cascade bumps.
```

**Changed packages** — versions you bumped manually since the last snapshot.  
**Cascade gaps** — dependents that still need a bump so they can be re-published correctly.  
**Already covered** — dependents you also bumped manually; dotgraph recognises these and skips them.

### 3b — Apply the missing bumps

```bash
dotgraph sync
```

```
  MyLib.Http    1.5.0 → 1.6.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Api     2.0.0 → 2.1.0   [MINOR]  depends on MyLib.Http

Apply 2 version changes? [Y/n]:
```

Press `Y`. dotgraph writes the proposed versions into each `.csproj` and updates `.dotgraph.json`.

### Options

```bash
dotgraph sync --dry-run        # print proposals only, write nothing
dotgraph sync --interactive    # review and override each proposal one by one
```

Interactive mode for `sync` works identically to `update --interactive` — you see each affected package with Accept / Enter manually / Skip choices before the final confirmation.

---

## Step 4 — Update Packages Explicitly

Use this when you want dotgraph to both set the version and cascade — without editing `.csproj` files by hand first.

### Single package

```bash
dotgraph update MyLib.Core 1.3.0
```

```
  MyLib.Core      1.2.0 → 1.3.0   [MINOR]  (explicit)
  MyLib.Http      1.5.0 → 1.5.1   [PATCH]  depends on MyLib.Core (MINOR bump)
  MyLib.Caching   1.1.0 → 1.1.1   [PATCH]  depends on MyLib.Core (MINOR bump)
  MyLib.Api       2.0.0 → 2.0.1   [PATCH]  depends on MyLib.Http, MyLib.Caching

Apply all 4 version changes? [Y/n]:
```

Press `Y`. dotgraph writes `<Version>` into each `.csproj` and updates `.dotgraph.json`.

### Multiple packages at once

Pass several `<package> <version>` pairs. Affected sets are merged — shared dependents appear only once, receiving the largest applicable bump from all their changed ancestors:

```bash
dotgraph update MyLib.Core 2.0.0 MyLib.Abstractions 1.1.0
```

```
  MyLib.Abstractions  1.0.0 → 1.1.0   [MINOR]  (explicit)
  MyLib.Core          1.2.0 → 2.0.0   [MAJOR]  (explicit)
  MyLib.Http          1.5.0 → 1.6.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Caching       1.1.0 → 1.2.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Api           2.0.0 → 2.1.0   [MINOR]  depends on MyLib.Http, MyLib.Caching

Apply all 5 version changes? [Y/n]:
```

`MyLib.Api` is listed once. Its trigger is MAJOR (from `MyLib.Core`), which outranks the MINOR from `MyLib.Abstractions`.

### Dry run

```bash
dotgraph update MyLib.Core 2.0.0 --dry-run
dotgraph update MyLib.Core 2.0.0 MyLib.Abstractions 1.1.0 --dry-run
```

Prints the proposal table without writing any files.

### Interactive mode

Use this when you want to review or override each proposal individually:

```bash
dotgraph update MyLib.Core 2.0.0 --interactive
```

```
Root change: MyLib.Core  1.2.0 → 2.0.0  [MAJOR]

─────────────────────────────────────────────────
Package:   MyLib.Http
Current:   1.5.0
Proposed:  1.6.0  [MINOR]  (depends on MyLib.Core, MAJOR bump)

  [1] Accept proposed  →  1.6.0
  [2] Enter version manually
  [3] Skip (leave at 1.5.0)
> _
```

After all choices a summary is shown before the final write:

```
Summary of changes:
  MyLib.Core      1.2.0 → 2.0.0   [MAJOR]   explicit
  MyLib.Http      1.5.0 → 1.6.0   [MINOR]   accepted proposal
  MyLib.Caching   1.1.0 → 1.2.0   [MINOR]   entered manually
  MyLib.Api       2.0.0 → 2.1.0   [MINOR]   accepted proposal

Apply these 4 changes? [Y/n]:
```

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

## Flags Reference

| Flag | Commands | Description |
|---|---|---|
| `--dry-run` | `update`, `sync` | Print proposals only, write nothing |
| `--interactive` | `update`, `sync` | Walk through each proposal interactively |
| `--force` | `update` | Allow version downgrades |
| `--solution <path>` | all | Specify solution file when multiple `.sln`/`.slnx` exist |

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
Warning: MyLib.Core 1.2.0 → 1.1.0 is a downgrade.
Use --force to apply anyway.
```

**Fix**: Use `--force` if intentional. Otherwise verify you typed the correct version.

---

## Tips

- **Commit `.dotgraph.json`** — `git diff .dotgraph.json` gives a clean view of what changed in each release.
- **Use `--dry-run` in CI** — run `dotgraph analyze` in your build pipeline to detect if any package was bumped without bumping its dependents.
- **Use `--interactive` for major bumps** — when making breaking changes, interactive mode lets you give each dependent a more meaningful version than the automatic proposal.
