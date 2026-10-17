# Feature Specification: Branch Diff Version Bump

**Feature Branch**: `feature/42-branch-diff-bump`

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "Support automatically increasing a package version, or making a proposal, from code changes against a compare branch (default main). A new command diffs the current files, finds packages whose code changed, bumps the version using the method that package already uses, then updates dependents and the saved graph. A separate command interactively edits only those changed packages and their dependency graph, and by default changes nothing."

## Clarifications

### Session 2026-10-17

- Q: What version does a code change get? → A: Propose a patch bump of the version on the compare branch, not the version in the current files. Show that proposal and the dependent bumps. Write only after the developer confirms. A preview writes nothing.
- Q: Which differences select a package? → A: Compare the current files, including edits that are not yet committed, with the tip of the compare branch. A package is selected when any of its files that the branch already knows about has changed, except a change that is only its version tag.
- Q: What happens to dependents when a version is edited? → A: Review code-changed packages first and recalculate dependents from the versions actually chosen, then review those dependents. The developer can still edit each dependent. This review is a separate command from the automatic proposal. The developer’s code changes already exist before either command runs. The review command changes nothing unless the developer chooses a version and confirms.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the version a code change would get (Priority: P1)

A developer has already changed code in one or more internal packages. They run the branch proposal and see which packages those code changes belong to. For each selected package the report shows the version stored on the compare branch, the version in the current files when it differs, and a proposed version that is one patch higher than the compare-branch version. The release label on the compare-branch version stays as it is. Packages whose only difference is the version tag are not selected. Nothing is written.

**Why this priority**: The developer asked to see what a code change is worth before any version is increased. A wrong package or a version taken from the current files instead of the compare branch publishes the wrong package.

**Independent Test**: On a compare branch, set one package to `1.4.2` and another to `2.0.0-beta.1`. In the current files, change a source file in the first package and set its version to `9.0.0`, change only the version tag of a third package, and leave a fourth package untouched. Preview the branch proposal. Confirm the first package is proposed as `1.4.3`, the second is proposed as `2.0.1-beta.1` only if its code changed, the third and fourth are not selected, and no project file or saved snapshot changes.

**Acceptance Scenarios**:

1. **Given** the compare branch has package A at `1.4.2` and the current files have A at `9.0.0` with a changed source file, **When** the developer previews the branch proposal, **Then** A is proposed as `1.4.3`, both `1.4.2` and `9.0.0` are visible, and no file is written.
2. **Given** the compare branch has package B at `2.0.0-beta.1` and a source file in B has changed, **When** the developer previews the branch proposal, **Then** B is proposed as `2.0.1-beta.1`.
3. **Given** the only difference in package C is its version tag, **When** the developer previews the branch proposal, **Then** C is not selected and is not given a new version.
4. **Given** a package has no file differences against the compare branch, **When** the developer previews the branch proposal, **Then** that package is not selected.
5. **Given** a selected package is at `1.4.2` on the compare branch and the current files are already at `1.4.3`, **When** the developer previews the branch proposal, **Then** the proposal is `1.4.3` and the package is shown as already at that version.
6. **Given** the developer has not chosen a compare branch, **When** they preview the branch proposal, **Then** the comparison uses `main`.

---

### User Story 2 - Apply the proposal and update dependents (Priority: P2)

The developer confirms the branch proposal. Each selected package is written to one patch above its compare-branch version, using the version tag that package already uses. Dependents that did not themselves change code are then offered the usual follow-up bump from their current version. After the versions are written, the saved snapshot matches the versions and the dependency links now in the solution. Declining the confirmation writes nothing.

**Why this priority**: Seeing the proposal has no publishing value until the developer can accept it and the dependents stay consistent with it.

**Independent Test**: Preview a proposal that selects one package and implies a follow-up on one dependent. Decline it and confirm nothing changed. Run it again, accept it, and confirm only those two versions changed and the saved snapshot matches them.

**Acceptance Scenarios**:

1. **Given** a preview that proposes A `1.4.2` → `1.4.3` and a follow-up for dependent D `3.0.0` → `3.0.1`, **When** the developer confirms, **Then** those versions are written and every other package stays as it was.
2. **Given** the same preview, **When** the developer declines, **Then** no package and no saved snapshot is changed.
3. **Given** a confirmed apply, **When** the write finishes, **Then** the saved snapshot shows the versions just written and the dependency links as they are in the solution now.
4. **Given** package A stores its version only as `PackageVersion` on the compare branch, and the current project uses that same tag, **When** the proposal is confirmed, **Then** only that tag is updated.
5. **Given** the current project stores the version in a different tag than a later unused tag, **When** the proposal is confirmed, **Then** the tag that already holds the version is updated and later version tags are not created or changed.
6. **Given** the proposed version is an earlier release than the version in the current files, **When** the developer has not confirmed that earlier release, **Then** that package is not written and the rest of the confirmed proposal still applies.
7. **Given** no package is selected and no follow-up is required, **When** the developer runs the branch proposal, **Then** the tool says there is nothing to update and writes nothing.

---

### User Story 3 - Edit the same set without changing anything by default (Priority: P3)

The developer runs a separate branch review after making code changes. It lists only the packages the branch diff selected, then the dependents affected by the versions the developer actually chooses. For each package the focused choice is to leave it unchanged, so running the review and accepting every default writes nothing. The developer can accept the proposal or type a version instead. When a chosen version changes how large the bump is, later dependents are recalculated before they are shown. Nothing is written until the developer confirms a summary that contains at least one change.

**Why this priority**: The automatic proposal applies one patch. The developer still needs a review that can raise or replace those versions, including the dependency graph, without the existing review of unrelated packages and without writing on accident.

**Independent Test**: Run the branch review on a change set of two code-changed packages and one dependent. Leave every package unchanged and confirm nothing is written. Repeat, type a major version for the first package, and confirm the dependent’s proposal is recalculated before it is shown. Decline the final confirmation and confirm nothing is written.

**Acceptance Scenarios**:

1. **Given** code changes that select two packages and would affect one dependent, **When** the developer opens the branch review, **Then** only those packages are offered, and packages outside that set are absent.
2. **Given** the branch review is open, **When** the developer looks at the choices for a package, **Then** the choices are Leave unchanged, Accept proposed, and Enter a version, with Leave unchanged focused first.
3. **Given** every package is left unchanged, **When** the review ends, **Then** the tool says nothing will be written and does not ask to apply an empty change.
4. **Given** the developer types a major version for a code-changed package, **When** a dependent is shown later, **Then** that dependent’s proposal has been recalculated from the typed version before the dependent is shown.
5. **Given** the developer leaves a code-changed package unchanged and its current version is still the compare-branch version, **When** its dependents are shown, **Then** they are not offered a follow-up caused by that package.
6. **Given** a code-changed package is already at the proposed patch and the developer leaves it unchanged, **When** its dependents are shown, **Then** they are still offered the follow-up for that patch, and the code-changed package is not written again.
7. **Given** the developer has chosen at least one version that differs from the current files, **When** the summary appears, **Then** it groups packages that will change and packages left unchanged and asks once whether to write. No file is written before the answer is yes.
8. **Given** the final question, **When** the developer says no, **Then** no package and no saved snapshot is changed.
9. **Given** the developer quits the review before the final confirmation, **When** the command ends, **Then** nothing is written.
10. **Given** five packages in the review, **When** the third is on screen, **Then** the review shows that this is package 3 of 5.
11. **Given** the same code changes, **When** the developer runs the existing interactive review of an explicit update or of missing follow-up bumps, **Then** that existing review is unchanged and is not limited to the branch-diff set.

---

### User Story 4 - Point the comparison at another branch (Priority: P4)

The developer can save a compare branch other than `main`. Later branch proposals and branch reviews use that saved branch until the developer changes it again. If they clear the setting, the comparison returns to `main`.

**Why this priority**: `main` is the right default. Teams that publish from another branch still need the same proposal without retyping the branch every time.

**Independent Test**: Save `release` as the compare branch, change a file that differs from `release` but not from `main`, and confirm the package is selected. Set the compare branch back to `main` and confirm that package is no longer selected.

**Acceptance Scenarios**:

1. **Given** no saved compare branch, **When** the developer asks which branch will be used, **Then** the answer is `main`.
2. **Given** the developer saves `release` as the compare branch, **When** they run a later branch proposal or branch review, **Then** the comparison uses `release`.
3. **Given** a saved compare branch, **When** the developer sets it back to `main`, **Then** the next comparison uses `main`.
4. **Given** the saved compare branch does not exist, **When** the developer runs a branch proposal or branch review, **Then** the tool names the missing branch, writes nothing, and does not change the saved setting.

---

### Edge Cases

- A file that the compare branch has never saved does not select a package, even when it sits inside that package’s project.
- A project file differs in both a source change and the version tag. The package is selected. The proposed number still comes from the compare branch, not from the edited tag.
- The compare branch and the current files use different version tags. The proposed number and release label come from the compare branch. The write updates the tag that already holds the version in the current files. Later unused version tags are left alone.
- The current files have no version tag, and the compare branch does. The write uses the tag that holds the version on the compare branch.
- A selected package has no readable numeric version on the compare branch, and it does exist there. The tool names it, leaves it unchanged, and still proposes the other packages.
- A package exists in the current solution and not on the compare branch. It is treated as new and proposed as `1.0.0`. The report says it is new. The branch review can replace that number.
- A package exists on the compare branch and not in the current solution. It is reported as removed and is not given a version.
- A changed project is not part of the saved package graph. It is named and left unchanged. It does not bump unrelated packages.
- A changed file belongs to no package. No package is selected because of that file.
- Two selected packages require different follow-up sizes for the same dependent. The larger follow-up is proposed. The dependent’s own release label is kept unless the developer types a different version.
- A follow-up keeps the dependent’s current release label. It does not copy the release label of the package that triggered it.
- The proposed version is lower than the version in the current files. The tool names both versions, warns that this is an earlier release, and writes it only after the developer confirms that earlier release.
- A selected package is already at the proposed version. It is not written again. Dependents are still offered the follow-up for the change from the compare-branch version to that current version.
- The developer types a version that is not a version. The review says what is wrong, shows an example with and without a release label, and asks again for the same package.
- The developer types the version the package already has. That package is treated as unchanged.
- The developer types a version during the branch review that is an earlier release than the current files. The review warns and accepts it only after the developer confirms that earlier release.
- The compare branch cannot be read, or the current folder is not a solution the tool already tracks. The tool explains what is missing and writes nothing.
- The saved snapshot is missing. The tool stops with the same instruction it already gives to create the snapshot first, and writes nothing.
- Output is redirected to a file. The report and the review stay understandable without color.
- The branch review and the branch proposal start from the same selected packages and the same patch proposals for those packages.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tool MUST remember a compare branch. Until the developer saves a different one, that branch MUST be `main`.
- **FR-002**: The developer MUST be able to save a different compare branch, set it back to `main`, and see which branch will be used. A missing compare branch MUST stop the command with that branch named, write nothing, and leave the saved setting unchanged.
- **FR-003**: The branch proposal and the branch review MUST compare the current files, including edits that are not yet committed, with the tip of the compare branch.
- **FR-004**: A package MUST be selected only when at least one of its files that the compare branch already knows about differs from that branch. A difference that is only the package’s version tag MUST NOT select it. A file the compare branch has never saved MUST NOT select it.
- **FR-005**: For a selected package that exists on the compare branch, the proposed version MUST be one patch above the numeric version on that branch, and MUST keep that branch’s release label. The version in the current files MUST NOT be the base of that proposal.
- **FR-006**: The proposal and the review MUST show, for each selected package, the compare-branch version, the current version when it differs, the proposed version, the change size in words, and the reason. A package already at the proposed version MUST be shown as needing no write.
- **FR-007**: A preview MUST show that report and MUST NOT change package files or the saved snapshot.
- **FR-008**: The branch proposal MUST write only after the developer confirms. Declining MUST write nothing. When nothing would change, the tool MUST say so and write nothing.
- **FR-009**: A confirmed write MUST update the version tag that already holds the package’s version. It MUST use the first tag that has a numeric version, in this order: `PackageVersion`, then `Version`, then `VersionPrefix` with optional `VersionSuffix`, then `PackagePrefix` with optional `PackageSuffix`. It MUST NOT create or change a later version tag. The number and release label written MUST be the confirmed proposal, which for a selected package starts from the compare branch.
- **FR-010**: After the selected packages are decided, the tool MUST propose follow-up bumps for dependents using the current change-size rules. A major change produces a minor follow-up. A minor or patch change produces a patch follow-up. The largest follow-up wins. A follow-up MUST keep the dependent’s own release label. A selected package that the developer leaves unchanged, while its current version is still the compare-branch version, MUST NOT cause a follow-up. A selected package that is already at its proposed version MUST still cause that follow-up and MUST NOT be written again.
- **FR-011**: For a dependent that was not itself selected, the follow-up MUST start from the version in the current files. For a selected package, the base MUST remain the compare-branch version.
- **FR-012**: After a confirmed write of at least one version, the saved snapshot MUST match the versions just written and the dependency links present in the solution. When nothing is written, the saved snapshot MUST stay unchanged.
- **FR-013**: The branch review MUST be a separate command from the branch proposal and from the existing interactive review. It MUST offer only selected packages and dependents affected by the versions chosen in that review.
- **FR-014**: In the branch review, each package MUST offer Leave unchanged, Accept proposed, and Enter a version, with Leave unchanged focused first. A package MUST be shown only after the packages it depends on in this review have been decided. The screen MUST show which package this is out of how many.
- **FR-015**: When the developer accepts or types a version, later follow-up proposals MUST be recalculated from that choice before those dependents are shown. Leave unchanged MUST NOT count as a bump.
- **FR-016**: The branch review MUST write nothing when every package is left unchanged, when the developer quits before the final confirmation, or when the developer declines the final confirmation. A final confirmation MUST be asked only when at least one package would change, and nothing MAY be written before that answer is yes.
- **FR-017**: A typed version MUST accept a numeric version with an optional release label. Invalid input MUST be rejected with the reason and an example, and the developer MUST be able to try again on the same package.
- **FR-018**: When a proposed or typed version is an earlier release than the version in the current files, the tool MUST warn and MUST write that earlier release only after the developer confirms it. The same numbers with a release label are earlier than those numbers without one. Clearing a release label on the same numbers is not an earlier release.
- **FR-019**: Packages that cannot be versioned MUST be named, left unchanged, and MUST NOT block the other packages. This includes a selected package with no numeric version, a changed project that is not in the package graph, and a package that was removed.
- **FR-020**: A package that exists in the current solution and not on the compare branch MUST be proposed as `1.0.0` and MUST be described as new. The branch review MUST allow that proposal to be replaced or left unchanged.
- **FR-021**: The existing explicit update, the existing follow-up sync, and their interactive reviews MUST keep their current behavior. The branch proposal and the branch review MUST NOT replace them.
- **FR-022**: Change size MUST use the same words already used for a major, minor, and patch change. Color MAY reinforce those words and MUST NOT be the only carrier of meaning. Redirected output MUST remain understandable without color.

### Key Entities

- **Compare branch**: The saved branch the current files are compared with. It is `main` until the developer saves another.
- **Selected package**: A package in the saved graph whose known files differ from the compare branch for a reason other than the version tag alone.
- **Branch proposal**: The patch version offered for a selected package, starting from that package’s version on the compare branch, plus any follow-up offered to dependents.
- **Current version**: The version stored in the current project files.
- **Compare-branch version**: The version stored for that package on the compare branch.
- **Follow-up**: A bump offered to a dependent because a package it depends on is actually getting a new version.
- **Branch review decision**: Leave the package unchanged, accept the proposal, or use a typed version.
- **Saved snapshot**: The last saved picture of package versions and dependency links. It is updated only after a confirmed write.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a solution of at least 20 packages, a developer can see every package selected by code changes, and the patch proposed from the compare branch, in one report before anything is written.
- **SC-002**: For 100% of selected packages that exist on the compare branch, the proposed version is exactly one patch above that branch’s version and keeps that branch’s release label, even when the current files show a different version.
- **SC-003**: A version-tag-only edit is absent from the selected set in 100% of cases, and an uncommitted edit to a known source file selects its package.
- **SC-004**: Declining confirmation, previewing, quitting the review, or leaving every reviewed package unchanged leaves 100% of package files and the saved snapshot unchanged.
- **SC-005**: After a confirmed apply, 100% of written packages match the confirmed versions, dependents that were not part of the confirm stay unchanged, and the saved snapshot matches the result.
- **SC-006**: A developer can finish a branch review of 10 packages, including one typed version, in one pass and in under 3 minutes, and can complete it by accepting every default without writing a file.
- **SC-007**: When a code-changed package is raised from a patch proposal to a major version, 100% of its later dependents show a recalculated follow-up before the developer answers them.
- **SC-008**: Changing the saved compare branch changes the selected set on the next run, and a missing branch writes nothing in 100% of attempts.

## Assumptions

- The people using this are developers who already maintain a solution of internal packages and already have a saved snapshot. This feature does not create the first snapshot and does not publish packages.
- "Patch" means the third numeric part of the version increases by one. `1.4.2` becomes `1.4.3`. `2.0.0-beta.1` becomes `2.0.1-beta.1`. The tool does not invent a new release label and does not turn `beta.1` into `beta.2` by itself.
- Change-size rules stay as they are today: a major change produces a minor follow-up, and a minor or patch change produces a patch follow-up. The largest follow-up wins.
- The version number for a selected package is read from the compare branch. The tag that is written is the tag the current project already uses, judged by the existing order: `PackageVersion`, then `Version`, then `VersionPrefix` and `VersionSuffix`, then `PackagePrefix` and `PackageSuffix`.
- A package that is not on the compare branch is new. Its proposal is `1.0.0` rather than a patch of a missing version. The developer can replace that number in the branch review or decline it.
- Follow-ups for packages that were not selected use the version in the current files as their starting point. They are not reset to the compare branch.
- "By default the review changes nothing" means Leave unchanged is the focused choice, and files are written only after the developer both chooses a real change and confirms the summary.
- The branch proposal’s confirmation is one yes-or-no for the whole proposal, plus a separate confirmation for any earlier release. The branch review is the only place that edits packages one by one.
- Files the compare branch has never saved are ignored when selecting packages. A brand-new file selects a package only after it is saved into the branch history.
- Projects that are not packages in the saved graph, including projects that have no version, are reported and not bumped.
- The existing explicit update and the existing follow-up sync, including their interactive reviews, stay as they are. Those reviews still focus Accept proposed first.
- Versions that are not stored in the project itself are out of scope. Build metadata after a plus sign is out of scope.
- The same version ordering as today applies: a higher major, minor, or patch is later; the same numbers with a release label come before the same numbers without one.

## Git branch (branch-format preset)

When this project has the **branch-format** preset installed, the feature **git branch**
MUST be created via the always-on **branch-format** skill as `{type}/{ISO-week}-{slug}`
(e.g. `feature/33-speckit-branch-format`). Parameters come from context or the user.

This Spec Kit **feature directory** (`specs/NNN-slug`) remains independent of the git
branch name. Record the git branch in the Feature Branch field if useful; do not rename
the feature directory to match.
