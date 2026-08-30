module NugetPackageHelper.Scanner.Tests.ProjectScannerTests

open System
open System.IO
open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner

let private fixturesDir =
    Path.Combine(AppContext.BaseDirectory, "Fixtures")

let private coreCsproj         = Path.Combine(fixturesDir, "projects", "Core",             "Core.csproj")
let private scannerCsproj      = Path.Combine(fixturesDir, "projects", "Scanner",          "Scanner.csproj")
let private noVerCsproj        = Path.Combine(fixturesDir, "projects", "NoVersion",        "NoVersion.csproj")
let private pkgVersionCsproj        = Path.Combine(fixturesDir, "projects", "PackageVersion",        "PackageVersion.csproj")
let private verPrefixCsproj         = Path.Combine(fixturesDir, "projects", "VersionPrefix",         "VersionPrefix.csproj")
let private verPrefixSuffCsproj     = Path.Combine(fixturesDir, "projects", "VersionPrefixSuffix",   "VersionPrefixSuffix.csproj")
let private pkgVerWinsCsproj        = Path.Combine(fixturesDir, "projects", "PkgVersionWinsOverVersion",  "PkgVersionWinsOverVersion.csproj")
let private verWinsPrefixCsproj     = Path.Combine(fixturesDir, "projects", "VersionWinsOverPrefix",      "VersionWinsOverPrefix.csproj")
let private verPreReleaseCsproj     = Path.Combine(fixturesDir, "projects", "VersionPreRelease",          "VersionPreRelease.csproj")
let private emptyVerSuffCsproj      = Path.Combine(fixturesDir, "projects", "EmptyVersionSuffix",         "EmptyVersionSuffix.csproj")
let private suffixOnlyCsproj        = Path.Combine(fixturesDir, "projects", "SuffixOnly",                 "SuffixOnly.csproj")
let private fsharpLibFsproj         = Path.Combine(fixturesDir, "projects", "FSharpLib",                  "FSharpLib.fsproj")
let private fakeSln                 = Path.Combine(fixturesDir, "slnx", "TestSolution.slnx")

// ── buildGraph ─────────────────────────────────────────────────────────────

[<Fact>]
let ``buildGraph parses PackageId as name`` () =
    match ProjectScanner.buildGraph fakeSln [coreCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.Packages.ContainsKey "MyCompany.Core" |> should equal true

[<Fact>]
let ``buildGraph falls back to AssemblyName when no PackageId`` () =
    match ProjectScanner.buildGraph fakeSln [scannerCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.Packages.ContainsKey "MyCompany.Scanner" |> should equal true

[<Fact>]
let ``buildGraph reads version correctly`` () =
    match ProjectScanner.buildGraph fakeSln [coreCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        let node = graph.Packages["MyCompany.Core"]
        node.Version |> should equal { Major=1; Minor=2; Patch=3; PreRelease=None }

[<Fact>]
let ``buildGraph remaps ProjectReference to internal package name`` () =
    match ProjectScanner.buildGraph fakeSln [coreCsproj; scannerCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        let scanner = graph.Packages["MyCompany.Scanner"]
        scanner.Dependencies |> should equal ["MyCompany.Core"]

[<Fact>]
let ``buildGraph excludes project with no Version tag and emits warning`` () =
    match ProjectScanner.buildGraph fakeSln [coreCsproj; noVerCsproj] with
    | Error e -> failwith e
    | Ok (graph, warnings) ->
        graph.Packages.ContainsKey "NoVersion" |> should equal false
        warnings |> List.isEmpty |> should equal false

[<Fact>]
let ``buildGraph sets SolutionPath on graph`` () =
    match ProjectScanner.buildGraph fakeSln [coreCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.SolutionPath |> should equal fakeSln

// ── version tag fallbacks ──────────────────────────────────────────────────

[<Fact>]
let ``buildGraph reads PackageVersion tag`` () =
    match ProjectScanner.buildGraph fakeSln [pkgVersionCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.Packages["PackageVersion"].Version
        |> should equal { Major=2; Minor=0; Patch=0; PreRelease=None }

[<Fact>]
let ``buildGraph reads VersionPrefix when no Version`` () =
    match ProjectScanner.buildGraph fakeSln [verPrefixCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.Packages["VersionPrefix"].Version
        |> should equal { Major=1; Minor=5; Patch=0; PreRelease=None }

[<Fact>]
let ``buildGraph reads VersionPrefix combined with VersionSuffix`` () =
    match ProjectScanner.buildGraph fakeSln [verPrefixSuffCsproj] with
    | Error e -> failwith e
    | Ok (graph, warnings) ->
        graph.Packages["VersionPrefixSuffix"].Version
        |> should equal { Major=1; Minor=5; Patch=0; PreRelease=Some "beta.1" }
        warnings |> List.isEmpty |> should equal true

// ── priority overrides ────────────────────────────────────────────────────

[<Fact>]
let ``PackageVersion wins over Version when both present`` () =
    match ProjectScanner.buildGraph fakeSln [pkgVerWinsCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.Packages["PkgVersionWinsOverVersion"].Version
        |> should equal { Major=3; Minor=0; Patch=0; PreRelease=None }

[<Fact>]
let ``Version wins over VersionPrefix when both present`` () =
    match ProjectScanner.buildGraph fakeSln [verWinsPrefixCsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.Packages["VersionWinsOverPrefix"].Version
        |> should equal { Major=2; Minor=5; Patch=0; PreRelease=None }

// ── edge cases ────────────────────────────────────────────────────────────

[<Fact>]
let ``Version tag with pre-release is parsed correctly`` () =
    match ProjectScanner.buildGraph fakeSln [verPreReleaseCsproj] with
    | Error e -> failwith e
    | Ok (graph, warnings) ->
        graph.Packages["VersionPreRelease"].Version
        |> should equal { Major=2; Minor=0; Patch=0; PreRelease=Some "rc.2" }
        warnings |> List.isEmpty |> should equal true

[<Fact>]
let ``empty VersionSuffix is treated as absent and uses VersionPrefix only`` () =
    match ProjectScanner.buildGraph fakeSln [emptyVerSuffCsproj] with
    | Error e -> failwith e
    | Ok (graph, warnings) ->
        graph.Packages["EmptyVersionSuffix"].Version
        |> should equal { Major=1; Minor=3; Patch=0; PreRelease=None }
        warnings |> List.isEmpty |> should equal true

[<Fact>]
let ``VersionSuffix alone without prefix produces no version and emits warning`` () =
    match ProjectScanner.buildGraph fakeSln [suffixOnlyCsproj] with
    | Error e -> failwith e
    | Ok (graph, warnings) ->
        graph.Packages.ContainsKey "SuffixOnly" |> should equal false
        warnings |> List.isEmpty |> should equal false

// ── .fsproj support ───────────────────────────────────────────────────────

[<Fact>]
let ``buildGraph scans fsproj and reads version`` () =
    match ProjectScanner.buildGraph fakeSln [fsharpLibFsproj] with
    | Error e -> failwith e
    | Ok (graph, warnings) ->
        graph.Packages.ContainsKey "MyCompany.FSharpLib" |> should equal true
        graph.Packages["MyCompany.FSharpLib"].Version
        |> should equal { Major=3; Minor=1; Patch=0; PreRelease=None }
        warnings |> List.isEmpty |> should equal true

[<Fact>]
let ``buildGraph remaps ProjectReference from fsproj to csproj dependency`` () =
    match ProjectScanner.buildGraph fakeSln [coreCsproj; fsharpLibFsproj] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.Packages["MyCompany.FSharpLib"].Dependencies
        |> should equal ["MyCompany.Core"]

[<Fact>]
let ``buildGraph handles mixed csproj and fsproj in same graph`` () =
    match ProjectScanner.buildGraph fakeSln [coreCsproj; scannerCsproj; fsharpLibFsproj] with
    | Error e -> failwith e
    | Ok (graph, warnings) ->
        graph.Packages.Count |> should equal 3
        graph.Packages.ContainsKey "MyCompany.Core"      |> should equal true
        graph.Packages.ContainsKey "MyCompany.Scanner"   |> should equal true
        graph.Packages.ContainsKey "MyCompany.FSharpLib" |> should equal true
        warnings |> List.isEmpty |> should equal true

// ── writeVersion ───────────────────────────────────────────────────────────

let private copyFixtureToTemp (sourcePath: string) : string =
    let tempDir = Path.Combine(Path.GetTempPath(), "dotgraph-tests", Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory tempDir |> ignore
    let destPath = Path.Combine(tempDir, Path.GetFileName sourcePath)
    File.Copy(sourcePath, destPath)
    destPath

let private readVersionFromProject (projectPath: string) =
    match ProjectScanner.buildGraph fakeSln [projectPath] with
    | Error e -> failwith e
    | Ok (graph, _) ->
        graph.Packages.Values |> Seq.head |> fun n -> n.Version

[<Fact>]
let ``writeVersion updates PackageVersion tag`` () =
    let path = copyFixtureToTemp pkgVersionCsproj
    let newVersion = { Major=2; Minor=1; Patch=0; PreRelease=None }
    match ProjectScanner.writeVersion path newVersion with
    | Error e -> failwith e
    | Ok () ->
        readVersionFromProject path |> should equal newVersion

[<Fact>]
let ``writeVersion updates PackageVersion when both PackageVersion and Version present`` () =
    let path = copyFixtureToTemp pkgVerWinsCsproj
    let newVersion = { Major=3; Minor=1; Patch=0; PreRelease=None }
    match ProjectScanner.writeVersion path newVersion with
    | Error e -> failwith e
    | Ok () ->
        readVersionFromProject path |> should equal newVersion

[<Fact>]
let ``writeVersion updates VersionPrefix and VersionSuffix`` () =
    let path = copyFixtureToTemp verPrefixSuffCsproj
    let newVersion = { Major=1; Minor=6; Patch=0; PreRelease=Some "beta.2" }
    match ProjectScanner.writeVersion path newVersion with
    | Error e -> failwith e
    | Ok () ->
        readVersionFromProject path |> should equal newVersion

[<Fact>]
let ``writeVersion updates VersionPrefix only project`` () =
    let path = copyFixtureToTemp verPrefixCsproj
    let newVersion = { Major=1; Minor=6; Patch=0; PreRelease=None }
    match ProjectScanner.writeVersion path newVersion with
    | Error e -> failwith e
    | Ok () ->
        readVersionFromProject path |> should equal newVersion
