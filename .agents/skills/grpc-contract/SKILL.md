---
name: grpc-contract
description: >-
  Universal gRPC contract skill. Write Protocol Buffers (.proto) from approved requirements.
  Architect or Team Lead authors the proto in Phase 5/6; Developer implements services
  exactly to RPCs and messages. Use when REQ includes gRPC behavior.
---

# grpc-contract

**Contract-first gRPC** for any backend (.NET, Go, Rust, etc.). The **`.proto` file** is the
**source of truth** for services, RPC methods, and messages. Server/client code must match —
not the other way around.

Sibling skills: `openapi-contract` (REST), `graphql-contract` (GraphQL).

## Pipeline placement

| Phase | Agent | Responsibility |
|-------|-------|----------------|
| **4** | `ba-analyst` | FR/AC for RPCs, messages, streaming, auth, errors |
| **5** | **`architect`** | **Primary author** — `GRPC-{id}-{slug}.proto` from REQ + SDD § gRPC |
| **6** | **`team-lead`** | **Contract lock** — map tasks → RPCs; brief sign-off |
| **7** | **`developer`** | Service stubs/handlers match proto exactly |
| **8** | `tester` | Contract tests against proto + AC |

## Artifact paths

| Artifact | Default path |
|----------|----------------|
| Proto file | `docs/sdlc/api/GRPC-{id}-{slug}.proto` |
| Contract brief | `docs/sdlc/api/GRPC-{id}-{slug}-brief.md` |

## Commands

```powershell
$GRPC = '.cursor/skills/grpc-contract/scripts'

pwsh $GRPC/scaffold-grpc.ps1 -ReqId 0006
# optional: -PackageName myapp -ServiceName PackagesService

pwsh $GRPC/validate-grpc.ps1 docs/sdlc/api/GRPC-0006-my-feature.proto -ReqId 0006
```

## Authoring rules

### Every service must have

- `syntax = "proto3";` and `package {name}.v1;`
- **REQ-NNNN** in file header comment
- RPCs with clear **request/response** messages
- Comment per RPC citing FR/AC (e.g. `// AC-3: get package by name`)

### Example

```protobuf
// REQ-0006
service PackageService {
  // FR-2, AC-3
  rpc GetPackage(GetPackageRequest) returns (Package);
}

message GetPackageRequest {
  string name = 1;
}

message Package {
  string name = 1;
  string version = 2;
}
```

### Code generation

After proto lock, generate stubs per stack (`grpc-dotnet`, `protoc-gen-go`, etc.) — generation
is implementation detail; **proto in `docs/sdlc/api/` remains canonical**.

### Team Lead / Developer

Same contract-lock and exact-implementation rules as `openapi-contract`.

## Validation

`validate-design.ps1` when SDD § gRPC API is present. Uses structural checks + optional `protoc`.

## Constraints

- Proto3 only for new contracts.
- Breaking changes require version bump (`v2` package) + human approval.
