---
name: project-intake
description: >-
  Greenfield project intake before adapt. Ensures PROJECT.md exists with Vision and Stack
  sections. On empty repos, ask the human structured questions, write PROJECT.md, then
  proceed to code-search and stack-selector. Available from install (pre-apply).
disable-model-invocation: true
---

# project-intake

**Step 0 of `.agents adapt`.** Run before code-search when the repo is greenfield or
`PROJECT.md` is missing/incomplete.

## When to run

| Condition | Action |
|-----------|--------|
| `PROJECT.md` missing | **Stop adapt** — run intake (ask questions → write file) |
| `PROJECT.md` incomplete (no Vision or Stack) | **Stop adapt** — ask to fill gaps |
| `PROJECT.md` OK + code present | Skip intake → code-search |
| `PROJECT.md` OK + **empty repo** | Use PROJECT.md stack hints as primary signals for stack-selector |

Check mechanically:

```powershell
pwsh .agents/skills/project-intake/scripts/ensure-project-md.ps1
# or after apply: pwsh .cursor/skills/project-intake/scripts/ensure-project-md.ps1
```

Exit `0` = ready; `1` = missing; `2` = incomplete; `3` = greenfield (empty repo, brief OK).

## Questions to ask (when PROJECT.md does not exist)

Ask in one structured form (use `AskQuestion` when available). Minimum required answers:

1. **Project name** — short title (becomes `#` heading and `pipeline.manifest.json` `project.name`).
2. **Vision** — one paragraph: users, problem, success criteria.
3. **Stack** — languages, UI/framework, platforms, data store, dependency manager.
4. **CI/CD** (optional) — e.g. Azure DevOps, GitHub Actions, none yet.
5. **Tracker / PR** (optional) — beads, GitHub issues, Azure DevOps work items.

Do **not** proceed to code-search/stack-selector until Vision and Stack are captured in
`PROJECT.md`.

## Write PROJECT.md

Copy structure from `templates/PROJECT.md.template` (in this skill or
`core/templates/PROJECT.md.template`). Replace placeholders with human answers.

After writing:

```powershell
pwsh .agents/skills/project-intake/scripts/ensure-project-md.ps1
```

Update `pipeline.manifest.json`:

```json
"project": {
  "name": "MyApp",
  "brief": "PROJECT.md",
  "default_lane": "full"
}
```

## Spec Kit constitution (from PROJECT.md)

`PROJECT.md` is the human brief; the Spec Kit **constitution** is its machine-checkable
counterpart. Once `PROJECT.md` is ready and Spec Kit is initialized
(`specify init . --integration cursor`), run **`/speckit.constitution`** seeded from the
`PROJECT.md` Vision + principles to create `.specify/memory/constitution.md`. All downstream
phases enforce it. See `skills/spec-kit/SKILL.md`. Record `spec_kit.enabled: true` in the
manifest.

## Handoff to adapt

Once `ensure-project-md.ps1` exits `0`:

1. **mcp-codebase-search** — `list_files` + `get_codebase_stats` + targeted
   `search_codebases` (e.g. "entry point", "database migrations", "SwiftUI app").
2. **Semantic MCP** — codesearch / configured primary when available.
3. **Filesystem globs** — `*.csproj`, `pubspec.yaml`, `Package.swift`, etc.
4. **`PROJECT.md` Stack** — primary on greenfield.
5. **`/speckit.constitution`** — seed from `PROJECT.md` once Spec Kit is initialized.

Record `adapt.code_search_source` in recommendation: `codesearch` | `mcp-codebase-search` | `filesystem` | `project-brief`.

## Re-intake

Human may edit `PROJECT.md` anytime. On `Run .agents adapt --update`, re-read the brief;
do not overwrite without asking unless sections are empty.

## Constraints

- Never invent stack choices — ask when unclear.
- No secrets in `PROJECT.md`.
- `PROJECT.md` is human-editable; adapt recommendations can be overridden via manifest
  (`packs_extra`, `agents_extra`).
