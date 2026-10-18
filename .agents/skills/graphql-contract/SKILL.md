---
name: graphql-contract
description: >-
  Universal GraphQL contract skill. Write GraphQL schemas from approved requirements.
  Architect or Team Lead authors the schema in Phase 5/6; Developer implements resolvers
  exactly to fields and types. Use when REQ includes GraphQL API behavior.
---

# graphql-contract

**Contract-first GraphQL** for any backend (Hot Chocolate, Apollo, gqlgen, etc.). The
`.graphql` schema is the **source of truth** for types, queries, mutations, and field-level
behavior. Resolvers must match — not the other way around.

Sibling skills: `openapi-contract` (REST), `grpc-contract` (protobuf/gRPC).

## Pipeline placement

| Phase | Agent | Responsibility |
|-------|-------|----------------|
| **4** | `ba-analyst` | FR/AC for queries, mutations, types, auth, errors — not GraphQL syntax |
| **5** | **`architect`** | **Primary author** — `GQL-{id}-{slug}.graphql` from REQ + SDD § GraphQL |
| **6** | **`team-lead`** | **Contract lock** — map tasks → fields; brief sign-off |
| **7** | **`developer`** | Resolvers match schema; code plan lists fields/types touched |
| **8** | `tester` | Contract tests against schema + AC |

## Artifact paths

| Artifact | Default path |
|----------|----------------|
| GraphQL schema | `docs/sdlc/api/GQL-{id}-{slug}.graphql` |
| Contract brief | `docs/sdlc/api/GQL-{id}-{slug}-brief.md` |

## Commands

```powershell
$GQL = '.cursor/skills/graphql-contract/scripts'

pwsh $GQL/scaffold-graphql.ps1 -ReqId 0006
# architect/TL completes schema — remove placeholders, add @req / @ac directives

pwsh $GQL/validate-graphql.ps1 docs/sdlc/api/GQL-0006-my-feature.graphql -ReqId 0006
```

## Authoring rules

### Every exposed field must have

- Clear **type** (non-null where business requires)
- **Description** citing FR/AC
- `@req(id: "REQ-NNNN")` on object types or `@ac(ids: ["AC-N"])` on fields

### Example

```graphql
type Query {
  """
  FR-2, AC-3: fetch package by name
  """
  package(name: String!): Package @ac(ids: ["AC-3", "AC-4"])
}

type Package @req(id: "REQ-0006") {
  name: String!
  version: String!
}
```

### Team Lead (Phase 6)

Map tasks → GraphQL fields in plan + `GQL-*-brief.md`.

### Developer (Phase 7)

- Code plan lists **field names** and **types** implemented.
- Resolver signatures and return shapes match schema exactly.
- Contract change → escalate (architect/TL updates schema first).

## Validation

`validate-design.ps1` runs when SDD § GraphQL API is present.

## Constraints

- Schema-first; no resolver-driven schema changes without contract update.
- Cite schema path in chat — do not paste full `.graphql` files.
