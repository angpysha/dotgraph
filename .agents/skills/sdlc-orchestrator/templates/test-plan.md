# TEST-NNNN: {Feature} — Test Report

## Meta

| Field | Value |
|-------|-------|
| **ID** | TEST-NNNN |
| **Parent REQ** | REQ-NNNN |
| **Parent Issue** | dartrepo-xxx |
| **Date** | YYYY-MM-DD |
| **Tester** | {name} |

## Summary

{One paragraph: overall pass/fail, test count}

## Commands Run

```bash
dotnet test tests/DartPubRepo.Functions.Tests/ --configuration Release
```

## Pass/Fail Matrix

| AC ID | Requirement | Test(s) | Result |
|-------|-------------|---------|--------|
| AC-1 | {description} | {TestClass.TestMethod} | PASS / FAIL |

## Coverage Summary

| Area | Covered | Notes |
|------|---------|-------|
| Unit | Yes/No/Partial | {notes} |
| Integration | Yes/No/Partial | {notes} |
| API Contract | Yes/No/Deferred | {notes} |

## Failures (if any)

| Test | Error | Root Cause |
|------|-------|------------|
| {test} | {error} | {cause} |

## Deferred Tests

| Test | Reason | Follow-up Issue |
|------|--------|-----------------|
| {test} | {reason} | dartrepo-xxx |

## Conclusion

- [ ] All acceptance criteria verified
- [ ] Ready to close issue
- [ ] Returned to Developer (see Failures)
