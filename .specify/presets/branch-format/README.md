# Branch Format Preset

Append-only Spec Kit preset that **mandates** the pipeline `branch-format` skill for
git branches. It does **not** replace core Spec Kit `speckit.specify` guidance.

## Format

```text
{type}/{week}-{slug}
```

Example: `feature/33-speckit-branch-format`

- `type`: `feature` | `fix` | `chore` | `docs` | `refactor` | `test` | `spike`
- `week`: ISO week of year, zero-padded (`01`–`53`)
- `slug`: lowercase hyphenated short description

Spec Kit feature directories remain `specs/NNN-slug` (independent of the git branch).

## Package layout

```text
speckit-tools/presets/branch-format/
├── preset.yml
├── README.md
├── LICENSE
├── commands/
│   └── speckit.specify.append.md
└── templates/
    └── spec-addendum.md
```

## Install (local / catalog)

From a Spec Kit–initialized project:

```bash
specify preset add --dev /path/to/ai-dev-pipeline/speckit-tools/presets/branch-format
specify preset list
```

`agentic-tool apply` also best-effort installs this preset when `.specify/` is present.

## Verify / remove

```bash
specify preset list
# Confirm installed specify command still has core steps + append mandate
specify preset remove branch-format
```

## Critical

- Composition strategy **MUST** stay `append` in `preset.yml`.
- **Never** change this preset to `strategy: replace` — that would wipe core specify behavior.
- Agents MUST create/switch branches via the `branch-format` skill (see skill README / SKILL.md).
