# dotgraph — Data Model

## F# Types

### `SemVer`

```fsharp
type SemVer = {
    Major: int
    Minor: int
    Patch: int
    PreRelease: string option  // e.g. "beta.1", "rc.2" — informational only
}
```

Parsing rules:
- Input format: `MAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH-PRE`
- All numeric components must be non-negative integers
- Pre-release suffix after `-` is preserved as-is but not used in bump logic

Comparison: standard SemVer ordering — compare Major, then Minor, then Patch. Pre-release versions are considered lower than the release.

---

### `BumpType`

```fsharp
type BumpType = Major | Minor | Patch
```

Derived from comparing two `SemVer` values:

```fsharp
let detectBump (oldVer: SemVer) (newVer: SemVer) : BumpType =
    if newVer.Major > oldVer.Major then Major
    elif newVer.Minor > oldVer.Minor then Minor
    else Patch
```

---

### `PackageNode`

```fsharp
type PackageNode = {
    Name: string           // Matches the NuGet package ID (usually AssemblyName)
    Version: SemVer        // Value from <Version> in .csproj
    ProjectPath: string    // Absolute path to the .csproj file
    Dependencies: string list  // Names of packages referenced via <ProjectReference>
                               // (only those that are also nodes in the graph)
}
```

---

### `DependencyGraph`

```fsharp
type DependencyGraph = {
    SolutionPath: string          // Absolute path to the .slnx / .sln file
    CreatedAt: System.DateTime    // UTC timestamp of last init/refresh
    Packages: Map<string, PackageNode>  // Key = PackageNode.Name
}
```

---

### `VersionProposal`

```fsharp
type VersionProposal = {
    PackageName: string
    CurrentVersion: SemVer
    ProposedVersion: SemVer
    BumpType: BumpType
    Reason: string   // e.g. "depends on MyLib.Core (MAJOR bump)"
}
```

---

### `CascadeResult`

```fsharp
type CascadeResult = {
    RootPackage: string
    OldRootVersion: SemVer
    NewRootVersion: SemVer
    Proposals: VersionProposal list  // Ordered: direct dependents first, then transitive
}
```

---

## `.dotgraph.json` Schema

The graph snapshot is stored as a JSON file at `<solution-root>/.dotgraph.json`.

```json
{
  "$schema": "https://raw.githubusercontent.com/yourorg/dotgraph/main/schema/dotgraph.schema.json",
  "solutionPath": "MyApp.slnx",
  "createdAt": "2026-05-07T12:34:56Z",
  "packages": {
    "MyLib.Abstractions": {
      "version": "1.0.0",
      "projectPath": "src/MyLib.Abstractions/MyLib.Abstractions.csproj",
      "dependencies": []
    },
    "MyLib.Core": {
      "version": "1.2.0",
      "projectPath": "src/MyLib.Core/MyLib.Core.csproj",
      "dependencies": ["MyLib.Abstractions"]
    },
    "MyLib.Http": {
      "version": "1.5.0",
      "projectPath": "src/MyLib.Http/MyLib.Http.csproj",
      "dependencies": ["MyLib.Core"]
    },
    "MyLib.Caching": {
      "version": "1.1.0",
      "projectPath": "src/MyLib.Caching/MyLib.Caching.csproj",
      "dependencies": ["MyLib.Core"]
    },
    "MyLib.Api": {
      "version": "2.0.0",
      "projectPath": "src/MyLib.Api/MyLib.Api.csproj",
      "dependencies": ["MyLib.Http", "MyLib.Caching"]
    }
  }
}
```

### Field reference

| Field | Type | Description |
|---|---|---|
| `solutionPath` | `string` | Relative path to the solution file from the directory containing `.dotgraph.json` |
| `createdAt` | `string` (ISO 8601 UTC) | Timestamp of last `init` or `refresh` |
| `packages` | `object` | Map of package name → package entry |
| `packages.<name>.version` | `string` | Current version (SemVer format) |
| `packages.<name>.projectPath` | `string` | Relative path to `.csproj` from the directory containing `.dotgraph.json` |
| `packages.<name>.dependencies` | `string[]` | Names of other packages in this graph that this package depends on |

### Notes

- `solutionPath` and `projectPath` values are stored as **relative paths** (relative to the `.dotgraph.json` file location) to keep the file portable across machines.
- `dependencies` contains **only internal packages** (packages that are nodes in the graph). External `<PackageReference>` entries are not recorded here.
- The file should be **committed to source control** — it acts as a versioned snapshot useful for `git diff`.

---

## `.csproj` Elements Read by the Scanner

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <!-- Required: package version -->
    <Version>1.2.0</Version>

    <!-- Optional: if different from project file name -->
    <AssemblyName>MyLib.Core</AssemblyName>
    <PackageId>MyLib.Core</PackageId>
  </PropertyGroup>

  <ItemGroup>
    <!-- Internal dependency — will become a graph edge -->
    <ProjectReference Include="../MyLib.Abstractions/MyLib.Abstractions.csproj" />
  </ItemGroup>
</Project>
```

**Package name resolution priority** (first found wins):
1. `<PackageId>` — explicit NuGet package ID
2. `<AssemblyName>` — explicit assembly name
3. Project file name without extension — e.g. `MyLib.Core.csproj` → `MyLib.Core`

---

## Graph Invariants

The following invariants are enforced at `init` and `refresh` time:

1. **No cycles**: the graph must be a DAG. Circular `<ProjectReference>` chains are an error.
2. **Unique names**: no two projects may resolve to the same package name.
3. **All edges are internal**: `dependencies` entries always reference a package that is also a node in the graph.
