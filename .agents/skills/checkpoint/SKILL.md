---
name: checkpoint
description: >-
  Read/write hierarchical SDLC checkpoints in _code_agent/{session}/. Save artifacts to
  disk (save/read/ls/link) instead of pasting large content in chat. JSON source of truth;
  TOON projections for token-efficient resume. Commands: start, done, save, read, ls, link,
  log, input, output, gate, resume, view, metrics.
disable-model-invocation: true
---

# Checkpoint Skill

Local, resumable memory for pipeline progress. Design: `docs/reference/agent-checkpoints.md`.

**Token rule:** persist bulky content as **files under `artifacts/`** and pass **paths** in
chat. Use `resume` / `ls` / `view` (metadata) / `read --max-chars` — never paste full
build logs, code plans, or gate output into the conversation.

Storage is **JSON** (source of truth) plus **TOON** projections for token-efficient resume
in a **new chat**.

Session path: `_code_agent/{YYYYMMDD-slug}/`

## Hierarchy

```
_code_agent/{session}/
  state.json                 # snapshot + artifacts_index (paths + bytes only)
  events.jsonl
  artifacts/                 # session files — write here, not in chat
    sdlc/                    # working SDLC docs (REQ, SDD, plan, API, TEST, ADR)
      requirements/
      design/
      api/
      adr/
      test-reports/
      closeout/
    tasks/{task-id}/code-plan.md
    spike/
    gates/
    ado/                     # Azure DevOps TOON queries (optional)
  steps/{phase}/{step}/
    step.json                # includes artifact path refs
    input.md | output.md | logs.md   # short summaries only
  views/resume.toon          # TOON projection for resume
```

## Commands

Requires **PowerShell Core** (`pwsh`). From repo root:

```powershell
$CP = '.cursor/skills/checkpoint/scripts/checkpoint.ps1'
# or after minimal install: $CP = '.agents/scripts/checkpoint.ps1'

# Step lifecycle
pwsh $CP start  <session> <phase> <step> <agent> "<short summary>"
pwsh $CP input  <session> <phase> <step> "<brief — paths to artifacts, not full docs>"
pwsh $CP log    <session> <phase> <step> "<one-line log; pipe build output to a file instead>"
pwsh $CP output <session> <phase> <step> "<short result + artifact paths>"
pwsh $CP done   <session> <phase> <step> "<summary>" [artifact-rel-path...]

# Artifact files (token-efficient)
pwsh $CP save   <session> <artifact-rel> --from <source-file>
pwsh $CP save   <session> <artifact-rel> --text "<small snippet>"
pwsh $CP link   <session> <phase> <step> <artifact-rel>
pwsh $CP ls     <session> [prefix]
pwsh $CP read   <session> <artifact-rel> [--max-chars 4096]

# Resume / inspect
pwsh $CP resume <session>
pwsh $CP view   <session> <phase> <step>
pwsh $CP view   <session> <phase> <step> full [--max-chars 8000]
pwsh $CP gate   <session> pass|fail "<gate-name>" [task-id]
pwsh $CP metrics <session>
```

## Token-saving workflow

| Instead of… | Do… |
|-------------|-----|
| Pasting a code plan in chat | Write to `artifacts/tasks/{id}/code-plan.md`, then `link` + cite path |
| Pasting build/test output | `save … --from /tmp/build.log` or redirect to `artifacts/gates/dev.log` |
| Pasting full step input/output | One-line summary in `input`/`output`; details in artifact file |
| Loading entire artifact on resume | `resume` (index only) → `read --max-chars 2000` if needed |
| `view` with huge logs | Default `view` = metadata; `view … full` only when debugging |

### Example — developer code plan

```powershell
$CP = '.cursor/skills/checkpoint/scripts/checkpoint.ps1'
$Session = '20260610-rate-limit'
$Task = 'task-142'

# 1. Write file with editor/Write tool (not in chat):
#    _code_agent/$Session/artifacts/tasks/$Task/code-plan.md

# 2. Register + brief the coordinator
pwsh $CP link $Session 7 7.3 "tasks/$Task/code-plan.md"
pwsh $CP output $Session 7 7.3 "Code plan ready: artifacts/tasks/$Task/code-plan.md"
```

### Example — gate log

```powershell
$CP = '.cursor/skills/checkpoint/scripts/checkpoint.ps1'
$Session = '20260610-rate-limit'
dotnet test 2>&1 | Tee-Object -FilePath /tmp/test.log
pwsh $CP save $Session gates/test.log --from /tmp/test.log
pwsh $CP gate $Session pass test-gate task-142
```

## Coordinator usage

- On every step boundary: `start` → (`save`/`link` as needed) → short `input`/`output` → `done` or `gate`.
- **SDLC docs:** write to `_code_agent/{session}/artifacts/sdlc/` during phases; coordinator publishes to `docs/sdlc/` after Phase 9.
- **Resume across chats:** `resume <session>` → read TOON → cite artifact paths → `read` only what you need.
- Never store secrets in checkpoint files.
