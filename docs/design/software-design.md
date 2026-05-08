# dotgraph — Software Design Document

## 1. Goals

**Primary goal**: Given a .NET solution where multiple projects are published as NuGet packages and reference each other via `<ProjectReference>`, automatically detect which packages need version bumps when one or more packages change, and apply those bumps safely.

**Non-goals**:
- Managing external/third-party package updates (e.g., `Newtonsoft.Json`)
- Querying NuGet.org or any remote feed
- Publishing packages (only manages versioning)
- Supporting `packages.config` or `Directory.Packages.props`

---

## 2. Architecture Overview

```mermaid
graph TD
    CLI["NugetPackageHelper.Cli\n(dotgraph)"]
    Scanner["NugetPackageHelper.Scanner\n(file parsing)"]
    Core["NugetPackageHelper.Core\n(domain + graph logic)"]
    SlnFile[".slnx / .sln file"]
    CsprojFiles[".csproj files"]
    GraphJson[".dotgraph.json"]

    CLI --> Scanner
    CLI --> Core
    Scanner --> SlnFile
    Scanner --> CsprojFiles
    Core --> GraphJson
```

### Component responsibilities

| Component | Responsibility |
|---|---|
| `NugetPackageHelper.Core` | Domain types, SemVer parsing/comparison, graph data structure, BFS/DFS traversal, version proposal logic |
| `NugetPackageHelper.Scanner` | Parsing `.slnx`/`.sln` to enumerate projects; parsing `.csproj` to extract `<Version>` and `<ProjectReference>` elements |
| `NugetPackageHelper.Cli` | CLI argument parsing, command dispatch, output formatting, interactive mode (Spectre.Console) |

---

## 3. Core Domain Types

```fsharp
// Semantic version
type SemVer = {
    Major: int
    Minor: int
    Patch: int
    PreRelease: string option
}

// How much a version changed
type BumpType = Major | Minor | Patch

// A single node in the dependency graph
type PackageNode = {
    Name: string          // Project/assembly name (matches NuGet package id)
    Version: SemVer
    ProjectPath: string   // Absolute path to .csproj
    Dependencies: string list  // Names of packages this project references via ProjectReference
}

// The full graph snapshot
type DependencyGraph = {
    SolutionPath: string
    CreatedAt: System.DateTime
    Packages: Map<string, PackageNode>
}

// A proposed version change for a dependent package
type VersionProposal = {
    PackageName: string
    CurrentVersion: SemVer
    ProposedVersion: SemVer
    BumpType: BumpType
    Reason: string        // Human-readable: "depends on MyLib.Core (MAJOR bump)"
}

// Result of an analyze or update operation
type CascadeResult = {
    Root: PackageName * SemVer * SemVer  // (name, old, new)
    Proposals: VersionProposal list       // ordered by graph depth (leaves first)
}

// A version change detected by comparing snapshot to live .csproj
type PackageChange = {
    PackageName: string
    SnapshotVersion: SemVer   // version stored in .dotgraph.json
    CurrentVersion: SemVer    // version found in .csproj right now
    BumpType: BumpType
}

// Full diff between snapshot and current filesystem state
type SnapshotDiff = {
    Changed: PackageChange list         // packages where csproj version ≠ snapshot version
    CascadeGaps: VersionProposal list   // dependents that need a bump but haven't been bumped yet
    AlreadyCovered: VersionProposal list // dependents already bumped by the user manually
}
```

---

## 4. Dependency Graph

The graph is a **directed acyclic graph (DAG)**:

- **Node**: a project in the solution that is published as a NuGet package
- **Edge A → B**: project A has `<ProjectReference>` to project B, meaning A *depends on* B

```mermaid
graph TD
    A["MyLib.Api\nv2.0.0"]
    B["MyLib.Http\nv1.5.0"]
    C["MyLib.Caching\nv1.1.0"]
    D["MyLib.Core\nv1.2.0"]
    E["MyLib.Abstractions\nv1.0.0"]

    A --> B
    A --> C
    B --> D
    C --> D
    D --> E
```

When a node's version changes, all nodes that **transitively depend on it** (reachable by following edges in reverse — upstream traversal) may need version bumps.

---

## 5. Application Flows

### 5.1 `dotgraph init`

```mermaid
flowchart TD
    Start([dotgraph init]) --> FindSln[Find .slnx or .sln in current directory]
    FindSln --> ParseSln[Parse solution file\nextract project paths]
    ParseSln --> ForEach[For each .csproj]
    ForEach --> ReadVersion[Read Version tag]
    ForEach --> ReadRefs[Read ProjectReference tags]
    ReadRefs --> FilterRefs[Keep only refs whose targets\nare also in the solution]
    FilterRefs --> BuildNode[Build PackageNode]
    ReadVersion --> BuildNode
    BuildNode --> MoreProjects{More projects?}
    MoreProjects -- Yes --> ForEach
    MoreProjects -- No --> BuildGraph[Assemble DependencyGraph]
    BuildGraph --> ValidateDAG{Graph is a DAG?\nno cycles}
    ValidateDAG -- No --> Error[Error: circular dependency detected\nlist the cycle]
    ValidateDAG -- Yes --> WriteJson[Write .dotgraph.json]
    WriteJson --> Done([Done — graph saved])
```

### 5.2 `dotgraph analyze <pkg>`

```mermaid
flowchart TD
    Start([dotgraph analyze MyLib.Core]) --> LoadGraph[Load .dotgraph.json]
    LoadGraph --> Missing{Graph file exists?}
    Missing -- No --> InitHint[Error: run dotgraph init first]
    Missing -- Yes --> FindNode[Find package node in graph]
    FindNode --> NotFound{Package found?}
    NotFound -- No --> Error[Error: unknown package name]
    NotFound -- Yes --> BFS[BFS/DFS upstream traversal\nfind all packages that\ntransitively depend on it]
    BFS --> Rank[Rank by graph depth\ndirectly dependent first]
    Rank --> Print[Print affected list\nwith current versions]
    Print --> Done([Done — no files changed])
```

### 5.3 `dotgraph update <pkg> <version>`

```mermaid
flowchart TD
    Start([dotgraph update MyLib.Core 2.1.0]) --> LoadGraph[Load .dotgraph.json]
    LoadGraph --> FindNode[Find package node]
    FindNode --> DetectBump[Detect bump type\nold vs new version]
    DetectBump --> BFS[Upstream BFS traversal\nfind all affected packages]
    BFS --> ProposeVersions[For each affected package\npropose new version\nusing cascade rules]
    ProposeVersions --> Mode{--interactive flag?}

    Mode -- No --> PrintAll[Print all proposals]
    PrintAll --> Confirm{--dry-run?}
    Confirm -- Yes --> Done([Done — no files changed])
    Confirm -- No --> AskConfirm[Prompt: Apply all? Y/n]
    AskConfirm -- Yes --> Apply[Apply all version changes\nto .csproj files + .dotgraph.json]
    AskConfirm -- No --> Abort([Aborted])

    Mode -- Yes --> Interactive[Interactive mode loop]
    Interactive --> Done
    Apply --> Done([Done])
```

### 5.4 Interactive Mode

```mermaid
flowchart TD
    Start([Interactive mode]) --> ShowRoot[Show root package change]
    ShowRoot --> NextProposal[Take next proposal from queue]
    NextProposal --> ShowProposal[Display:\n- Package name\n- Current version\n- Proposed version\n- Reason]
    ShowProposal --> UserChoice{User choice}

    UserChoice -- Accept proposal --> ApplyProposed[Use proposed version]
    UserChoice -- Enter manually --> PromptInput[Prompt for version string]
    PromptInput --> ValidateInput{Valid semver?}
    ValidateInput -- No --> PromptInput
    ValidateInput -- Yes --> ApplyManual[Use entered version]
    UserChoice -- Skip --> SkipPackage[Leave version unchanged\nmark as skipped]

    ApplyProposed --> MoreProposals{More proposals?}
    ApplyManual --> MoreProposals
    SkipPackage --> MoreProposals

    MoreProposals -- Yes --> NextProposal
    MoreProposals -- No --> Summary[Show summary of all decisions]
    Summary --> FinalConfirm{Confirm and apply?}
    FinalConfirm -- Yes --> WriteFiles[Write all version changes\nto .csproj files + .dotgraph.json]
    FinalConfirm -- No --> Abort([Aborted — no files changed])
    WriteFiles --> Done([Done])
```

### 5.5 `dotgraph diff` — Auto-detect Changes

Compares the live `.csproj` versions against the `.dotgraph.json` snapshot to show exactly what changed and what cascade bumps are still missing. **Read-only — no files are written.**

```mermaid
flowchart TD
    Start([dotgraph diff]) --> LoadGraph[Load .dotgraph.json snapshot]
    LoadGraph --> ScanAll[Scan all .csproj files\nread current Version tags]
    ScanAll --> Compare[For each package:\ncompare snapshot version\nvs current version]

    Compare --> Classify{Version changed?}
    Classify -- Yes, bumped up --> Changed[Add to Changed list\nrecord old→new + BumpType]
    Classify -- No change --> Unchanged[Keep as unchanged]
    Classify -- Yes, downgraded --> Downgrade[Add to Changed list\nflag as DOWNGRADE warning]

    Changed --> BuildAffected[For each changed package:\nBFS upstream to find dependents]
    BuildAffected --> CheckEach{Dependent version\nalso changed vs snapshot?}

    CheckEach -- No change --> Gap[Add to CascadeGaps\npropose a version]
    CheckEach -- Yes, bumped --> Covered[Add to AlreadyCovered\nuser already handled it]

    Gap --> Render
    Covered --> Render
    Unchanged --> Render

    Render[Render SnapshotDiff report\nin three sections]
    Render --> Done([Done — no files changed])
```

**Output format** (`dotgraph diff`):

```
Changed packages (vs snapshot):
  MyLib.Core      1.2.0 → 2.0.0   [MAJOR]
  MyLib.Caching   1.1.0 → 1.2.0   [MINOR]  ← also manually bumped

Cascade gaps (need version bumps):
  MyLib.Http      1.5.0   → propose 1.6.0   [MINOR]  depends on MyLib.Core (MAJOR)
  MyLib.Api       2.0.0   → propose 2.1.0   [MINOR]  depends on MyLib.Http

Already covered (manually bumped, no action needed):
  MyLib.Caching   1.1.0 → 1.2.0   [MINOR]  depends on MyLib.Core (MAJOR) ✓

Run 'dotgraph sync' to apply the proposed cascade bumps.
```

---

### 5.6 `dotgraph sync` — Auto-detect and Apply Cascade

Runs the same diff as `dotgraph diff`, then proposes and applies version bumps for all cascade gaps. Accepts `--dry-run` and `--interactive` flags with the same semantics as `dotgraph update`.

```mermaid
flowchart TD
    Start([dotgraph sync]) --> Diff[Run snapshot diff\nsame as dotgraph diff logic]

    Diff --> AnyChanged{Any changed\npackages found?}
    AnyChanged -- No --> NothingToDo([Nothing to do.\nAll versions match snapshot.\nConsider running dotgraph refresh\nif you added new projects.])

    AnyChanged -- Yes --> AnyGaps{Any cascade\ngaps?}
    AnyGaps -- No --> NoGaps([All dependents already bumped.\nRun dotgraph refresh to update snapshot.])

    AnyGaps -- Yes --> Mode{--interactive?}

    Mode -- No --> PrintAll[Print diff report\n+ all proposals]
    PrintAll --> DryRun{--dry-run?}
    DryRun -- Yes --> Done([Done — no files changed])
    DryRun -- No --> AskConfirm[Prompt: Apply N version changes? Y/n]
    AskConfirm -- Yes --> ApplyAll[Write all proposed versions\nto .csproj files\nUpdate .dotgraph.json]
    AskConfirm -- No --> Abort([Aborted])

    Mode -- Yes --> Interactive[Interactive loop\nover all proposals\n(same as update --interactive)]
    Interactive --> Done([Done])
    ApplyAll --> Done
```

---

### 5.7 Multi-root Cascade (multiple packages changed simultaneously)

When `dotgraph diff` / `dotgraph sync` detects that **several packages** changed in one batch, their affected sets are merged before proposing versions. The trigger bump for each dependent is the **largest** bump type among all its changed direct or transitive dependencies.

```mermaid
flowchart TD
    A["MyLib.Abstractions\n1.0.0 → 2.0.0\n(MAJOR)"]
    B["MyLib.Core\n1.2.0 → 1.3.0\n(MINOR) — also manually bumped"]
    C["MyLib.Http\ngap → propose 1.6.0 [MINOR]\ntrigger: Core MINOR"]
    D["MyLib.Api\ngap → propose 2.1.0 [MINOR]\ntrigger: Http MINOR\n(Abstractions MAJOR is not direct)"]
    E["MyLib.Caching\ngap → propose 1.2.0 [MINOR]\ntrigger: Core MINOR"]

    A -->|root change| B
    B -->|root change| C
    C --> D
    B --> E
    E --> D
```

Resolution rules when a dependent has **multiple changed ancestors**:
1. Collect the bump type from each direct dependency that changed (or whose proposal is known).
2. Take the **maximum** — `Major > Minor > Patch`.
3. Apply the cascade proposal rule for that maximum bump type.

This ensures a dependent never receives a weaker-than-needed version bump when it sits below multiple roots.

---

## 6. Version Cascade Rules

### Bump type detection

Given old version `a.b.c` and new version `x.y.z`:

| Condition | Detected bump |
|---|---|
| `x > a` | MAJOR |
| `x == a` and `y > b` | MINOR |
| `x == a` and `y == b` and `z > c` | PATCH |

### Cascade proposal table

| Parent bump | Proposed bump for each dependent |
|---|---|
| MAJOR | MINOR (bump minor, reset patch to 0) |
| MINOR | PATCH (bump patch only) |
| PATCH | PATCH (bump patch only) |

**Rationale**: A dependent whose code hasn't changed only needs to re-publish with updated dependency references — a minor or patch bump communicates "no new functionality in this package itself".

### Transitive cascade

When computing proposals, the *trigger bump type* used for each dependent is the bump type of its **closest changed dependency** (the one with the largest bump). If A depends on B (MAJOR) and C (PATCH), A's trigger is MAJOR.

```mermaid
flowchart LR
    Core["Core\n1.0.0 → 2.0.0\n(MAJOR)"]
    Http["Http\n1.5.0 → 1.6.0\n(MINOR proposal)"]
    Api["Api\n2.0.0 → 2.1.0\n(PATCH proposal\nbased on Http's MINOR)"]

    Core -->|MAJOR triggers MINOR| Http
    Http -->|MINOR triggers PATCH| Api
```

---

## 7. File Parsing

### Solution files

- `.slnx` (new XML format, Visual Studio 2022+): parse `<Project Path="..." />` elements
- `.sln` (classic format): parse `Project(...)` lines with regex

### `.csproj` parsing

Extract from each project file:

| Element | XPath / location |
|---|---|
| Package version | `<Project><PropertyGroup><Version>` |
| Project references | `<Project><ItemGroup><ProjectReference Include="..." />` |

The `Include` attribute on `<ProjectReference>` is a relative path — resolve it to an absolute path, then match against the set of known solution projects to build the edge list.

---

## 8. Error Handling

| Scenario | Behavior |
|---|---|
| `.dotgraph.json` not found | Print error with hint to run `dotgraph init` |
| Circular dependency detected during init | Print the cycle and exit with error |
| Package name not found in graph | Print fuzzy-matched suggestions |
| Downgrade attempted (new version < old) | Warn user, require `--force` flag to proceed |
| `.csproj` has no `<Version>` tag | Skip that project, warn user |
| Multiple `.slnx`/`.sln` files in directory | Require `--solution <path>` flag |
| `dotgraph diff` / `sync` — no changes detected | Print "all versions match snapshot" and hint to run `dotgraph refresh` if new projects were added |
| `dotgraph sync` — all dependents already covered | Print "no cascade gaps" and hint to run `dotgraph refresh` to save the new baseline |
| `dotgraph diff` — a package version decreased vs snapshot | Show as DOWNGRADE warning in the diff report; `sync` will not auto-propose a fix, requires explicit `dotgraph update --force` |

---

## 9. Module Dependency Diagram

```mermaid
classDiagram
    class SemVer {
        +int Major
        +int Minor
        +int Patch
        +string PreRelease
        +parse(string) SemVer
        +toString() string
        +compare(SemVer) int
    }

    class PackageNode {
        +string Name
        +SemVer Version
        +string ProjectPath
        +string[] Dependencies
    }

    class DependencyGraph {
        +string SolutionPath
        +DateTime CreatedAt
        +Map Packages
        +findUpstream(name) PackageNode[]
        +detectCycle() string[] option
    }

    class VersionProposal {
        +string PackageName
        +SemVer CurrentVersion
        +SemVer ProposedVersion
        +BumpType BumpType
        +string Reason
    }

    class SolutionScanner {
        +scan(solutionPath) string[]
    }

    class ProjectScanner {
        +scan(csprojPath) PackageNode
    }

    class GraphPersistence {
        +load(path) DependencyGraph
        +save(path, graph) unit
    }

    class CascadeEngine {
        +computeProposals(graph, name, newVersion) VersionProposal[]
    }

    class DiffEngine {
        +diff(snapshot, liveScan) SnapshotDiff
        +mergeRoots(changes) VersionProposal[]
    }

    class PackageChange {
        +string PackageName
        +SemVer SnapshotVersion
        +SemVer CurrentVersion
        +BumpType BumpType
    }

    class SnapshotDiff {
        +PackageChange[] Changed
        +VersionProposal[] CascadeGaps
        +VersionProposal[] AlreadyCovered
    }

    DependencyGraph "1" --> "*" PackageNode : contains
    PackageNode --> SemVer : has
    VersionProposal --> SemVer : current + proposed
    CascadeEngine --> DependencyGraph : reads
    CascadeEngine --> VersionProposal : produces
    DiffEngine --> DependencyGraph : reads snapshot
    DiffEngine --> PackageChange : produces
    DiffEngine --> SnapshotDiff : produces
    DiffEngine --> CascadeEngine : delegates cascade
    SolutionScanner --> ProjectScanner : uses
    ProjectScanner --> PackageNode : produces
    GraphPersistence --> DependencyGraph : serializes
```

---

## 10. Technology Choices

| Concern | Choice | Reason |
|---|---|---|
| Language | F# | Algebraic types suit domain modeling; pattern matching fits version/bump logic |
| CLI parsing | `System.CommandLine` | Official .NET library, composable, good subcommand support |
| Interactive TUI | `Spectre.Console` | Rich terminal output; prompt/selection components for interactive mode |
| JSON serialization | `System.Text.Json` | Built-in, no extra dependency |
| XML parsing | `System.Xml.Linq` (XDocument) | Clean F# interop for `.csproj` parsing |
| Testing | `xunit` + `FsUnit` | Standard .NET test stack with F#-friendly assertions |
