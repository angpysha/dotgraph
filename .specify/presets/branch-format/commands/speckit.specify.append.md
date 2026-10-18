## Mandatory: branch-format skill for git branches

When this preset is installed, agents **MUST** create or switch the feature **git branch**
using the **branch-format** skill — do **not** invent `NNN-slug` (or other) branch names by hand.

### Branch name format

```text
{type}/{week}-{slug}
```

- **type** (required): `feature` | `fix` | `chore` | `docs` | `refactor` | `test` | `spike`
- **week**: ISO week-of-year, zero-padded two digits (`01`–`53`)
- **slug**: lowercase hyphenated short description

Example: `feature/33-speckit-branch-format`

### How to run

1. Infer `type` and short description from conversation context when unambiguous.
2. If either is missing or ambiguous → **ask the user** (do not invent).
3. Prefer a dry-run, then create/checkout:

```powershell
# Catalog / pipeline home
pwsh core/skills/branch-format/scripts/create-branch.ps1 -Type <type> -Description "<text>" [-Week N] [-DryRun]

# After agentic-tool apply / host sync
pwsh .agents/skills/branch-format/scripts/create-branch.ps1 ...
# or
pwsh .cursor/skills/branch-format/scripts/create-branch.ps1 ...
```

### Spec directory independence

Spec Kit feature directories stay under `specs/NNN-slug` (sequential) and
`.specify/feature.json`. The **git branch name MUST NOT** be forced to equal the
feature directory name.

### Out of scope

- Do not auto-push.
- Do not auto-rename remote branches that use a different naming scheme.
