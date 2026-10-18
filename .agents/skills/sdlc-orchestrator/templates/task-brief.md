## Task: {Title}

**Type**: task | bug | feature | chore
**Priority**: 0-4 (0=critical, 4=backlog)
**Size**: XS | S | M
**Parent REQ**: REQ-NNNN
**Parent SDD/TDD**: SDD-NNNN / TDD-NNNN

### Description

{What needs to be done}

### Acceptance Criteria

- [ ] AC-1: {criterion from REQ}
- [ ] AC-2: {criterion}

### Technical Notes

{Implementation hints, file references, constraints}

### Definition of Done

- [ ] Code implemented and compiles (`dotnet build`)
- [ ] Dev gate passes (`run-dev-gate.ps1`)
- [ ] Tests written and passing (`run-test-gate.ps1`)
- [ ] Test report filed (`docs/sdlc/test-reports/TEST-NNNN-*.md`)
- [ ] No secrets committed

### File ownership (parallel safety)

- Owned files: `{path/glob, ...}` — developer must not touch files outside this set
- Parallel track: `{A | B | none}` — only run parallel with tasks on other tracks

### Dependencies

- Blocked by: {dartrepo-xxx or none}
- Blocks: {dartrepo-xxx or none}
- Parallel with: {dartrepo-yyy or none — disjoint file ownership required}
