module NugetPackageHelper.Core.Tests.PropsExportTests

open System.IO
open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core

let private ver major minor patch pre =
    { Major = major; Minor = minor; Patch = patch; PreRelease = pre }

let private node name version =
    { Name = name; Version = version; ProjectPath = $"/fake/{name}.csproj"; Dependencies = [] }

let private packages entries =
    entries |> List.map (fun (n, v) -> n, node n v) |> Map.ofList

[<Fact>]
let ``buildDotgraphGroup orders names case insensitively`` () =
    let pkgs =
        packages [
            "MyLib.Core", ver 1 2 0 None
            "mylib.abstractions", ver 1 0 0 None
            "MyLib.Http", ver 1 5 0 (Some "beta.1")
        ]
    let text = PropsExport.buildDotgraphGroup pkgs
    let core = text.IndexOf("MyLib.Core")
    let abstractions = text.IndexOf("mylib.abstractions")
    let http = text.IndexOf("MyLib.Http")
    abstractions < core |> should equal true
    core < http |> should equal true
    text |> should haveSubstring "Version=\"1.5.0-beta.1\""

[<Fact>]
let ``applyContent creates new file body`` () =
    let pkgs = packages [ "A", ver 1 0 0 None ]
    match PropsExport.applyContent pkgs None with
    | Error e -> failwith e
    | Ok PropsExport.Unchanged -> failwith "expected change"
    | Ok (PropsExport.Changed text) ->
        text |> should haveSubstring "<ItemGroup Label=\"Dotgraph\">"
        text |> should haveSubstring "Include=\"A\""

[<Fact>]
let ``applyContent replaces only Dotgraph group`` () =
    let pkgs = packages [ "A", ver 2 0 0 None ]
    let existing =
        """<Project>
  <ItemGroup>
    <PackageVersion Include="Other" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup Label="Dotgraph">
    <PackageVersion Include="A" Version="1.0.0" />
  </ItemGroup>
</Project>
"""
    let otherGroup = "    <PackageVersion Include=\"Other\" Version=\"9.0.0\" />"
    match PropsExport.applyContent pkgs (Some existing) with
    | Error e -> failwith e
    | Ok PropsExport.Unchanged -> failwith "expected change"
    | Ok (PropsExport.Changed text) ->
        text |> should haveSubstring otherGroup
        text |> should haveSubstring "Version=\"2.0.0\""
        text |> should not' (haveSubstring "Version=\"1.0.0\"")

[<Fact>]
let ``export second run already matches`` () =
    let dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName())
    let build = Path.Combine(dir, "build")
    Directory.CreateDirectory build |> ignore
    try
        let graph =
            { SolutionPath = Path.Combine(dir, "sol.slnx")
              CreatedAt = System.DateTime.UtcNow
              CompareBranch = "main"
              PropsPath = Some "build/versions.props"
              Packages = packages [ "A", ver 1 0 0 None ] }
        match PropsExport.export graph dir with
        | Error e -> failwith e
        | Ok _ -> ()
        match PropsExport.export graph dir with
        | Error e -> failwith e
        | Ok result ->
            match result.Outcome with
            | PropsExport.AlreadyMatches -> ()
            | other -> failwith $"expected already matches: {other}"
    finally
        Directory.Delete(dir, recursive = true)

[<Fact>]
let ``applyContent empty package list leaves empty group`` () =
    match PropsExport.applyContent Map.empty None with
    | Ok (PropsExport.Changed text) ->
        text |> should haveSubstring "<ItemGroup Label=\"Dotgraph\">"
        text |> should not' (haveSubstring "PackageVersion")
    | other -> failwith $"{other}"

[<Fact>]
let ``applyContent rejects duplicate Dotgraph groups`` () =
    let pkgs = packages [ "A", ver 1 0 0 None ]
    let existing =
        """<Project>
  <ItemGroup Label="Dotgraph"></ItemGroup>
  <ItemGroup Label="Dotgraph"></ItemGroup>
</Project>"""
    match PropsExport.applyContent pkgs (Some existing) with
    | Error msg -> msg |> should haveSubstring "more than one"
    | Ok _ -> failwith "expected error"

[<Fact>]
let ``findExternalDuplicateNames reports package outside Dotgraph`` () =
    let text =
        """<Project>
  <ItemGroup>
    <PackageVersion Include="Shared" Version="1.0.0" />
  </ItemGroup>
  <ItemGroup Label="Dotgraph">
    <PackageVersion Include="Shared" Version="2.0.0" />
  </ItemGroup>
</Project>"""
    PropsExport.findExternalDuplicateNames text (Set.ofList [ "Shared" ])
    |> should equal [ "Shared" ]

[<Fact>]
let ``export writes file under base directory`` () =
    let dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName())
    let build = Path.Combine(dir, "build")
    Directory.CreateDirectory build |> ignore
    try
        let graph =
            { SolutionPath = Path.Combine(dir, "sol.slnx")
              CreatedAt = System.DateTime.UtcNow
              CompareBranch = "main"
              PropsPath = Some "build/versions.props"
              Packages = packages [ "Pkg", ver 1 2 3 None ] }
        match PropsExport.export graph dir with
        | Error e -> failwith e
        | Ok result ->
            match result.Outcome with
            | PropsExport.Wrote 1 -> ()
            | other -> failwith $"{other}"
            let path = Path.Combine(build, "versions.props")
            File.Exists path |> should equal true
            let written = File.ReadAllText path
            written |> should haveSubstring "Include=\"Pkg\""
            written |> should haveSubstring "Version=\"1.2.3\""
    finally
        Directory.Delete(dir, recursive = true)
