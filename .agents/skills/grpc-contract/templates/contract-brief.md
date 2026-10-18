# Contract brief — GRPC-{REQ_ID}-{slug}

gRPC / Protocol Buffers contract for REQ-{REQ_ID}.

| Field | Value |
|-------|-------|
| **REQ** | REQ-{REQ_ID} |
| **Proto file** | `docs/sdlc/api/GRPC-{REQ_ID}-{slug}.proto` |
| **Status** | Draft |

## Requirement → RPC map

| REQ ref | RPC method | Request | Response | Notes |
|---------|------------|---------|----------|-------|
| FR-1 / AC-1 | `{RpcName}` | `{RequestMsg}` | `{ResponseMsg}` | {fill in Phase 5/6} |

## Service metadata

| Field | Value |
|-------|-------|
| `package` | `{package}.v1` |
| `service` | `{ServiceName}` |

## Sign-off

| Role | Phase | Done |
|------|-------|------|
| Architect | 5 — initial `.proto` from REQ + SDD | [ ] |
| Team Lead | 6 — contract lock + task RPC mapping | [ ] |
| Developer | 7 — servers/clients match proto exactly | [ ] |
