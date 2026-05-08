module NugetPackageHelper.Scanner.Tests.ProjectScannerTests

open System
open System.IO
open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner

let private fixturesDir =
    Path.Combine(AppContext.BaseDirectory, "Fixtures")

let private coreCsproj    = Path.Combine(fixturesDir, "projects", "Core",      "Core.csproj")
let private scannerCsproj = Path.Combine(fixturesDir, "projects", "Scanner",   "Scanner.csproj")
let private noVerCsproj   = Path.Combine(fixturesDir, "projects", "NoVersion", "NoVersion.csproj")
let private fakeSln       = Path.Combine(fixturesDir, "slnx", "TestSolution.slnx")

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
