# Research: Package Prefix and Suffix Updates

## 1. Where a release suffix is dropped

**Decision**: `SemVer.applyBump` keeps `PreRelease`. A follow-up bump changes only the numeric triple.

**Rationale**: `CascadeEngine.computeProposals` is the only place follow-up versions are created, and it calls `applyBump`. Today each arm sets `PreRelease = None`, so `1.2.0-beta` becomes `1.2.1` with no suffix. The spec requires the dependent's own suffix to stay. Preserving the field fixes every caller (update and sync) without a second bump implementation.

**Alternatives considered**: Re-attach the suffix in the CLI after `applyBump`. Rejected because constitution IV makes `CascadeEngine` the only bump source, and a CLI patch would miss `sync`.

## 2. Suffix-only changes and downgrades must not look like a patch bump

**Decision**: Add `Suffix` to `BumpType`. `detectBump` returns `Suffix` when the numeric triple is unchanged and the release suffix differs. `CascadeEngine` records a root in the cascade map only when `detectBump` returns `Major`, `Minor`, or `Patch` and `isDowngrade` is false. A suffix-only root and an earlier-release root produce no follow-up proposals.

**Rationale**: `detectBump` currently falls through to `Patch` whenever major and minor do not increase. A change from `1.0.0-beta` to `1.0.0-rc.1`, or a downgrade, would then patch every dependent. The spec treats a suffix-only difference as its own change, and an earlier release as a warning, not as a patch.

**Alternatives considered**: Leave `BumpType` at three cases and special-case the CLI labels. Rejected because `DiffEngine` and `CascadeEngine` would still cascade those changes as patches.

## 3. Ordering of release suffixes

**Decision**: Extend `SemVer.compare` with standard pre-release precedence. Identifiers split on `.`. All-digit identifiers compare as integers. A numeric identifier is lower than a non-numeric one. A longer remainder is higher when the shared prefix is equal. The same numbers with a suffix come before those numbers without a suffix. `isDowngrade` stays `compare new old < 0`, so `1.2.0` → `1.2.0-beta` is a downgrade and `1.2.0-beta` → `1.2.0` is not.

**Rationale**: `compare` today stops at patch, so `DiffEngine` treats `1.0.0-beta` and `1.0.0-rc.1` as equal and omits the change. The design note in `docs/design/data-model.md` already says a pre-release is lower than the release; the code does not do that yet. Snapshot JSON already stores `SemVer.toString`, which includes the suffix, so no file-format change is required.

**Alternatives considered**: Compare the suffix as a raw string. Rejected because `beta.10` would sort before `beta.2`.

## 4. `PackagePrefix` and `PackageSuffix` tag order

**Decision**: One resolver in `ProjectScanner` tries non-empty tags in this order: `PackageVersion`, `Version`, `VersionPrefix` plus optional `VersionSuffix`, `PackagePrefix` plus optional `PackageSuffix`. Write uses that same winner. Later tags are not modified and earlier tags are not created. A prefix/suffix winner stores `MAJOR.MINOR.PATCH` on the prefix tag and the release label on the matching suffix tag. An empty suffix tag means no suffix. A missing suffix tag is created beside the prefix tag only when the new version has a suffix. A lone suffix tag, with no prefix and no earlier version tag, stays a warning and the project stays out of the graph.

**Rationale**: Read and write already share `resolveVersion` and `resolveVersionWriteTarget` for the first three winners. The clarified spec appends the fourth pair without reordering the three the constitution names. Combining a prefix tag with its suffix tag already exists for `VersionPrefix`; `PackagePrefix` uses that same combine function.

**Alternatives considered**: Treat `PackagePrefix` as an alias that wins over `VersionPrefix`. Rejected in clarification (option A). Writing both pairs to keep them equal. Rejected for the same reason.

## 5. Console review and color

**Decision**: Keep Spectre.Console 0.55 as the only renderer. `Output` owns the change-size words and colors: MAJOR red, MINOR yellow, PATCH green, SUFFIX grey, Error red, Warning yellow. `Interactive` calls those helpers. Markup stays inside `AnsiConsole`, which strips color when `NO_COLOR` is set or when stdout is not a terminal. The review shows "N of M", the current and proposed prefix, the suffix or `none`, and the choices Accept (focused first), Enter a version, and Leave unchanged. Invalid input says to use `1.2.3` or `1.2.3-beta.1` and asks again. A typed earlier release asks for confirmation unless `--force` is already set. The summary splits "Will change" and "Left unchanged". Zero changes print "Nothing will be written." and do not ask to apply.

**Rationale**: `update --interactive` and `sync --interactive` already call `Interactive.run` and `confirmSummary`. The gaps are display and the skip/downgrade/empty paths, not a new command. A second color library would duplicate Spectre's `NO_COLOR` handling.

**Alternatives considered**: A new test project that drives the console. Rejected. Constitution III puts behavior tests in `NugetPackageHelper.Core.Tests` and `NugetPackageHelper.Scanner.Tests`. Version rules and tag IO are tested there. The prompt walk-through is checked with the quickstart.

## 6. Explicit downgrade before the review starts

**Decision**: In interactive `update`, an earlier explicit version does not abort before the review. The review shows it as a warning and writes it only after the final confirmation, or immediately when `--force` is set. Non-interactive `update` keeps today's behavior: warn and exit with code 1 unless `--force`.

**Rationale**: FR-006 allows an earlier release after confirmation or when the developer already allowed earlier versions. `--force` is that allowance. Aborting before the interactive review removes the confirmation the spec asks for.

**Alternatives considered**: Always require `--force`, including interactive. Rejected because the spec's interactive scenario confirms an earlier typed version without a separate flag.
