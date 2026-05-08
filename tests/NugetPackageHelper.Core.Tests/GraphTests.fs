module NugetPackageHelper.Core.Tests.GraphTests

open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core

let private v100 = { Major=1; Minor=0; Patch=0; PreRelease=None }

let private node name deps : PackageNode =
    { Name = name; Version = v100; ProjectPath = $"/fake/{name}.csproj"; Dependencies = deps }

let private graph nodes : DependencyGraph =
    { SolutionPath="/fake/sol.slnx"
      CreatedAt=System.DateTime.UtcNow
      Packages = nodes |> List.map (fun n -> n.Name, n) |> Map.ofList }

// ── findUpstreamOrdered ────────────────────────────────────────────────────

[<Fact>]
let ``findUpstreamOrdered returns empty for leaf with no dependents`` () =
    let g = graph [ node "A" []; node "B" [] ]
    Graph.findUpstreamOrdered g ["A"] |> List.isEmpty |> should equal true

[<Fact>]
let ``findUpstreamOrdered returns direct dependent`` () =
    // B depends on A
    let g = graph [ node "A" []; node "B" ["A"] ]
    Graph.findUpstreamOrdered g ["A"] |> should equal ["B"]

[<Fact>]
let ``findUpstreamOrdered returns BFS level-order`` () =
    // A ← B ← C  (A is root, B direct dep, C transitive)
    let g = graph [ node "A" []; node "B" ["A"]; node "C" ["B"] ]
    Graph.findUpstreamOrdered g ["A"] |> should equal ["B"; "C"]

[<Fact>]
let ``findUpstreamOrdered handles diamond dependency`` () =
    // A ← B, A ← C, B ← D, C ← D
    let g = graph [ node "A" []; node "B" ["A"]; node "C" ["A"]; node "D" ["B";"C"] ]
    let result = Graph.findUpstreamOrdered g ["A"]
    // B and C appear before D; D appears exactly once
    let dIdx = result |> List.findIndex (fun x -> x = "D")
    let bIdx = result |> List.findIndex (fun x -> x = "B")
    let cIdx = result |> List.findIndex (fun x -> x = "C")
    bIdx |> should be (lessThan dIdx)
    cIdx |> should be (lessThan dIdx)
    result |> List.filter (fun x -> x = "D") |> List.length |> should equal 1

[<Fact>]
let ``findUpstreamOrdered handles multiple roots`` () =
    let g = graph [ node "A" []; node "B" []; node "C" ["A";"B"] ]
    Graph.findUpstreamOrdered g ["A";"B"] |> should equal ["C"]

// ── detectCycle ────────────────────────────────────────────────────────────

[<Fact>]
let ``detectCycle returns None for acyclic graph`` () =
    let g = graph [ node "A" []; node "B" ["A"]; node "C" ["B"] ]
    Graph.detectCycle g |> should equal None

[<Fact>]
let ``detectCycle detects direct cycle`` () =
    let g = graph [ node "A" ["B"]; node "B" ["A"] ]
    Graph.detectCycle g |> should not' (equal None)

[<Fact>]
let ``detectCycle detects indirect cycle`` () =
    let g = graph [ node "A" ["C"]; node "B" ["A"]; node "C" ["B"] ]
    Graph.detectCycle g |> should not' (equal None)

[<Fact>]
let ``detectCycle returns None for single node`` () =
    let g = graph [ node "A" [] ]
    Graph.detectCycle g |> should equal None
