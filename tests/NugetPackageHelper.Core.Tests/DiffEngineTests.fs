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
      CompareBranch="main"
      PropsPath=None
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

// ── suffix-only changes ────────────────────────────────────────────────────

[<Fact>]
let ``computeDiff classifies 1.0.0-beta to 1.0.0-rc.1 as Suffix without a cascade gap`` () =
    // Snapshot 1.0.0-beta, live 1.0.0-rc.1: a suffix-only move is Changed, not a cascade.
    let beta = { Major = 1; Minor = 0; Patch = 0; PreRelease = Some "beta" }
    let rc = { Major = 1; Minor = 0; Patch = 0; PreRelease = Some "rc.1" }
    let snap = graph [ node "A" beta [] ]
    let live = Map.ofList ["A", rc]
    let diff = DiffEngine.computeDiff snap live
    diff.Changed |> List.length |> should equal 1
    diff.Changed[0].PackageName     |> should equal "A"
    diff.Changed[0].SnapshotVersion |> should equal beta
    diff.Changed[0].CurrentVersion  |> should equal rc
    diff.Changed[0].BumpType        |> should equal Suffix
    diff.CascadeGaps                |> List.isEmpty |> should equal true

[<Fact>]
let ``computeDiff still identifies a cascade gap when the number changes`` () =
    // A numeric move of a dependency still leaves an unbumped dependent as a gap.
    let snap = graph [ node "A" v100 []; node "B" v100 ["A"] ]
    let live = Map.ofList ["A", ver 1 0 1; "B", v100]
    let diff = DiffEngine.computeDiff snap live
    diff.Changed |> List.length |> should equal 1
    diff.Changed[0].PackageName |> should equal "A"
    diff.Changed[0].BumpType    |> should equal Patch
    diff.CascadeGaps            |> List.length |> should equal 1
    diff.CascadeGaps[0].PackageName |> should equal "B"

[<Fact>]
let ``computeDiff does not treat 1.2.0-beta to 1.2.0 as an earlier release`` () =
    // Clearing the suffix on the same numbers is a forward Suffix change, not a downgrade.
    let beta = { Major = 1; Minor = 2; Patch = 0; PreRelease = Some "beta" }
    let release = ver 1 2 0
    let snap = graph [ node "A" beta [] ]
    let live = Map.ofList ["A", release]
    let diff = DiffEngine.computeDiff snap live
    diff.Changed |> List.length |> should equal 1
    diff.Changed[0].PackageName     |> should equal "A"
    diff.Changed[0].SnapshotVersion |> should equal beta
    diff.Changed[0].CurrentVersion  |> should equal release
    diff.Changed[0].BumpType        |> should equal Suffix
    SemVer.isDowngrade beta release |> should equal false
    diff.CascadeGaps                |> List.isEmpty |> should equal true
