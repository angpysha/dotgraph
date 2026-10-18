# Feature Specification: Write Package Versions to a Props File

**Feature Branch**: `feature/42-props-package-versions`

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "I would like one more feature. It should read from config all packages what we scanned and selected to versioning. And write it to some props files into item group as package version. Path should be as parameter in dotgraph setting file."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Write the saved package versions into a props file (Priority: P1)

A developer already has a saved list of the packages the scan kept for versioning. They save one props-file path in the dotgraph settings, then ask the tool to write those packages. The props file receives one item group, labeled `Dotgraph`, with one package-version entry for every package in that saved list. Each entry carries the package name and the version stored for it, including a release label when the saved version has one. Project versions and the saved list are not changed.

**Why this priority**: Other projects need one list of the internal package versions the team has already chosen. Writing that list is the outcome the developer asked for. Choosing the path, and being able to see or clear it, is what makes the write go to the right file.

**Independent Test**: Save a list of three packages at `1.0.0`, `1.2.0-beta.1`, and `2.0.0`. Save a props path that does not exist yet, inside a folder that does exist. Write the package versions. Confirm the new file has one `Dotgraph` item group with those three names and versions, ordered by name, and that the saved list and every project version are unchanged. Clear the path and write again. Confirm no further file is written.

**Acceptance Scenarios**:

1. **Given** the saved list contains `MyLib.Core` `1.2.0`, `MyLib.Abstractions` `1.0.0`, and `MyLib.Http` `1.5.0-beta.1`, and a props path has been saved, **When** the developer writes the package versions, **Then** the props file contains one item group labeled `Dotgraph` with those three packages, each with the version from the saved list, ordered `MyLib.Abstractions`, `MyLib.Core`, `MyLib.Http`.
2. **Given** no props path is saved, **When** the developer asks to write package versions, **Then** the tool says that no path is saved, writes no file, and leaves the saved list and project versions unchanged.
3. **Given** a props path is saved, **When** the developer asks which path will be used, **Then** the tool shows that path.
4. **Given** a props path is saved, **When** the developer clears it, **Then** the next write writes nothing, and the props file that already exists is not deleted.
5. **Given** the developer saves or replaces a props path, **When** that save finishes, **Then** the props file is not written yet and the saved package list is unchanged.
6. **Given** the same saved list and the same props file, **When** the developer writes package versions a second time, **Then** the props file is unchanged.
7. **Given** a successful write, **When** the developer looks at project versions and the saved package list, **Then** both are the same as before the write.
8. **Given** the scan excluded a project because it has no version, **When** the developer writes package versions, **Then** that project does not appear in the `Dotgraph` item group.

---

### User Story 2 - Update the tool's item group without disturbing the rest of the file (Priority: P2)

The props file may already exist and may contain other item groups. A later write finds the item group labeled `Dotgraph` and makes that group match the saved package list exactly. Packages added to the list appear. Packages removed from the list disappear. Changed versions are updated. Every other item group, and every package version outside the `Dotgraph` group, stays as it was.

**Why this priority**: A props file often holds other package versions the tool does not manage. Replacing the whole file would drop them. Leaving a removed package in the tool's group would keep a version the team no longer publishes.

**Independent Test**: Start from a props file that has a `Dotgraph` group for packages A and B, plus a separate item group for an unrelated package. Change the saved list so A has a new version, B is gone, and C is added. Write again. Confirm the `Dotgraph` group lists only A and C with the saved versions, and the unrelated group is byte-for-byte unchanged.

**Acceptance Scenarios**:

1. **Given** the props file has an item group other than `Dotgraph`, **When** the developer writes package versions, **Then** that other item group is unchanged.
2. **Given** the `Dotgraph` group lists A `1.0.0` and B `1.0.0`, and the saved list now has A `1.0.1` and C `2.0.0`, **When** the developer writes package versions, **Then** the `Dotgraph` group lists A `1.0.1` and C `2.0.0` and does not list B.
3. **Given** the props file does not exist and the folder named by the path does exist, **When** the developer writes package versions, **Then** the file is created with the `Dotgraph` item group and no other item group.
4. **Given** the props file already has a `Dotgraph` item group, **When** the developer writes package versions, **Then** that same group is updated and a second `Dotgraph` group is not added.
5. **Given** the same package name appears in an item group other than `Dotgraph`, **When** the developer writes package versions, **Then** the tool names that package, still writes the `Dotgraph` group, and does not change the other group.
6. **Given** the saved list has no packages, **When** the developer writes package versions, **Then** the `Dotgraph` group contains no entries, the tool says there were no packages to write, and content outside that group stays unchanged.

---

### Edge Cases

- The saved package list is missing. The tool explains that the list must exist first, writes nothing, and does not create a props file.
- The saved path is relative. It is resolved from the folder that contains the dotgraph settings file. An absolute path is used as saved.
- The folder that should contain the props file does not exist. The tool names that folder, writes nothing, does not create the folder, and leaves the saved path unchanged.
- The saved path is a folder, or it is the dotgraph settings file. The tool explains that, writes nothing, and leaves the saved path unchanged.
- The props file exists but cannot be read as a props file, or it cannot be written. The tool explains why, leaves that file unchanged, and leaves the saved list and project versions unchanged.
- A package version in the saved list includes a release label. The written entry uses that full version. The tool does not drop the label and does not invent one.
- The saved list and the current project files disagree. The props file follows the saved list. The write does not rescan projects and does not copy the unsaved project version.
- A package name differs only by letter case from another name. Both are written as stored. Ordering ignores letter case, and names that still tie keep the order stored in the saved list.
- The developer clears the path. The existing props file stays on disk. Later versioning actions do not update it.
- Saving a path, replacing it, or clearing it never writes the props file and never deletes it.
- An existing versioning action that updates project versions or the saved list does not write or update the props file. The developer writes the props file in a separate step.
- The developer writes, then removes a package from the saved list, then writes again. That package is gone from the `Dotgraph` group and remains in any other group where it was already listed.
- Comments or other content inside the `Dotgraph` group are not kept. After a write, that group contains only the current package-version entries. Content outside the group is kept.
- Output is redirected to a file. The messages for a missing path, a missing list, an unreadable props file, and a successful write stay understandable without color.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The developer MUST be able to save one props-file path in the dotgraph settings file, replace that path, clear it, and see the path currently saved. Until a path is saved, no props path is in effect.
- **FR-002**: Saving, replacing, or clearing the props path MUST NOT create, change, or delete the props file, and MUST NOT change the saved package list or any project version.
- **FR-003**: The developer MUST be able to write package versions as a separate step. That step MUST read the saved package list and MUST NOT rescan the solution or read versions from project files.
- **FR-004**: The write MUST include every package in the saved package list, and MUST NOT include a project the scan excluded from that list.
- **FR-005**: Each included package MUST appear once, as a package-version entry in a single item group labeled `Dotgraph`. The entry MUST state the package name and the version stored for that package. A release label that is part of the stored version MUST be included. Entries MUST be ordered by package name, ignoring letter case.
- **FR-006**: A later write MUST update the existing `Dotgraph` item group so that it matches the saved package list exactly. Packages that are new to the list MUST appear. Packages that left the list MUST disappear from that group. Changed versions MUST be updated. The write MUST NOT add a second `Dotgraph` item group.
- **FR-007**: Content outside the `Dotgraph` item group MUST be left unchanged, including other item groups and package versions that are not in the `Dotgraph` group.
- **FR-008**: When the props file does not exist and the folder that should contain it does exist, the write MUST create the file containing the `Dotgraph` item group.
- **FR-009**: When no path is saved, the saved package list is missing, the path's folder does not exist, the path is a folder, the path is the dotgraph settings file, the props file cannot be read, or the props file cannot be written, the tool MUST explain what is wrong, write nothing, and leave the saved path, the saved package list, and project versions unchanged.
- **FR-010**: A write MUST NOT change project version tags and MUST NOT change the saved package list.
- **FR-011**: Repeating a write with the same saved list and the same content outside the `Dotgraph` group MUST leave the props file unchanged.
- **FR-012**: When a package name written into the `Dotgraph` group already appears in another item group, the tool MUST name that package, still complete the write, and MUST NOT change the other group.
- **FR-013**: A relative props path MUST be resolved from the folder that contains the dotgraph settings file. An absolute props path MUST be used as saved.
- **FR-014**: When the saved list contains no packages, the write MUST leave the `Dotgraph` group empty and MUST tell the developer that there were no packages to write.
- **FR-015**: Existing actions that create or update the saved package list, or that change project versions, MUST keep their current behavior and MUST NOT write the props file.

### Key Entities

- **Saved package list**: The packages the scan kept for versioning, each with the name and version last saved. This is the only source for the props write.
- **Props path**: The single location, saved in the dotgraph settings file, where the package versions are written. It may be relative or absolute. No path means the write is off.
- **Dotgraph item group**: The one item group labeled `Dotgraph` in the props file. After a successful write it contains exactly the saved package list.
- **Package-version entry**: One package name and its full saved version, inside the `Dotgraph` item group.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer with a saved list of 20 packages can save a props path and produce a props file listing all 20 names and versions in one write, in under one minute.
- **SC-002**: In 100% of successful writes, every package in the saved list appears exactly once in the `Dotgraph` group, with the saved version, including any release label, and every package the scan excluded is absent.
- **SC-003**: A second write with an unchanged saved list leaves the props file unchanged in 100% of cases.
- **SC-004**: After one package version changes, one package is added, and one package is removed from the saved list, the next write shows those three differences in the `Dotgraph` group and leaves every other item group unchanged.
- **SC-005**: When no path is saved, or the path cannot be written, 100% of attempts leave every props file, the saved package list, and all project versions unchanged.
- **SC-006**: Saving, replacing, clearing, or viewing the props path changes no props file and no package version.
- **SC-007**: A developer can tell, by opening the props file, which item group the tool maintains, because that group is labeled `Dotgraph` and a later write updates that group rather than adding another.

## Assumptions

- The people using this already keep a saved package list. This feature does not scan the solution, does not create the first list, and does not change how project versions are chosen or stored.
- "Packages scanned and selected for versioning" means every package in that saved list. It does not mean only the packages changed by the latest bump. Projects the scan excluded are not written.
- The version written for a package is the version stored in the saved list. If a project file has a newer unsaved edit, the props file does not pick it up until the saved list is updated and the developer writes again.
- One path points at one props file. This feature does not write the same list to several files.
- The developer starts the write. Updating the saved list or bumping a project version does not update the props file by itself.
- The props file is an output other projects can consume. This feature does not read versions back from that file, and it does not take over package versions that live outside the `Dotgraph` group.
- The tool does not create missing folders and does not delete the props file when the path is cleared.
- The developer decides when to commit the props file. The tool does not commit it.
- Package names are written as stored. Ordering is alphabetical, ignoring letter case, so repeated writes stay stable.
- A release label is part of the version text. The write copies it and does not translate it into a separate field.

## Git branch (branch-format preset)

When this project has the **branch-format** preset installed, the feature **git branch**
MUST be created via the always-on **branch-format** skill as `{type}/{ISO-week}-{slug}`
(e.g. `feature/33-speckit-branch-format`). Parameters come from context or the user.

This Spec Kit **feature directory** (`specs/NNN-slug`) remains independent of the git
branch name. Record the git branch in the Feature Branch field if useful; do not rename
the feature directory to match.
