---
name: branch-format
description: >-
  Create or checkout git branches as {type}/{ISO-week}-{slug}. Mandatory when the
  Spec Kit branch-format preset is installed. Use at feature intake / before
  /speckit.specify when a branch is needed. Parameters from context or ask the user.
disable-model-invocation: true
---

# Branch Format Skill

Creates or checks out git branches in the pipeline naming format. Spec Kit feature
directories (`specs/NNN-slug`, `.specify/feature.json`) stay **independent** of the
git branch name.

**Contract**: `specs/010-speckit-branch-format/contracts/branch-name.md`  
**CLI**: `specs/010-speckit-branch-format/contracts/branch-format-skill-cli.md`

## Branch pattern

```text
{type}/{week}-{slug}
```

| Segment | Rule |
|---------|------|
| `type` | `feature` \| `fix` \| `chore` \| `docs` \| `refactor` \| `test` \| `spike` |
| `week` | ISO 8601 week-of-year, **zero-padded** two digits (`01`–`53`) |
| `slug` | Lowercase hyphenated short description |

Example: `feature/33-speckit-branch-format`

## Agent protocol (mandatory)

1. Infer `-Type` and `-Description` from conversation/session context when unambiguous.
2. If either is missing or ambiguous → **ask the user** (do not invent a type like `misc`).
3. Prefer `-DryRun` first to confirm the name; then run without `-DryRun` (and use
   `-AllowExisting` when re-entering an existing local branch).
4. **Never push** unless the human explicitly asks in that message.
5. Do **not** rename Spec Kit feature directories to match the git branch.
6. Do **not** auto-rename remotes that use a different scheme — report and ask the human.

This skill is **always-on** (all lanes: spike, micro, short, fast, full) after
`agentic-tool apply`. When the Spec Kit **branch-format** preset is installed, using
this skill for feature git branches is **mandatory**.

## Invoke

Requires **PowerShell Core** (`pwsh`) and `git`.

```powershell
# From pipeline catalog / AI_PIPELINE_HOME
$BF = 'core/skills/branch-format/scripts/create-branch.ps1'

# After apply into a target repo
$BF = '.agents/skills/branch-format/scripts/create-branch.ps1'
# Host projection (Cursor):
# $BF = '.cursor/skills/branch-format/scripts/create-branch.ps1'

pwsh $BF -Type feature -Description 'speckit branch format' -Week 33 -DryRun
pwsh $BF -Type feature -Description 'speckit branch format' -Week 33
pwsh $BF -Type feature -Description 'speckit branch format' -Week 33 -AllowExisting
```

Optional: `-Date yyyy-MM-dd` to derive ISO week (ignored if `-Week` is set).

## Outputs

- `BRANCH_NAME: {type}/{WW}-{slug}`
- Dry-run also prints `DRY_RUN: true`
- Success create/checkout prints `ACTION: created` or `ACTION: checked_out`
