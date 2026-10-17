# Research: Branch Diff Version Bump

## 1. How the tool reads Git

**Decision**: Reference `LibGit2Sharp` 0.32.0 from `NugetPackageHelper.Scanner`. That package depends on `LibGit2Sharp.NativeBinaries` 2.0.324. The scanner opens the repository that contains the solution, looks up the saved branch by its local name, diffs that commit’s tree against the index and the working directory, and reads project-file text from the branch tree as a blob. The CLI never starts the `git` process.

**Rationale**: The spec needs the tip of a named branch and uncommitted edits to files that branch already contains. LibGit2Sharp 0.32.0 is the current release (2026-07-24), targets `net8.0`, and runs on the `net10.0` tool. `Repository.Diff.Compare` of a tree against `DiffTargets.Index | DiffTargets.WorkingDirectory` is the documented way to list those edits. Status listings exclude untracked files unless `IncludeUntracked` is set, which this feature must not set. Blob text at `branch.Tip[relativePath]` supplies the version on that branch without checking the branch out.

**Alternatives considered**: Calling `git` through `Process` or through Cake.Git. Rejected because the plan input asks for NuGet packages, and a missing `git` install would make the tool fail. A pure-managed reader such as GitReader. Rejected because worktree and index diffs are the part LibGit2Sharp already implements. A second wrapper package on top of LibGit2Sharp. Rejected as an extra dependency with no extra fact the tool needs.

## 2. Where the native library sits

**Decision**: Only the scanner project references LibGit2Sharp. Core stays free of it. The quickstart packs the global tool once and opens a repository, because a framework-dependent tool can fail at runtime if the native asset is not copied into the tool layout. There is no `PublishAot` in the CLI project; Native AOT is out of scope.

**Rationale**: Constitution I keeps decision logic testable without a native binary. Constitution V forbids a fourth runtime project for one IO library. The scanner already performs file IO.

**Alternatives considered**: Reference LibGit2Sharp from the CLI only. Rejected because the CLI would then own repository rules. A new `NugetPackageHelper.Git` project. Rejected because one module in the scanner is enough.

## 3. Where the compare branch is stored

**Decision**: Optional root property `compareBranch` on `.dotgraph.json`, mapped to `DependencyGraph.CompareBranch`. When the property is absent, loaders use `main` and do not rewrite the file just to add it. Setting the branch updates that property and saves. Version saves keep the property. A branch name that does not exist is still stored; `propose` and `review` report it and leave the file unchanged.

**Rationale**: The spec asks for one remembered setting with default `main`. The snapshot file is already the tool’s project file. A second config file would be a second format and a second “not found” path. Old snapshots stay valid because the reader treats a missing property as `main`, and today’s writer does not reject unknown properties when reading.

**Alternatives considered**: A user-profile setting outside the repository. Rejected because the branch is a property of the solution, and the spec’s “set it back to main” check is per solution. An environment variable. Rejected because it is not remembered.

## 4. Which paths select a package

**Decision**: From the tree diff, keep Modified, Deleted, Renamed, Copied, and TypeChanged entries whose old path exists in the compare-branch tree. Drop Added and anything that is only untracked. Map a path to the package whose project directory is the longest prefix of that path. The project file maps to its own package. A path under no project selects nothing.

A package that already exists on the branch is selected only when at least one kept path maps to it, and that set is not a version-tag-only edit. Version-tag-only means the only kept path is the project file, and the branch XML and the current XML are equal once the winning version tags are removed (`PackageVersion`, `Version`, `VersionPrefix`, `VersionSuffix`, `PackagePrefix`, `PackageSuffix`).

A project file that is not in the compare-branch tree is a new package. It is selected even though its files are new, and it is proposed as `1.0.0`. A package that is in the saved snapshot and missing from the live solution is reported as removed and is not versioned.

**Rationale**: The spec separates “a file the branch has never saved” (does not select an existing package) from “a package that does not exist on the branch” (first version `1.0.0`). Filtering on presence in the branch tree implements the first rule. The new-project rule is the exception, and it is about the project file, not about every untracked file beside an old project. Comparing XML without version tags avoids treating a formatting-sensitive line number as the definition of “only the version changed”.

**Alternatives considered**: Any dirty path, including untracked files. Rejected by the spec. Selecting a package when only its version tag changed. Rejected by the spec. Treating a new project as “no version on the branch, so skip it”. Rejected because the spec proposes `1.0.0`.

## 5. How the proposed number is chosen

**Decision**: For a selected package whose project file exists on the branch, parse that blob with the existing `resolveVersion` order. The proposal is `SemVer.applyBump Patch` of that version, so the release label is kept. The live version is not the base. If the blob has no numeric version, name the package, skip it, and continue. For a new package, the proposal is `1.0.0` with no release label.

The number is written with the existing write target on the current project file. When the current file has no version tag, the write target is the one that won on the branch blob.

`CascadeEngine.computeProposals` is called with root pairs `(package, compareBranchVersion, chosenVersion)` and with a graph filled with live versions. It remains the only follow-up calculator. A selected package left unchanged whose live version still equals the compare-branch version is omitted from those roots. A selected package already equal to its proposal is omitted from the write set and still passed as a root, so dependents move. The larger bump wins when a selected package is both a root and a dependent of another chosen root: compare the patch of the branch version with the follow-up `applyBump` would produce from that same branch version, and keep the higher one.

**Rationale**: `applyBump Patch` already increments the third number and copies `PreRelease`. Passing the branch version as the root’s “old” version makes `detectBump` see a patch (or a major/minor when the review typed one) instead of a downgrade against a dirty live version. Dependents still move from the versions in the current files because `computeProposals` reads `node.Version` for them.

**Alternatives considered**: Patch the live version. Rejected in clarification. A second bump function that also edits the suffix. Rejected because constitution IV keeps bumps in `SemVer` and `CascadeEngine`. Resetting dependents to the compare branch before cascading. Rejected by the spec: only selected packages take their base from the branch.

## 6. Review versus the existing interactive command

**Decision**: Add `Interactive.runBranchReview`. It lists selected packages first, in dependency order, then pure dependents. Leave unchanged is the focused choice. After each accepted or typed version, later proposals are rebuilt before they are shown. Quit, an empty change set, or a declined summary writes nothing. `Interactive.run` is not modified, so `update --interactive` and `sync --interactive` still focus Accept proposed first.

**Rationale**: The spec makes this a separate command with the opposite default and with recalculation. Folding a flag into `Interactive.run` would risk the existing review, which the spec says must stay as it is.

**Alternatives considered**: Reuse `Interactive.run` and tell the developer to pick Leave unchanged. Rejected because the focused default would still be Accept, and dependents would not be recalculated.
