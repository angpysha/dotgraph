# TDD-NNNN: {Component Name}

## Meta

| Field | Value |
|-------|-------|
| **ID** | TDD-NNNN |
| **Parent SDD** | SDD-NNNN |
| **Parent REQ** | REQ-NNNN |
| **Status** | Draft |
| **Author** | {name} |
| **Created** | YYYY-MM-DD |

## 1. Overview

{What specific component or module is being designed}

## 2. Component Diagram

```mermaid
classDiagram
  class ExampleService {
    +Method()
  }
```

## 3. Sequence Diagrams

### {Flow Name}

```mermaid
sequenceDiagram
  participant Client
  participant API
  participant Service
  Client->>API: Request
  API->>Service: Call
  Service-->>API: Result
  API-->>Client: Response
```

## 4. Interface Contracts

### Input

{Detailed input specifications}

### Output

{Detailed output specifications}

### Error Handling

| Condition | Response | HTTP Status |
|-----------|----------|-------------|
| {condition} | {response} | {code} |

## 5. Implementation Steps

| Step | Description | Estimate |
|------|-------------|----------|
| 1 | {step} | {time} |

## 6. Testing Strategy

### Unit Tests

- {scenario}

### Integration Tests

- {scenario}

### Edge Cases

- {case}

## 7. Rollback Plan

{How to revert if issues are found}
