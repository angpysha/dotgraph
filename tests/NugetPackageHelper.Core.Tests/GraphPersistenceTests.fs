module NugetPackageHelper.Core.Tests.GraphPersistenceTests

open System.IO
open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core

let private ver major minor patch = { Major=major; Minor=minor; Patch=patch; PreRelease=None }

let private node name version deps : PackageNode =
    { Name=name; Version=version; ProjectPath=Path.Combine("/fake", $"{name}.csproj"); Dependencies=deps }

let private makeGraph nodes =
    { SolutionPath = Path.Combine("/fake", "sol.slnx")
      CreatedAt    = System.DateTime(2025, 1, 1, 0, 0, 0, System.DateTimeKind.Utc)
      Packages     = nodes |> List.map (fun n -> n.Name, n) |> Map.ofList }

// ── round-trip ────────────────────────────────────────────────────────────

[<Fact>]
let ``save then load round-trips graph correctly`` () =
    let dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName())
    Directory.CreateDirectory dir |> ignore
    try
        let original =
            makeGraph [
                node "Core"    (ver 1 2 3) []
                node "Scanner" (ver 0 5 0) ["Core"]
                node "Cli"     (ver 0 5 0) ["Core"; "Scanner"]
            ]

        GraphPersistence.save original dir |> Result.isOk |> should equal true

        let loaded = GraphPersistence.load dir
        loaded |> Result.isOk |> should equal true

        match loaded with
        | Error e -> failwith e
        | Ok g ->
            g.Packages.Count |> should equal 3
            g.Packages["Core"].Version    |> should equal (ver 1 2 3)
            g.Packages["Scanner"].Version |> should equal (ver 0 5 0)
            g.Packages["Scanner"].Dependencies |> should equal ["Core"]
            g.Packages["Cli"].Dependencies     |> should equal ["Core"; "Scanner"]
    finally
        Directory.Delete(dir, recursive=true)

[<Fact>]
let ``load returns Error when file missing`` () =
    let dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName())
    Directory.CreateDirectory dir |> ignore
    try
        match GraphPersistence.load dir with
        | Error msg -> msg |> should haveSubstring ".dotgraph.json"
        | Ok _      -> failwith "Expected Error"
    finally
        Directory.Delete(dir, recursive=true)

[<Fact>]
let ``save uses relative paths in JSON`` () =
    let dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName())
    Directory.CreateDirectory dir |> ignore
    try
        let g =
            { makeGraph [] with
                SolutionPath = Path.Combine(dir, "my.slnx")
                Packages =
                    Map.ofList [
                        "Pkg", { Name="Pkg"; Version=ver 1 0 0
                                 ProjectPath=Path.Combine(dir, "src", "Pkg.csproj")
                                 Dependencies=[] }
                    ] }
        GraphPersistence.save g dir |> ignore
        let json = File.ReadAllText(Path.Combine(dir, ".dotgraph.json"))
        json |> should haveSubstring "src"
        json |> should not' (haveSubstring (Path.GetTempPath()))
    finally
        Directory.Delete(dir, recursive=true)
