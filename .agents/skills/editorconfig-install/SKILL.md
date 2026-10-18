---
name: editorconfig-install
description: >-
  Interactive EditorConfig installer for multi-stack repos. Detects C#, Flutter/Dart,
  Rust, React, Angular, Svelte, and TypeScript signals; human picks stacks; writes a
  composed .editorconfig at repo root. Use during adapt or early Phase 7 setup.
---

# editorconfig-install

**Interactive** skill — always confirm stack selection with the human before writing files.

Installs a composed **`.editorconfig`** at the repo root from curated templates for:

| Stack id | Covers |
|----------|--------|
| `csharp` | C# / .NET (`dotnet format`, analyzers) |
| `flutter` | Dart + Android/iOS/Windows/macOS native plugin folders (Kotlin, Swift, Gradle) |
| `rust` | Rust / rustfmt baseline |
| `react` | React JS/TS/TSX |
| `angular` | Angular TS + HTML templates |
| `svelte` | Svelte / SvelteKit |
| `typescript` | Generic TS/Node when no specific UI framework |

## When to use

| When | Who |
|------|-----|
| After **`agentic-tool apply`** / before first implementation | Coordinator or developer |
| Repo has **no** `.editorconfig` or incomplete sections | Human requests style baseline |
| **Multi-stack** monorepo (e.g. .NET API + React SPA) | Pick multiple stacks |

## Interactive workflow (mandatory)

1. **Detect** — run detect-only; show the human a table of detected vs available stacks.
2. **Confirm** — human selects stacks (comma-separated ids or menu numbers). Do not skip.
3. **Install** — run installer with confirmed `-Stacks` (or `-Interactive` in terminal).
4. **Report** — cite `.agents/editorconfig-install-report.json` (stacks + templates used).

### Step 1 — detect

```powershell
$EC = '.cursor/skills/editorconfig-install/scripts/install-editorconfig.ps1'
pwsh $EC -DetectOnly
```

Present results like:

```text
Detected: csharp, react
Available: csharp, flutter, rust, react, angular, svelte, typescript
Recommend: csharp, react (detected) + ask if flutter/rust/angular/svelte/typescript needed
```

### Step 2 — human confirms

Ask explicitly:

> Which EditorConfig stacks should we install?  
> Options: csharp, flutter, rust, react, angular, svelte, typescript  
> Detected: {list}. Reply with ids (e.g. `csharp,react`) or `all-detected`.

### Step 3 — install

```powershell
# Confirmed selection (non-interactive — preferred for agents)
pwsh $EC -Stacks csharp,react

# Or terminal interactive menu (human at keyboard)
pwsh $EC -Interactive

# Existing .editorconfig — merge new sections only
pwsh $EC -Stacks svelte -Merge

# Replace entire file (human must approve)
pwsh $EC -Stacks csharp,flutter -Force
```

## Outputs

| File | Purpose |
|------|---------|
| `.editorconfig` | Composed EditorConfig at repo root (`root = true` in base section) |
| `.agents/editorconfig-install-report.json` | Audit trail: stacks, templates, detected signals |

## Stack notes

### Flutter (all platforms)

One **Dart** section applies to Android, iOS, Windows, macOS, Linux, and Web — Flutter UI code is Dart.
The `flutter-platforms` template adds Kotlin/Swift/Gradle rules for **native plugin** folders only.

Pair with `dart format` / `flutter analyze` (see `flutter-bloc` pack).

### C#

Pair with **`dotnet-format`** skill after 7.4. EditorConfig drives `dotnet format` and analyzers.

### Front-end (React / Angular / Svelte)

EditorConfig sets indent/EOL baseline; **Prettier/ESLint** may still be added separately.
`typescript` stack is included automatically via react/angular/svelte catalog entries.

## Constraints

- **Human confirmation required** before `-Stacks` or `-Force`.
- Default: **fail** if `.editorconfig` exists (use `-Merge` or `-Force`).
- Do not paste full `.editorconfig` in chat — cite report path.
- Secrets never belong in EditorConfig.

## Extend catalog

Templates live in `templates/*.editorconfig`; register stacks in `catalog.json`.
