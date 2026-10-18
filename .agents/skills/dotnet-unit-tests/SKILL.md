---
name: dotnet-unit-tests
description: >-
  Run dotnet unit tests with Cobertura coverage and VSTest TRX output for Azure DevOps.
  Use at Phase 7.5 after writing tests. Produces TestResults/azure-devops-results.json.
disable-model-invocation: true
---

# dotnet-unit-tests

Deterministic **unit test + coverage** runner for .NET (xUnit). Use at **step 7.5** after
implementing tests and before polish / dev gate.

## When to run

| Step | Action |
|------|--------|
| **7.4** | Write code |
| **dotnet-format** | Format |
| **7.5** | **This skill** — run tests + coverage |
| **7.7** | Polish |
| **7.8** | Dev gate |

## Commands

From repo root (PowerShell Core):

```powershell
$Tests = '.cursor/skills/dotnet-unit-tests/scripts/dotnet-unit-tests.ps1'

# Default — Release, Cobertura + TRX
pwsh $Tests

# Filter (xUnit expression)
pwsh $Tests -Filter "FullyQualifiedName~RateLimit"

# Skip coverage (faster local loop)
pwsh $Tests -NoCoverage
```

## Outputs (Azure DevOps)

All paths are **repo-relative** — stable for CI and `Publish*@2` tasks.

| File | Purpose |
|------|---------|
| `TestResults/test-results.trx` | VSTest results → `PublishTestResults@2` |
| `TestResults/coverage/cobertura.xml` | Cobertura → `PublishCodeCoverageResults@2` |
| `TestResults/azure-devops-results.json` | Machine-readable summary for agents / pipelines |

### `azure-devops-results.json` shape

```json
{
  "schemaVersion": "1",
  "passed": true,
  "exitCode": 0,
  "azureDevOps": {
    "publishTestResults": {
      "testResultsFormat": "VSTest",
      "testResultsFiles": "TestResults/test-results.trx"
    },
    "publishCodeCoverageResults": {
      "codeCoverageTool": "Cobertura",
      "summaryFileLocation": "TestResults/coverage/cobertura.xml"
    }
  },
  "coverage": {
    "lineCoveragePercent": 85.2,
    "branchCoveragePercent": 72.1,
    "linesValid": 1000,
    "linesCovered": 852
  }
}
```

### Azure Pipelines YAML

```yaml
- pwsh: .cursor/skills/dotnet-unit-tests/scripts/dotnet-unit-tests.ps1
  displayName: Unit tests + coverage

- task: PublishTestResults@2
  condition: always()
  inputs:
    testResultsFormat: VSTest
    testResultsFiles: TestResults/test-results.trx
    mergeTestResults: true

- task: PublishCodeCoverageResults@2
  condition: succeededOrFailed()
  inputs:
    codeCoverageTool: Cobertura
    summaryFileLocation: $(System.DefaultWorkingDirectory)/TestResults/coverage/cobertura.xml
```

## Manifest override (optional)

```json
"test": {
  "command": "pwsh .cursor/skills/dotnet-unit-tests/scripts/dotnet-unit-tests.ps1",
  "filter": "Category!=Integration",
  "results": {
    "directory": "TestResults",
    "trx": "TestResults/test-results.trx",
    "cobertura": "TestResults/coverage/cobertura.xml",
    "summary": "TestResults/azure-devops-results.json"
  }
}
```

`test.command` is used by `run-test-gate.ps1` when the test gate runs.

## Test project requirements

- **xUnit** test project(s) in the solution.
- For coverage, test projects need **`coverlet.collector`** (or SDK-bundled collector):

```xml
<PackageReference Include="coverlet.collector" Version="6.*">
  <PrivateAssets>all</PrivateAssets>
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
</PackageReference>
```

## Checkpoint

```powershell
pwsh $Tests 2>&1 | pwsh .cursor/skills/checkpoint/scripts/save-artifact.ps1 `
  -Session <session> -ArtifactRel gates/unit-tests.log -Mode --stdin
```

Cite `TestResults/azure-devops-results.json` in chat (paths + coverage %), not full Cobertura XML.

## Constraints

- Run after **7.5** test code is written — not a substitute for writing tests.
- Integration tests (`7.6`) may use a separate filter; default runs the full test target.
- On failure, loop to **7.4** / **7.5** until green.
