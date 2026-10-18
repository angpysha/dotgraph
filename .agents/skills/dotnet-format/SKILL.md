---
name: dotnet-format
description: >-
  Run dotnet format after Phase 7.4 (write code). Applies solution-wide formatting
  (whitespace, style, analyzers) before unit tests and dev gate. Use on every .NET task.
disable-model-invocation: true
---

# dotnet-format

Run **immediately after step 7.4 (Write code)** and before 7.5 (unit tests).

## When to run

| Step | Action |
|------|--------|
| **7.4** | Write code per file map |
| **→ this skill** | `dotnet format` — fix style/whitespace/analyzers |
| **7.5** | Unit tests |
| **7.7** | Re-run if analyzers still warn; optional `-Verify` before handoff |

## Commands

From repo root (PowerShell Core):

```powershell
$Fmt = '.cursor/skills/dotnet-format/scripts/dotnet-format.ps1'

# Apply formatting (default — after 7.4)
pwsh $Fmt

# Check only — fail if unformatted (before 7.8 / PR)
pwsh $Fmt -Verify
```

## What it does

1. Resolves the solution (`.sln` / `.slnx`) or `.csproj` at repo root.
2. Runs `dotnet format` (apply) or `dotnet format --verify-no-changes` (verify).
3. Exits non-zero on failure — loop back to **7.4** and fix.

## Manifest override (optional)

Add to `pipeline.manifest.json` after adapt:

```json
"format": { "command": "dotnet format MyApp.sln" }
```

If omitted, the script auto-detects `*.sln` / `*.slnx` / `*.csproj`.

## Checkpoint

Save formatter output when verbose (optional, token-saving):

```powershell
dotnet format 2>&1 | pwsh .cursor/skills/checkpoint/scripts/save-artifact.ps1 -Session <session> -ArtifactRel gates/dotnet-format.log -Mode --stdin
```

## Constraints

- Run after **every** 7.4 that touches `.cs` files.
- Do not skip for "small" diffs — keeps TL review focused on logic.
- If format changes files, re-run `build.command` before 7.5.
