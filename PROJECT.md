# dotgraph (package_helper)

> Living project brief for the dotgraph NuGet package graph CLI.

## Vision

Developers who publish a suite of internally referenced NuGet packages need a reliable way to detect manual version changes and cascade semver bumps through the dependency graph. **dotgraph** scans a .NET solution, builds a dependency snapshot (`.dotgraph.json`), compares live project versions to that snapshot, and applies cascade bumps so re-publishing never hits duplicate-version rejections on the feed.

Success looks like: init once, edit version tags in project files, run `dotgraph sync`, and all affected upstream packages are bumped consistently with clear MAJOR/MINOR/PATCH rules.

## Stack

- **Language:** F# on .NET 10
- **Project layout:** SDK-style `.fsproj` projects, `NugetPackageHelper.slnx`
- **CLI:** `dotgraph` global tool (`NugetPackageHelper.Cli`)
- **Libraries:** Core (graph, semver, diff, cascade), Scanner (solution/project parsing)
- **Tests:** xUnit + FsUnit (`dotnet test`)
- **CI/CD:** GitHub Actions (build + test on push/PR)
- **Publishing:** NuGet.org via tagged GitHub release workflow
- **Code search:** Serena MCP (`.serena/project.yml`, project `package_helper`)

## Delivery

- **Tracker:** beads (`br` CLI)
- **PR provider:** GitHub (`main` target branch)
- **Default lane:** full SDLC via Spec Kit

## Open questions

- None for adapt — existing mature CLI with tests and CI.
