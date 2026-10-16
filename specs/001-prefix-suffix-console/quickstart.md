# Quickstart: Package Prefix and Suffix Updates

Validation guide for `specs/001-prefix-suffix-console`. Tag rules are in [contracts/version-tags.md](contracts/version-tags.md). Console rules are in [contracts/cli-review.md](contracts/cli-review.md).

## Prerequisites

- .NET 10 SDK
- Repo root as the working directory

## Automated checks

```bash
dotnet test --configuration Release
```

Expected: all tests in `NugetPackageHelper.Core.Tests` and `NugetPackageHelper.Scanner.Tests` pass, including:

- Follow-up bump of `1.2.0-beta` keeps `beta`
- `1.0.0-beta` versus `1.0.0-rc.1` is a difference, and `1.2.0` → `1.2.0-beta` is an earlier release
- `PackagePrefix` / `PackageSuffix` read and write, and they lose to `PackageVersion`, `Version`, and `VersionPrefix`

## Manual preview

Build the tool once:

```bash
dotnet build src/NugetPackageHelper.Cli/NugetPackageHelper.Cli.fsproj --configuration Release
```

Run it as `dotnet src/NugetPackageHelper.Cli/bin/Release/net10.0/dotgraph.dll` from a sample solution that already has `.dotgraph.json`, or as `dotgraph` after `dotnet pack` and a local tool install.

1. **Suffix-only diff.** Change one project's suffix and nothing else. `dotgraph diff` lists that package with the word SUFFIX and both suffixes. A second project whose number changed shows MAJOR, MINOR, or PATCH. An unchanged project is absent.
2. **Dry run.** `dotgraph update <package> <version> --dry-run` prints prefix and suffix for every row and leaves project files and `.dotgraph.json` unchanged (`git status` clean for those files).
3. **PackagePrefix write.** On a project whose only version tags are `PackagePrefix` and `PackageSuffix`, set `1.6.0-beta.2`. Those two tags update. `PackageVersion`, `Version`, and `VersionPrefix` are not added.
4. **Earlier tag wins.** On a project with `PackageVersion` `2.0.0` and `PackagePrefix` `1.0.0`, set `2.1.0`. Only `PackageVersion` changes.
5. **Follow-up suffix.** A dependent at `1.2.0-beta` whose dependency takes a minor bump becomes a patch with suffix `beta`.
6. **Interactive.** `dotgraph update <package> <version> --interactive` shows roots, then `Package N of M`, then Accept / Enter a version / Leave unchanged. Type `1.4.0-beta.2` for one package and leave another unchanged. Answer no at the summary. Nothing is written. Run again, answer yes, and only the accepted and typed packages change.
7. **Empty review.** Leave every follow-up unchanged and use an explicit version equal to the current one. The console prints `Nothing will be written.` and does not ask to apply.
8. **Earlier release.** Interactively type `1.2.0-beta` over `1.2.0`. The console warns and writes only after confirmation. The same request without `--interactive` or `--force` exits 1 and writes nothing.
9. **No color.** `NO_COLOR=1 dotgraph diff` prints MAJOR / MINOR / PATCH / SUFFIX / Error / Warning and the versions, with no ANSI escape bytes. Redirecting stdout to a file does the same.

## Done

The run matches the nine acceptance scenarios in User Story 1 and the interactive and no-color stories in the spec. `dotnet test --configuration Release` is green.
