# Feature Specification: Package Prefix and Suffix Updates

**Feature Branch**: `feature/42-prefix-suffix-console`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "Check full solution and verify if it support also packagepreffix and suffix update if require. Also Check if some interactive mode exist for package updates and how it will work in cosnole app. You can also use some colors and best practises for ui/ux for console to make this more simple for user"

## Clarifications

### Session 2026-10-16

- Q: Which project-file tags should win when a package stores its version in more than one place? → A: `PackageVersion`, then `Version`, then `VersionPrefix` and `VersionSuffix`, then `PackagePrefix` and `PackageSuffix`. Write back only to the first tag that has a numeric version.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Update prefix and suffix together (Priority: P1)

A developer maintains a solution of internal packages. Some packages store a version as one value (`PackageVersion` or `Version`, for example `1.5.0` or `1.5.0-beta.1`). Others store the same idea as a numeric prefix plus an optional release suffix, in `VersionPrefix` and `VersionSuffix` or in `PackagePrefix` and `PackageSuffix`. When the developer sets a new version, the tool reads the first of those tags that has a numeric version and writes the new prefix and suffix back only to that tag or tag pair.

**Why this priority**: A wrong or dropped suffix publishes a different package than the developer intended. Getting the written version right is the core of the tool.

**Independent Test**: Point the tool at a solution that mixes `PackageVersion`, `Version`, `VersionPrefix`/`VersionSuffix`, and `PackagePrefix`/`PackageSuffix`. Set one explicit version that includes a suffix, and one that does not. Confirm each affected package ends with the intended prefix and suffix on the winning tag only, and that later tags and untouched packages stay as they were.

**Acceptance Scenarios**:

1. **Given** a package stored as prefix `1.5.0` and suffix `beta.1`, **When** the developer sets that package to `1.6.0-beta.2`, **Then** the prefix becomes `1.6.0` and the suffix becomes `beta.2`.
2. **Given** a package stored as prefix `1.5.0` and suffix `beta.1`, **When** the developer sets that package to `1.6.0` with no suffix, **Then** the prefix becomes `1.6.0` and the suffix is cleared.
3. **Given** a package stored as a single version `2.0.0-rc.1`, **When** the developer sets it to `2.0.1-rc.1`, **Then** the stored version becomes `2.0.1-rc.1` and no separate suffix field is created.
4. **Given** a dependent package whose current version is `1.2.0-beta`, **When** a follow-up bump is required because a dependency changed, **Then** the numeric prefix is bumped by the usual change-size rules and the suffix stays `beta`.
5. **Given** a package with a release suffix and no numeric prefix, **When** the developer updates the solution, **Then** that package is named in a warning, left unchanged, and the rest of the solution still updates.
6. **Given** a confirmed update, **When** the tool finishes writing, **Then** the saved snapshot shows the same prefix and suffix as each package that was written.
7. **Given** a package at `1.2.0`, **When** the developer sets `1.2.0-beta` and has not already allowed earlier versions, **Then** the tool warns that this is an earlier release and writes it only after the developer confirms.
8. **Given** a package whose only version tags are `PackagePrefix` `1.5.0` and `PackageSuffix` `beta.1`, **When** the developer sets `1.6.0-beta.2`, **Then** `PackagePrefix` becomes `1.6.0`, `PackageSuffix` becomes `beta.2`, and `PackageVersion`, `Version`, and `VersionPrefix` are not created.
9. **Given** a package with `PackageVersion` `2.0.0` and also `PackagePrefix` `1.0.0`, **When** the developer sets `2.1.0`, **Then** `PackageVersion` becomes `2.1.0` and `PackagePrefix` stays `1.0.0`.

---

### User Story 2 - See what will change before anything is written (Priority: P2)

Before files change, the developer can review the whole solution and see, for every affected package, the current prefix, the current suffix (or none), the proposed prefix, the proposed suffix (or none), and why the change is proposed. A change that touches only the suffix is visible. A change that touches only the number is visible. Packages already at the right version are shown as needing nothing.

**Why this priority**: The developer asked to check the full solution. Writing the wrong suffix is worse than showing a clear preview.

**Independent Test**: Change only a suffix on one package, only a number on another, and leave a third unchanged. Run the difference report and a dry update. Confirm the three outcomes are distinct and that no file is written.

**Acceptance Scenarios**:

1. **Given** a saved snapshot of `1.0.0-beta` and a live version of `1.0.0-rc.1`, **When** the developer asks what changed, **Then** the package is listed as changed and both suffixes are shown.
2. **Given** a live version `1.2.0` and a proposal `1.2.1` with no suffix, **When** the developer previews an update, **Then** the report shows prefix `1.2.0` → `1.2.1` and suffix none → none.
3. **Given** the same preview, **When** the developer asks for a dry run, **Then** the report is shown and every package file and the saved snapshot stay as they were.
4. **Given** a move from `1.2.0` to `1.2.0-beta`, **When** the preview is shown, **Then** the tool warns that the new version is an earlier release than the current one.
5. **Given** a move from `1.2.0-beta` to `1.2.0`, **When** the preview is shown, **Then** the tool does not treat clearing the suffix as a downgrade.

---

### User Story 3 - Review each package in the console (Priority: P3)

The developer can turn on an interactive review for package updates and for applying missing follow-up bumps. The console walks one affected package at a time. For each package the developer accepts the proposal, types a version, or leaves the package unchanged. Typed versions may include a release suffix. After the last package, one summary lists what will change and what will stay, and nothing is written until the developer confirms.

**Why this priority**: Interactive review already exists as a choice on update and on applying follow-up bumps. This story defines how that review works so prefix and suffix decisions are obvious.

**Independent Test**: Run an interactive update that affects three packages. Accept the first, type `2.0.0-rc.1` for the second, and leave the third unchanged. Decline the final confirmation and confirm nothing was written. Repeat and accept the confirmation; confirm only the first two packages changed, and the second has prefix `2.0.0` and suffix `rc.1`.

**Acceptance Scenarios**:

1. **Given** an update with follow-up packages, **When** the developer asks for interactive review, **Then** the console first shows the versions they named, then each affected package with current prefix, current suffix, proposed prefix, proposed suffix, and a one-line reason.
2. **Given** a package on screen, **When** the developer looks at the choices, **Then** the choices are Accept proposed, Enter a version, and Leave unchanged, with Accept focused first.
3. **Given** Enter a version, **When** the developer types `1.4.0-beta.2`, **Then** that version is accepted and the later summary shows prefix `1.4.0` and suffix `beta.2`.
4. **Given** Enter a version, **When** the developer types text that is not a version, **Then** the console says what is wrong, shows an example of a valid version with and without a suffix, and asks again without leaving the package.
5. **Given** the developer has answered every package, **When** the summary appears, **Then** it groups packages that will change and packages left unchanged, shows from → to for each change, and asks one yes-or-no question before writing.
6. **Given** the final question, **When** the developer says no, **Then** no package and no saved snapshot is changed.
7. **Given** every package was left unchanged, **When** the review ends, **Then** the console says nothing will be written and does not ask to apply an empty change.
8. **Given** five affected packages, **When** the third is on screen, **Then** the console shows that this is package 3 of 5.
9. **Given** the developer types a version that is earlier than the current one, **When** they have not already allowed earlier versions, **Then** the console names both versions, warns, and writes that earlier version only if they confirm it.

---

### User Story 4 - Understand the console with or without color (Priority: P4)

Color makes the review easier to scan, and the same screen still makes sense when the console cannot show color or the developer has turned color off. Major, minor, and patch changes keep the same words everywhere. Errors, warnings, and success use the same words everywhere.

**Why this priority**: Color is a reading aid. The review must stay usable in a plain terminal, a redirected log, and for developers who do not distinguish the chosen colors.

**Independent Test**: Run the same interactive update twice, once in a color console and once with color disabled. Confirm both runs offer the same choices and show the same versions, and that every colored state also has a word or symbol.

**Acceptance Scenarios**:

1. **Given** a color console, **When** a preview or review is shown, **Then** major changes are red, minor changes are yellow, patch changes are green, secondary detail is grey, errors are red, and warnings are yellow, and each of those states also shows a word (MAJOR, MINOR, PATCH, Error, Warning) or a symbol.
2. **Given** color is unavailable or turned off, **When** the same preview is shown, **Then** the words, versions, choices, and summary are unchanged and no meaning is lost.
3. **Given** any command that prints versions, **When** the same change size appears in the difference report, the proposal table, and the interactive review, **Then** it uses the same word and the same color.

---

### Edge Cases

- A package has a numeric prefix and an empty suffix (`VersionSuffix` or `PackageSuffix`). It is treated as having no suffix.
- A package has `PackageSuffix` or `VersionSuffix` and no numeric prefix in that pair, and no earlier version tag. It is excluded with a warning and is not given a made-up number.
- A project contains both `VersionPrefix` and `PackagePrefix`. The tool reads and writes `VersionPrefix` (and `VersionSuffix` when that suffix is set). `PackagePrefix` and `PackageSuffix` stay unchanged.
- A project contains `PackageVersion` or `Version` plus a later prefix/suffix pair. The single-value tag is the one written. The prefix and suffix tags stay unchanged.
- The winning tag is `PackagePrefix` or `VersionPrefix`, the new version includes a suffix, and the matching suffix tag is missing. The tool adds that suffix tag beside the prefix tag. It does not add a suffix tag for a single-value `PackageVersion` or `Version`.
- A follow-up bump keeps the dependent's own suffix even when the triggering package has a different suffix or none.
- Two dependencies ask for different bump sizes for the same package. The larger change size wins, and the package's own suffix is still kept unless the developer types a different version.
- The developer types a version lower than the current one. The tool warns, names the current and typed versions, and still allows it only when they confirm that earlier version.
- The developer types the same version the package already has. The package is treated as unchanged.
- The solution has no affected packages. The console says there is nothing to update and writes nothing.
- The saved snapshot is missing. The tool stops with a clear instruction to create the snapshot first, and writes nothing.
- A package name is not in the solution. The tool stops, names the unknown package, suggests close names when it has them, and writes nothing.
- The review is cancelled at the final question after some packages were accepted. Nothing is written.
- Output is redirected to a file. The text form is used, without color control codes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tool MUST treat a package version as a numeric prefix (`MAJOR.MINOR.PATCH`) plus an optional release suffix. A missing or empty suffix means a stable version.
- **FR-002**: The tool MUST read the first project tag that has a numeric version, in this order: `PackageVersion`, then `Version`, then `VersionPrefix` with optional `VersionSuffix`, then `PackagePrefix` with optional `PackageSuffix`. The tool MUST write the update only to that winning tag or tag pair and MUST leave every later version tag unchanged. It MUST NOT create an earlier tag when a later tag already holds the version.
- **FR-003**: When the developer sets an explicit version, the tool MUST write that prefix and that suffix. Including a suffix stores it. Omitting a suffix clears any previous suffix.
- **FR-004**: When the tool proposes a follow-up bump for a dependent package, it MUST change only the numeric prefix using the existing change-size rules, and MUST keep that package's current suffix.
- **FR-005**: A difference that changes only the suffix, with the same numeric prefix, MUST be reported as a version change and MUST be applicable.
- **FR-006**: The tool MUST warn when the requested version is an earlier release than the current one. The same numbers with a suffix are earlier than those numbers without a suffix. Clearing a suffix on the same numbers is not an earlier release. An earlier release MUST be applied only after the developer confirms it, or when they already asked to allow earlier versions.
- **FR-007**: Before writing, preview and difference output MUST show, for each affected package, the current prefix, the current suffix or "none", the proposed prefix, the proposed suffix or "none", the change size in words, and the reason.
- **FR-008**: A dry run MUST show that preview and MUST NOT change package files or the saved snapshot.
- **FR-009**: Interactive review MUST be available for setting explicit versions and for applying missing follow-up bumps.
- **FR-010**: Interactive review MUST show the named version changes first, then each affected package one at a time, including "N of M", the current and proposed prefix and suffix, and the reason.
- **FR-011**: For each package, the developer MUST be able to accept the proposal, type a version, or leave the package unchanged. Accept MUST be the initially focused choice.
- **FR-012**: A typed version MUST accept a numeric prefix with an optional release suffix. Invalid input MUST be rejected with the reason and an example of a valid version with and without a suffix, and the developer MUST be able to try again on the same package.
- **FR-013**: After the last package, the tool MUST show a summary of packages that will change and packages left unchanged, then ask once whether to apply the changes. No package file and no snapshot may be written before that answer is yes.
- **FR-014**: If the developer declines the final confirmation, or if nothing would change, the tool MUST write nothing and MUST say that nothing was written.
- **FR-015**: Color MUST reinforce meaning and MUST NOT be the only carrier of meaning. Major is red and the word MAJOR. Minor is yellow and the word MINOR. Patch is green and the word PATCH. Errors use the word Error. Warnings use the word Warning.
- **FR-016**: When the console cannot show color, color is turned off, or output is redirected, the tool MUST print the same information as plain text without color control codes.
- **FR-017**: The same change size MUST use the same word and the same color in the difference report, the proposal table, and the interactive review.
- **FR-018**: Packages that cannot be updated because they have no numeric prefix MUST be named, left unchanged, and MUST NOT block updates to the other packages.
- **FR-019**: The non-interactive update path MUST apply the same prefix and suffix results as interactive review would for the same accepted proposals.
- **FR-020**: After a confirmed apply, the saved snapshot MUST match the versions just written, including suffixes.

### Key Entities

- **Package**: A named project in the solution that has a version and may depend on other packages in the same solution.
- **Version**: A numeric prefix and an optional release suffix. A project stores it in the first tag that has a numeric version: `PackageVersion`, `Version`, `VersionPrefix` plus optional `VersionSuffix`, or `PackagePrefix` plus optional `PackageSuffix`.
- **Version change**: A move from one version to another, classified as major, minor, patch, suffix-only, or a move to an earlier release.
- **Proposal**: The version the tool suggests for one package, plus the reason (explicit request or follow-up from a dependency).
- **Review decision**: Accept the proposal, use a typed version, or leave the package unchanged.
- **Snapshot**: The last saved picture of package versions, including suffixes, used to see what changed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a solution of at least 20 packages that mixes single-value versions and prefix-plus-suffix versions, a developer can preview every affected prefix and suffix in one report before anything is written.
- **SC-002**: After a confirmed update, 100% of affected packages show the intended prefix and the intended suffix, and 100% of unaffected packages are unchanged.
- **SC-003**: A suffix-only change and a prefix-only change are each identified correctly in the difference report.
- **SC-004**: A developer can finish an interactive review of 10 affected packages, including at least one typed suffix, in one pass and in under 3 minutes without looking up how the prompts work.
- **SC-005**: Declining the final confirmation, cancelling a dry run, or leaving every package unchanged leaves 100% of package files and the saved snapshot unchanged.
- **SC-006**: With color turned off, a reviewer can still name the change size, the decision, and the resulting prefix and suffix for every package in the summary.
- **SC-007**: On the first attempt, at least 90% of developers in a short usability check choose the intended action (accept, type a version, or leave unchanged) without asking what the choices mean.

## Assumptions

- "Package prefix" means the numeric `MAJOR.MINOR.PATCH` version. "Package suffix" means the optional release label after a hyphen, such as `beta` or `rc.1`. In the project file those parts live in `PackageVersion`, `Version`, `VersionPrefix`/`VersionSuffix`, or `PackagePrefix`/`PackageSuffix`, and the first tag in that list that has a numeric version is the one the tool reads and writes.
- Follow-up bumps keep the dependent package's current suffix. A follow-up bump does not promote a package to stable and does not rename its suffix. The developer changes or clears a suffix by setting an explicit version, including by typing one during interactive review.
- Change-size rules stay as they are today: a major change on a package produces a minor follow-up on its dependents; a minor or patch change produces a patch follow-up. The largest required follow-up wins when several dependencies change.
- Interactive review is the existing optional review on explicit updates and on applying missing follow-up bumps. This feature defines that review's content, choices, color, and confirmation. It does not add a separate product.
- Versions that are not written in the project itself (for example a number inherited only from a shared property file) are out of scope. The tool updates versions it can read from the project.
- Build metadata after a plus sign is out of scope.
- A release suffix is a label, not a second numbering scheme the tool invents. The tool does not auto-increment `beta.1` to `beta.2`.
- Standard version ordering applies: a higher major, minor, or patch is later; the same numbers with a suffix come before the same numbers without a suffix; suffix labels compare in the usual dotted pre-release order (`beta.2` after `beta.1`).
- The people using the console are developers who already run this tool from a terminal. Prompts are short, one decision at a time, and the write happens only after an explicit yes.
- Color follows the mapping in FR-015 on every screen. No other colors are introduced for the same meanings.

## Git branch (branch-format preset)

When this project has the **branch-format** preset installed, the feature **git branch**
MUST be created via the always-on **branch-format** skill as `{type}/{ISO-week}-{slug}`
(e.g. `feature/33-speckit-branch-format`). Parameters come from context or the user.

This Spec Kit **feature directory** (`specs/NNN-slug`) remains independent of the git
branch name. Record the git branch in the Feature Branch field if useful; do not rename
the feature directory to match.
