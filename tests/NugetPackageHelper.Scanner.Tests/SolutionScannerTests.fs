module NugetPackageHelper.Scanner.Tests.SolutionScannerTests

open System
open System.IO
open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Scanner

let private fixturesDir =
    Path.Combine(AppContext.BaseDirectory, "Fixtures")

// ── .slnx parsing ─────────────────────────────────────────────────────────

[<Fact>]
let ``scan slnx returns project paths`` () =
    let slnx = Path.Combine(fixturesDir, "slnx", "TestSolution.slnx")
    match SolutionScanner.scan slnx with
    | Error e -> failwith e
    | Ok paths ->
        paths |> List.length |> should equal 2
        paths |> List.exists (fun p -> p.EndsWith "Core.csproj")    |> should equal true
        paths |> List.exists (fun p -> p.EndsWith "Scanner.csproj") |> should equal true

[<Fact>]
let ``scan slnx returns absolute paths`` () =
    let slnx = Path.Combine(fixturesDir, "slnx", "TestSolution.slnx")
    match SolutionScanner.scan slnx with
    | Error e -> failwith e
    | Ok paths -> paths |> List.forall Path.IsPathRooted |> should equal true

// ── .sln parsing ──────────────────────────────────────────────────────────

[<Fact>]
let ``scan sln returns project paths`` () =
    let sln = Path.Combine(fixturesDir, "sln", "TestSolution.sln")
    match SolutionScanner.scan sln with
    | Error e -> failwith e
    | Ok paths ->
        paths |> List.length |> should equal 2
        paths |> List.exists (fun p -> p.EndsWith "Core.csproj")    |> should equal true
        paths |> List.exists (fun p -> p.EndsWith "Scanner.csproj") |> should equal true

// ── findSolution ──────────────────────────────────────────────────────────

[<Fact>]
let ``findSolution finds slnx in directory`` () =
    let dir = Path.Combine(fixturesDir, "slnx")
    match SolutionScanner.findSolution dir with
    | Error e -> failwith e
    | Ok path -> path |> should haveSubstring "TestSolution.slnx"

[<Fact>]
let ``findSolution returns Error for empty directory`` () =
    let dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName())
    Directory.CreateDirectory dir |> ignore
    try
        match SolutionScanner.findSolution dir with
        | Error msg -> msg |> should haveSubstring "No .slnx or .sln"
        | Ok _      -> failwith "Expected Error"
    finally
        Directory.Delete dir
