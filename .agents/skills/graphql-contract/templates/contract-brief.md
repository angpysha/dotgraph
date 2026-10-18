# Contract brief — GQL-{REQ_ID}-{slug}

GraphQL schema contract for REQ-{REQ_ID}.

| Field | Value |
|-------|-------|
| **REQ** | REQ-{REQ_ID} |
| **GraphQL schema** | `docs/sdlc/api/GQL-{REQ_ID}-{slug}.graphql` |
| **Status** | Draft |

## Requirement → field map

| REQ ref | GraphQL field | Type | Root | Notes |
|---------|---------------|------|------|-------|
| FR-1 / AC-1 | `{fieldName}` | `Query` / `Mutation` | Query | {fill in Phase 5/6} |

## Auth & errors

| Concern | Policy |
|---------|--------|
| Authentication | {none / bearer / session / @auth directive} |
| Errors | Use `UserError` union or standard error extensions |

## Sign-off

| Role | Phase | Done |
|------|-------|------|
| Architect | 5 — initial schema from REQ + SDD | [ ] |
| Team Lead | 6 — contract lock + task field mapping | [ ] |
| Developer | 7 — resolvers match schema exactly | [ ] |
