# PR description template for Phase 10 closeout (REQ-{id}).

## Summary

{One paragraph — what changed and why.}

## SDLC artifacts

| Artifact | Path |
|----------|------|
| Requirements | docs/sdlc/requirements/REQ-{id}-{slug}.md |
| SDD | docs/sdlc/design/SDD-{id}-{slug}.md |
| TDD | docs/sdlc/design/TDD-{id}-{slug}.md |
| Test report | docs/sdlc/test-reports/TEST-{id}-{slug}.md |
| Implementation plan | docs/sdlc/design/IMPLEMENTATION-PLAN-{id}.md |

## Tracker

- Closed issues: {br issue ids}
- Epic: {epic summary one-liner}

## Test evidence

- Dev gate: PASS
- Test gate: PASS
- Coverage summary: TestResults/azure-devops-results.json (if .NET)

## Notes

{Infra changes, migrations, rollout — or "None".}
