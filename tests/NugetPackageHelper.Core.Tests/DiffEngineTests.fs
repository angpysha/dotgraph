module NugetPackageHelper.Core.Tests.DiffEngineTests

open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core

let private ver major minor patch = { Major=major; Minor=minor; Patch=patch; PreRelease=None }
let private v100 = ver 1 0 0
let private v110 = ver 1 1 0

let private node name version deps : PackageNode =
    { Name = name; Version = version; ProjectPath = $"/fake/{name}.csproj"; Dependencies = deps }

let private graph nodes : DependencyGraph =
    { SolutionPath="/fake/sol.slnx"
      CreatedAt=System.DateTime.UtcNow
      Packages = nodes |> List.map (fun n -> n.Name, n) |> Map.ofList }

// ── no changes ────────────────────────────────────────────────────────────

[<Fact>]
let ``computeDiff returns empty diff when nothing changed`` () =
    let snap = graph [ node "A" v100 [] ]
    let live = Map.ofList ["A", v100]
    let diff = DiffEngine.computeDiff snap live
    diff.Changed        |> List.isEmpty |> should equal true
    diff.CascadeGaps    |> List.isEmpty |> should equal true
    diff.AlreadyCovered |> List.isEmpty |> should equal true

// ── changed ───────────────────────────────────────────────────────────────

[<Fact>]
let ``computeDiff detects a single version change`` () =
    let snap = graph [ node "A" v100 [] ]
    let live = Map.ofList ["A", v110]
    let diff = DiffEngine.computeDiff snap live
    diff.Changed |> List.length |> should equal 1
    diff.Changed[0].PackageName    |> should equal "A"
    diff.Changed[0].SnapshotVersion |> should equal v100
    diff.Changed[0].CurrentVersion  |> should equal v110
    diff.Changed[0].BumpType        |> should equal Minor

// ── cascade gaps ──────────────────────────────────────────────────────────

[<Fact>]
let ``computeDiff identifies cascade gap when dependent not bumped`` () =
    // Snapshot: A=1.0.0, B=1.0.0 (B depends on A)
    // Live: A=1.1.0, B=1.0.0 (still at snapshot → gap)
    let snap = graph [ node "A" v100 []; node "B" v100 ["A"] ]
    let live = Map.ofList ["A", v110; "B", v100]
    let diff = DiffEngine.computeDiff snap live
    diff.CascadeGaps   |> List.length |> should equal 1
    diff.CascadeGaps[0].PackageName |> should equal "B"
    diff.AlreadyCovered |> List.isEmpty |> should equal true

// ── already covered ────────────────────────────────────────────────────────

[<Fact>]
let ``computeDiff produces no cascade gap when dependent is also manually bumped`` () =
    // Both A and B changed: B was pre-bumped by the user.
    // B becomes a root (Changed) so it is NOT proposed as a cascade, leaving no gap.
    let snap = graph [ node "A" v100 []; node "B" v100 ["A"] ]
    let live = Map.ofList ["A", v110; "B", ver 1 0 1]
    let diff = DiffEngine.computeDiff snap live
    diff.Changed     |> List.length |> should equal 2
    diff.CascadeGaps |> List.isEmpty |> should equal true

// ── multiple roots ─────────────────────────────────────────────────────────

[<Fact>]
let ``computeDiff handles multiple simultaneously changed roots`` () =
    let snap = graph [ node "A" v100 []; node "B" v100 [] ]
    let live = Map.ofList ["A", v110; "B", ver 2 0 0]
    let diff = DiffEngine.computeDiff snap live
    diff.Changed |> List.length |> should equal 2
    diff.Changed |> List.map (fun c -> c.PackageName) |> List.sort |> should equal ["A"; "B"]
