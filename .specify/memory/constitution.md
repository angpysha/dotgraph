# dotgraph Constitution

## Core Principles

### I. Library-First

Core logic lives in `NugetPackageHelper.Core` and `NugetPackageHelper.Scanner`. The CLI is a thin
command layer. Libraries must be independently testable with xUnit.

### II. CLI Interface

The `dotgraph` global tool exposes all user-facing behavior via subcommands with clear stdout/stderr
and non-zero exit codes on failure.

### III. Test-First

Behavior changes require tests in `NugetPackageHelper.Core.Tests` or
`NugetPackageHelper.Scanner.Tests`. Run `dotnet test --configuration Release` before merge.

### IV. Semver Cascade Integrity

Version reads and writes must use the same MSBuild tag priority (`PackageVersion` → `Version` →
`VersionPrefix`/`VersionSuffix` → `PackagePrefix`/`PackageSuffix`). Cascade rules in `CascadeEngine` are the single source of bump
logic.

### V. Simplicity

Prefer minimal diffs, no over-abstraction, and match existing F# conventions in the repo.

## Stack Constraints

- F# on .NET 10, SDK-style projects
- GitHub Actions CI on every PR to `main`
- Serena MCP for codebase discovery (project `package_helper`)

## Workflow

Spec Kit drives SDLC phases (`/speckit.*`). Coordinator gates requirements, design, tasks, dev,
and test before closeout.
