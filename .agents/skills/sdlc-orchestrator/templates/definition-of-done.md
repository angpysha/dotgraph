# Definition of Done — task {dartrepo-xxx}

Checked before Phase 9/10 closes a task. Mirror of Definition of Ready at Phase 7 entry.

## Task DoD checklist

- [ ] All acceptance criteria met (traceability matrix updated)
- [ ] Unit tests green; integration tests if required (`run-unit-tests.ps1` / `--all`)
- [ ] `run-test-gate.ps1` PASS (full/fast lanes)
- [ ] No new compiler warnings / analyzer findings; `dotnet format` clean
- [ ] Code style per [docs/dotnet-code-style.mdc](../../../../docs/dotnet-code-style.mdc)
- [ ] AOT compat verified when applicable (`aot-compat-check`)
- [ ] Docs/OpenAPI updated if contract changed (tech-writer)
- [ ] No secrets in diff; secret-scan passed (dev gate)
- [ ] `br` issue updated with verification notes
- [ ] Human review approved (Phase 9)

## Definition of Ready (entry to Phase 7)

- [ ] Acceptance criteria on `br` issue
- [ ] Edge cases listed in REQ
- [ ] File map feasible; no blocking open technical questions
- [ ] Infra impact known
