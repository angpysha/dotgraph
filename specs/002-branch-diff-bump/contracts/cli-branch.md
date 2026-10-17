# Contract: Branch commands

Three new commands. `diff`, `sync`, `update`, and their `--interactive` reviews are unchanged: Accept proposed stays the focused choice there.

Renderer stays Spectre.Console. Change-size words stay MAJOR, MINOR, PATCH, and SUFFIX, with the same colors as [the existing review contract](../../001-prefix-suffix-console/contracts/cli-review.md). Color is never the only signal. `NO_COLOR` and redirected stdout stay plain text.

## `dotgraph compare-branch`

No argument: print the saved branch name. Missing property prints `main`. Exit 0. Does not create `.dotgraph.json`.

`dotgraph compare-branch <name>`: store that name and print it. Exit 0. Does not check that the branch exists. Does not rescan packages.

Empty name: print Error, leave the file unchanged, exit 1.

Missing `.dotgraph.json`: print the existing “run `dotgraph init` first” error, exit 1.

## `dotgraph propose`

Prints one report before any write.

For each selected package: name, compare-branch version, live version when it differs, proposed version, change word, and the reason (`code changed` or `new package`). A package already at the proposal is marked already current.

Then follow-ups, each with live version, proposed version, change word, and the dependency reason.

Then removed packages and skipped packages, as warnings, with no proposed version.

`--dry-run`: print the report, do not ask, write nothing, exit 0.

Without `--dry-run`:

1. For each proposal that is an earlier release than the live version, warn with both versions and ask. No on that question drops only that package. `--force` accepts these without the extra question.
2. If nothing remains to write, print `Nothing will be written.` and do not ask. Exit 0.
3. Otherwise one yes/no: apply the remaining set. No writes before yes.
4. No: print that nothing was written. Exit 0. Files and snapshot unchanged.
5. Yes: write versions, then refresh the snapshot so it matches the solution. Exit 0.

A missing branch, a missing repository, or a missing snapshot: Error, write nothing, exit 1. The saved branch name is not cleared.

## `dotgraph review`

Separate from `propose` and from `update --interactive` / `sync --interactive`.

1. Same selected set and the same starting proposals as `propose`.
2. Selected packages first. A package appears only after selected dependencies that are also in this review have been answered. Then pure dependents. Heading shows `Package N of M`.
3. Choices, Leave unchanged focused first:
   - Leave unchanged
   - Accept proposed
   - Enter a version
4. Invalid version: `Invalid version. Example: 1.2.3 or 1.2.3-beta.1`, ask again on the same package.
5. A typed version equal to the live version counts as Leave unchanged.
6. An earlier release warns and asks, unless `--force`.
7. After an accept or a typed version, proposals not yet shown are rebuilt before the next package. Leave unchanged at the compare-branch version does not rebuild dependents from that package. A package already at the proposed patch still feeds that patch into later dependents.
8. Summary groups “Will change” and “Left unchanged”.
9. Ask once only when “Will change” is non-empty. No writes before yes.
10. Empty set, quit, or no: `Nothing will be written.` Exit 0. No file and no snapshot change.
11. Yes: same write and snapshot refresh as `propose`. Exit 0.

Packages outside the selected set and their follow-ups are not shown.

## Exit codes

| Result | Code |
|---|---|
| Printed, applied, nothing to do, user declined, or user left the review | 0 |
| Missing snapshot, missing repository, missing branch, empty branch name, write or save failure | 1 |

## Sample report

```text
Compare branch: main

Selected:
  MyLib.Core     branch 1.4.2   current 9.0.0   → 1.4.3   PATCH   code changed
  MyLib.Extra    branch (none)  current 0.1.0   → 1.0.0   MAJOR   new package

Follow-ups:
  MyLib.Http     3.0.0 → 3.0.1   PATCH   depends on MyLib.Core

Warnings:
  MyLib.Legacy   removed
  MyLib.Broken   no numeric version on main
```

`9.0.0` → `1.4.3` is an earlier release and needs the extra confirm unless `--force`.
