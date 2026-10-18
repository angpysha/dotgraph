# Tasks: Write Package Versions to a Props File

> Feature: `specs/003-props-package-versions`

## Task checklist

- [x] T001 [Foundation] Write failing propsPath persistence tests — tests/NugetPackageHelper.Core.Tests/GraphPersistenceTests.fs
- [x] T002 [Foundation] Add PropsPath on DependencyGraph and GraphPersistence — src/NugetPackageHelper.Core/Types.fs, GraphPersistence.fs, test literals, ProjectScanner.buildGraph
- [x] T003 [Foundation] Write failing PropsExport tests — tests/NugetPackageHelper.Core.Tests/PropsExportTests.fs
- [x] T004 [Foundation] Implement PropsExport — src/NugetPackageHelper.Core/PropsExport.fs, NugetPackageHelper.Core.fsproj
- [x] T005 [US1] Register props-path command — src/NugetPackageHelper.Cli/Commands/PropsPath.fs, Program.fs, fsproj
- [x] T006 [US1] Register export-props command — src/NugetPackageHelper.Cli/Commands/ExportProps.fs, Program.fs, fsproj
- [x] T007 [US2] Preserve PropsPath on refresh, sync, propose — Refresh.fs, Sync.fs, Propose.fs
- [x] T008 [Polish] Document props-path and export-props — docs/user-guide.md
- [x] T009 [Polish] Run dotnet test Release — specs/003-props-package-versions/quickstart.md

## Dependencies

T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008 → T009
