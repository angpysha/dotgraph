# Contract brief — OAPI-{REQ_ID}-{slug}

Links **requirements** → **OpenAPI operations** → **implementation tasks**.

| Field | Value |
|-------|-------|
| **REQ** | REQ-{REQ_ID} |
| **OpenAPI** | `docs/sdlc/api/OAPI-{REQ_ID}-{slug}.yaml` |
| **Status** | Draft |

## Requirement → operation map

| REQ ref | Operation ID | Method | Path | Notes |
|---------|--------------|--------|------|-------|
| FR-1 / AC-1 | `{operationId}` | GET | `/example` | {fill during Phase 5/6} |

## Auth & errors

| Concern | Policy |
|---------|--------|
| Authentication | {none / bearer / api-key} |
| Standard errors | `400`, `401`, `403`, `404`, `409`, `422`, `500` — use shared `ProblemDetails` schema where applicable |

## Out of scope (explicit)

- {endpoint or behavior not in this contract}

## Sign-off

| Role | Phase | Done |
|------|-------|------|
| Architect | 5 — initial OpenAPI from REQ + SDD | [ ] |
| Team Lead | 6 — contract lock + task `operationId` mapping | [ ] |
| Developer | 7 — implementation matches schema | [ ] |
