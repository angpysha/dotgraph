---
name: spec-kit-packages
description: >-
  Install, update, search, and catalog Spec Kit presets, extensions, and workflows
  using the official specify CLI (local --dev, community marketplace, enterprise
  catalogs). Use when managing Spec Kit packages from a pipeline package list or
  when agents need correct specify commands from github/spec-kit docs.
disable-model-invocation: true
---

# Spec Kit Packages

Official toolkit: [github/spec-kit](https://github.com/github/spec-kit).  
This skill curates **install / update / catalog** commands only — not the full SDD phase map
(see `spec-kit` skill for `/speckit.*` phases).

Pipeline package list: `speckit-tools/packages.yml` — used packages with
`source: local | community | enterprise`.

## Pipeline runner (`agentic-tool`)

Prefer the catalog driver (merge-only; never prunes unlisted workspace packages):

```bash
agentic-tool speckit-packages list [--target DIR] [--file PATH]
agentic-tool speckit-packages install [--target DIR] [--file PATH] [--id ID]
agentic-tool speckit-packages update [--target DIR] [--file PATH] [--id ID]
```

Default `--file` is `{AI_PIPELINE_HOME}/speckit-tools/packages.yml`.
On batch install/update: continue after failures; print per-entry STATUS; exit non-zero if any failed.

## Sources

| Source | Meaning | Typical Spec Kit action |
|--------|---------|-------------------------|
| **local** | Path in this catalog / monorepo | `specify <kind> add --dev <path>` |
| **community** | Default / community marketplace | `specify <kind> add <id>` / search |
| **enterprise** | Org-hosted catalog URL | `specify <kind> catalog add …` then `add <id>` |

Kinds map to Spec Kit: **preset**, **extension**, **workflow** (use “bundle” only if the
package list defines it as a composition of these).

## Presets

Docs: [presets README](https://github.com/github/spec-kit/blob/main/presets/README.md),
[presets reference](https://github.com/github/spec-kit/blob/main/docs/reference/presets.md).

```bash
specify preset search
specify preset add <preset-id>                 # community / catalog
specify preset add --dev /path/to/preset       # local
specify preset list
specify preset info <preset-id>
specify preset remove <preset-id>
specify preset resolve <template-name>

# Enterprise / custom catalogs (project: .specify/preset-catalogs.yml)
specify preset catalog list
specify preset catalog add <url> --name <name> --install-allowed
specify preset catalog remove <name>
```

Composition strategies for presets: `replace` (default), `prepend`, `append`, `wrap`.
Pipeline `branch-format` preset MUST use **append**.

Env (presets): `SPECKIT_PRESET_CATALOG_URL` can override catalog stack; GitHub-hosted private
catalogs may need `GH_TOKEN` / `GITHUB_TOKEN`.

## Extensions

Docs: [extensions user guide](https://github.com/github/spec-kit/blob/main/extensions/EXTENSION-USER-GUIDE.md),
[extensions reference](https://github.com/github/spec-kit/blob/main/docs/reference/extensions.md).

```bash
specify extension search
specify extension add <name-or-path>
specify extension add --dev /path/to/extension
specify extension add --from <url> <name>
specify extension list
specify extension remove <name>

# Enterprise / custom catalogs (project: .specify/extension-catalogs.yml)
specify extension catalog list
specify extension catalog add <url> --name <name> --install-allowed
specify extension catalog remove <name>
```

Env: `SPECKIT_CATALOG_URL` overrides the default upstream extension catalog JSON
(org catalog pattern for enterprise).

## Workflows

Docs: [workflows README](https://github.com/github/spec-kit/blob/main/workflows/README.md).

```bash
specify workflow add <id-or-path>
specify workflow add --dev /path/to/workflow   # when supported by installed Spec Kit
specify workflow list
specify workflow catalog list
specify workflow catalog add <url> --name <name>
specify workflow catalog remove <index>
```

Pipeline lane packages live under `core/workflows/pipeline-*` and are also registered on
`agentic-tool apply`.

## Agent rules

1. Prefer the pipeline **package list** `speckit-tools/packages.yml` when installing “used tools”.
2. Never invent a parallel installer — always call `specify` (via `agentic-tool` when available).
3. Local entries → `--dev` + path. Community → id from search/catalog. Enterprise → ensure
   catalog registered (`catalog add` / env) then install by id.
4. **Merge only**: install/update listed packages; **do not** remove Spec Kit packages that are
   already on the workspace but missing from `packages.yml`.
5. On batch install/update: **continue** after failures; report each entry; non-zero exit if any
   failed.
6. After install, verify with `specify preset list` / `extension list` / `workflow list` as
   appropriate.
7. Do not change a preset’s composition strategy from **append** to **replace** for
   `branch-format`.
8. Cite official docs URLs above rather than pasting full upstream manuals into chat.

## Verify Spec Kit CLI

```bash
specify version
# Requires Python 3.11+ and uv for typical installs:
# uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
```
