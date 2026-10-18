---
name: openapi-contract
description: >-
  Universal backend HTTP contract skill. Write OpenAPI 3.x (Swagger) specs from approved
  requirements. Architect or Team Lead authors the schema in Phase 5/6; Developer implements
  exactly to operationIds and request/response models. Use when REQ includes HTTP/API behavior.
---

# openapi-contract

**Contract-first HTTP API** for any backend stack (.NET, Node, Rust, etc.). The OpenAPI file
is the **source of truth** for routes, methods, schemas, status codes, and `operationId`
values. Implementation must match — not the other way around.

## Pipeline placement

```mermaid
flowchart LR
  REQ[REQ Phase 4] --> SDD[SDD Phase 5]
  SDD --> OAPI[OpenAPI YAML]
  OAPI --> PLAN[Plan Phase 6]
  PLAN --> DEV[Developer Phase 7]
  DEV --> TEST[Tester Phase 8]
```

| Phase | Agent | OpenAPI responsibility |
|-------|-------|------------------------|
| **4** | `ba-analyst` | FR/AC describe **behavior** (status codes, payloads, auth) — not OpenAPI syntax |
| **5** | **`architect`** | **Primary author** — complete `OAPI-{id}-{slug}.yaml` from REQ + SDD § API Design |
| **6** | **`team-lead`** | **Contract lock** — map tasks → `operationId`; brief sign-off; no drift in plan |
| **7** | **`developer`** | Implement **exactly** to schema; code plan lists `operationId`s touched |
| **8** | `tester` | Contract/adversarial tests against OpenAPI + AC |
| **9** | `tech-writer` | Keep published docs in sync with OpenAPI |

**Coordinator rule:** if SDD has HTTP endpoints, **do not start Phase 7** until OpenAPI passes
`validate-openapi.ps1` and human approves design gate.

## Artifact paths

From `pipeline.manifest.json` `artifacts`:

| Artifact | Default path |
|----------|----------------|
| OpenAPI | `docs/sdlc/api/OAPI-{id}-{slug}.yaml` |
| Contract brief | `docs/sdlc/api/OAPI-{id}-{slug}-brief.md` |

## Commands

```powershell
$OAPI = '.cursor/skills/openapi-contract/scripts'

# 1. Scaffold stub from REQ (after Phase 4 gate)
pwsh $OAPI/scaffold-openapi.ps1 -ReqId 0006

# 2. Architect/TL edits YAML — fill paths, schemas, operationIds, x-ac-* extensions

# 3. Validate before design / tasks gate
pwsh $OAPI/validate-openapi.ps1 docs/sdlc/api/OAPI-0006-my-feature.yaml -ReqId 0006
```

## Authoring rules (architect / team-lead)

### Every operation must have

- Unique **`operationId`** (camelCase, stable — used in tasks and tests)
- **`summary`** + **`description`** referencing FR/AC ids
- **Request body** schema (if applicable) with required fields
- **Responses** for success + documented errors (`400`, `401`, `403`, `404`, `409`, `422`, `500`)
- Extension **`x-acceptance-criteria`**: list of `AC-N` ids covered

### Example operation

```yaml
paths:
  /packages/{name}:
    get:
      operationId: getPackageByName
      summary: Retrieve package metadata
      description: Implements FR-2, AC-3, AC-4
      x-acceptance-criteria: [AC-3, AC-4]
      parameters:
        - name: name
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Package found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/PackageDto'
        '404':
          description: Package not found
```

### SDD alignment

Copy the SDD **§ API Design** table into OpenAPI paths, then **enrich** with schemas and
error models. SDD table is summary; OpenAPI is complete contract.

### Team Lead (Phase 6)

In the implementation plan, add **OpenAPI contract** section:

| Task | operationId(s) | Files (disjoint) |
|------|----------------|------------------|
| task-142 | `getPackageByName` | `src/.../PackagesRoutes.cs` |

Update `OAPI-{id}-{slug}-brief.md` requirement → operation map. Mark TL sign-off checkbox.

## Developer rules (Phase 7)

1. Read OpenAPI + assigned `operationId`s **before** code plan.
2. Code plan **file map** must cite `operationId` per changed route.
3. DTOs match `components/schemas` — same property names, types, required fields.
4. HTTP status codes match the spec.
5. If implementation needs a contract change → **escalate to coordinator** (architect/TL
   amends OpenAPI, human re-approves) — never silently drift.

## BA analyst input (Phase 4)

Ensure REQ includes for each API behavior:

- Method semantics (safe/idempotent where relevant)
- Request/response fields and validation rules
- Auth requirement
- Error cases as **AC-N** (not just happy path)

BA does **not** write OpenAPI — feeds the architect.

## Validation gate

`validate-design.ps1` invokes OpenAPI validation when SDD § API Design lists HTTP methods.

Manual check:

```powershell
pwsh .cursor/skills/openapi-contract/scripts/validate-openapi.ps1 <path> -ReqId NNNN
```

Checks: OpenAPI 3.0/3.1, `info`, non-empty `paths`, `operationId`s, REQ traceability.
Optional: `@redocly/cli lint` when `npx` is available.

## Checkpoint

```powershell
pwsh $OAPI/validate-openapi.ps1 ... 2>&1 | pwsh .cursor/skills/checkpoint/scripts/save-artifact.ps1 `
  -Session <session> -ArtifactRel gates/openapi-validate.log -Mode --stdin
```

Sibling skills: `graphql-contract` (GraphQL), `grpc-contract` (protobuf/gRPC).

- **OpenAPI 3.0.3+** (Swagger 2.0 is not supported).
- Stack-agnostic — no ASP.NET/Express-specific fields in the YAML.
- Do not paste full YAML in chat — cite file path + operationId list.
- Contract changes require human review on design/plan gate.
