module NugetPackageHelper.Core.Tests.CascadeEngineTests

open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core

let private ver major minor patch = { Major=major; Minor=minor; Patch=patch; PreRelease=None }
let private verPre major minor patch pre = { Major=major; Minor=minor; Patch=patch; PreRelease=Some pre }
let private v100 = ver 1 0 0

let private node name version deps : PackageNode =
    { Name = name; Version = version; ProjectPath = $"/fake/{name}.csproj"; Dependencies = deps }

let private graph nodes : DependencyGraph =
    { SolutionPath="/fake/sol.slnx"
      CreatedAt=System.DateTime.UtcNow
      CompareBranch="main"
      PropsPath=None
      Packages = nodes |> List.map (fun n -> n.Name, n) |> Map.ofList }

// ── single root, single dependent ─────────────────────────────────────────

[<Fact>]
let ``MAJOR root change yields MINOR proposal for direct dependent`` () =
    let g = graph [ node "A" v100 []; node "B" v100 ["A"] ]
    let proposals = CascadeEngine.computeProposals g ["A", ver 1 0 0, ver 2 0 0]
    proposals |> List.length |> should equal 1
    let p = proposals[0]
    p.PackageName    |> should equal "B"
    p.BumpType       |> should equal Minor
    p.ProposedVersion |> should equal (ver 1 1 0)

[<Fact>]
let ``MINOR root change yields PATCH proposal for direct dependent`` () =
    let g = graph [ node "A" v100 []; node "B" v100 ["A"] ]
    let proposals = CascadeEngine.computeProposals g ["A", ver 1 0 0, ver 1 1 0]
    proposals[0].BumpType |> should equal Patch
    proposals[0].ProposedVersion |> should equal (ver 1 0 1)

[<Fact>]
let ``PATCH root change yields PATCH proposal for direct dependent`` () =
    let g = graph [ node "A" v100 []; node "B" v100 ["A"] ]
    let proposals = CascadeEngine.computeProposals g ["A", ver 1 0 0, ver 1 0 1]
    proposals[0].BumpType |> should equal Patch

// ── transitive cascade ─────────────────────────────────────────────────────

[<Fact>]
let ``MAJOR root cascades two levels: MINOR then PATCH`` () =
    // A (root, MAJOR) → B (should get MINOR) → C (should get PATCH)
    let g = graph [ node "A" v100 []; node "B" v100 ["A"]; node "C" v100 ["B"] ]
    let proposals = CascadeEngine.computeProposals g ["A", ver 1 0 0, ver 2 0 0]
    proposals |> List.length |> should equal 2
    let b = proposals |> List.find (fun p -> p.PackageName = "B")
    let c = proposals |> List.find (fun p -> p.PackageName = "C")
    b.BumpType |> should equal Minor
    c.BumpType |> should equal Patch

// ── multi-root ─────────────────────────────────────────────────────────────

[<Fact>]
let ``multi-root: shared dependent takes max cascade bump`` () =
    // A (MAJOR) and B (PATCH) both affect C; MAJOR→Minor wins over PATCH→Patch
    let g = graph [ node "A" v100 []; node "B" v100 []; node "C" v100 ["A";"B"] ]
    let proposals = CascadeEngine.computeProposals g
                        ["A", ver 1 0 0, ver 2 0 0
                         "B", ver 1 0 0, ver 1 0 1]
    let c = proposals |> List.find (fun p -> p.PackageName = "C")
    c.BumpType |> should equal Minor

// ── no dependents ──────────────────────────────────────────────────────────

[<Fact>]
let ``leaf package with no dependents produces no proposals`` () =
    let g = graph [ node "A" v100 [] ]
    CascadeEngine.computeProposals g ["A", ver 1 0 0, ver 2 0 0]
    |> List.isEmpty |> should equal true

// ── reason string ─────────────────────────────────────────────────────────

[<Fact>]
let ``proposal reason mentions dependency name`` () =
    let g = graph [ node "A" v100 []; node "B" v100 ["A"] ]
    let proposals = CascadeEngine.computeProposals g ["A", ver 1 0 0, ver 2 0 0]
    proposals[0].Reason |> should haveSubstring "A"

// ── suffix preservation and non-cascading roots ───────────────────────────

[<Fact>]
let ``MINOR root change yields PATCH proposal that keeps beta`` () =
    // B is 1.2.0-beta. A's minor bump cascades to a patch and must keep beta.
    let beta = verPre 1 2 0 "beta"
    let g = graph [ node "A" v100 []; node "B" beta ["A"] ]
    let proposals = CascadeEngine.computeProposals g ["A", ver 1 0 0, ver 1 1 0]
    proposals |> List.length |> should equal 1
    let p = proposals[0]
    p.PackageName |> should equal "B"
    p.BumpType |> should equal Patch
    p.ProposedVersion |> should equal (verPre 1 2 1 "beta")

[<Fact>]
let ``suffix-only root produces no proposals`` () =
    // 1.2.0-beta → 1.2.0 changes only the suffix and is not a downgrade.
    let old = verPre 1 2 0 "beta"
    let g = graph [ node "A" old []; node "B" v100 ["A"] ]
    CascadeEngine.computeProposals g ["A", old, ver 1 2 0]
    |> List.isEmpty |> should equal true

[<Fact>]
let ``earlier numeric release produces no proposals`` () =
    // 1.2.0 → 1.1.0 is a downgrade and must not cascade.
    let old = ver 1 2 0
    let g = graph [ node "A" old []; node "B" v100 ["A"] ]
    CascadeEngine.computeProposals g ["A", old, ver 1 1 0]
    |> List.isEmpty |> should equal true

[<Fact>]
let ``earlier suffix release produces no proposals`` () =
    // 1.2.0 → 1.2.0-beta is a downgrade and must not cascade.
    let old = ver 1 2 0
    let beta = verPre 1 2 0 "beta"
    let g = graph [ node "A" old []; node "B" v100 ["A"] ]
    CascadeEngine.computeProposals g ["A", old, beta]
    |> List.isEmpty |> should equal true

[<Fact>]
let ``two dependency changes: larger numeric trigger wins`` () =
    // A (MAJOR) and B (MINOR) both affect C; MAJOR→Minor wins over MINOR→Patch.
    let g = graph [ node "A" v100 []; node "B" v100 []; node "C" v100 ["A";"B"] ]
    let proposals = CascadeEngine.computeProposals g
                        ["A", ver 1 0 0, ver 2 0 0
                         "B", ver 1 0 0, ver 1 1 0]
    let c = proposals |> List.find (fun p -> p.PackageName = "C")
    c.BumpType |> should equal Minor
    c.ProposedVersion |> should equal (ver 1 1 0)
