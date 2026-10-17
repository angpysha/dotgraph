module NugetPackageHelper.Core.Tests.BranchProposalTests

open System.IO
open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core

let private ver major minor patch =
    { Major = major; Minor = minor; Patch = patch; PreRelease = None }

let private verPre major minor patch pre =
    { Major = major; Minor = minor; Patch = patch; PreRelease = Some pre }

let private xml (version: string) =
    $"""<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><Version>{version}</Version></PropertyGroup></Project>"""

let private node name version deps path : PackageNode =
    { Name = name; Version = version; ProjectPath = path; Dependencies = deps }

let private graph nodes : DependencyGraph =
    { SolutionPath = "/repo/App.slnx"
      CreatedAt = System.DateTime.UtcNow
      CompareBranch = "main"
      Packages = nodes |> List.map (fun n -> n.Name, n) |> Map.ofList }

let private source (liveXml: string) (branchXml: string option) : BranchProposal.PackageXml =
    { LiveXml = liveXml; BranchXml = branchXml }

let private changed oldPath newPath : BranchProposal.ChangedPath =
    { OldPath = oldPath; NewPath = newPath }

let private propose nodes xml changedPaths =
    let g = graph nodes
    BranchProposal.propose g xml [] changedPaths

[<Fact>]
let ``longest project directory prefix selects the package`` () =
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let nestedPath = Path.Combine("/repo", "src", "Core", "Nested", "Nested.csproj")
    let nodes = [
        node "Core" (ver 1 0 0) [] corePath
        node "Nested" (ver 1 0 0) [] nestedPath
    ]
    let xml =
        Map.ofList [
            "Core", source (xml "1.0.0") (Some (xml "1.0.0"))
            "Nested", source (xml "1.0.0") (Some (xml "1.0.0"))
        ]
    let nestedFile = Path.Combine("/repo", "src", "Core", "Nested", "Foo.cs")
    let coreFile = Path.Combine("/repo", "src", "Core", "Bar.cs")
    let outside = Path.Combine("/repo", "src", "Other", "X.cs")
    let report =
        propose nodes xml [
            changed nestedFile nestedFile
            changed coreFile coreFile
            changed outside outside
        ]

    let names = report.Selected |> List.map (fun s -> s.Name) |> List.sort
    names |> should equal [ "Core"; "Nested" ]
    report.Selected |> List.exists (fun s -> s.Name = "Core" && s.Reason = "code changed") |> should equal true
    report.Selected |> List.exists (fun s -> s.Name = "Nested" && s.Reason = "code changed") |> should equal true

[<Fact>]
let ``version-tag-only project file is not selected`` () =
    let path = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let nodes = [ node "Core" (ver 1 5 0) [] path ]
    let xml = Map.ofList [ "Core", source (xml "1.5.0") (Some (xml "1.4.2")) ]
    let report = propose nodes xml [ changed path path ]
    report.Selected |> should be Empty

[<Fact>]
let ``project file with a non-version difference is selected`` () =
    let path = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let nodes = [ node "Core" (ver 1 4 2) [] path ]
    let live =
        """<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><Version>1.4.2</Version><Description>now</Description></PropertyGroup></Project>"""
    let branch =
        """<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><Version>1.4.2</Version><Description>then</Description></PropertyGroup></Project>"""
    let xml = Map.ofList [ "Core", source live (Some branch) ]
    let report = propose nodes xml [ changed path path ]
    report.Selected |> List.map (fun s -> s.Name) |> should equal [ "Core" ]

[<Fact>]
let ``branch 1.4.2 with live 9.0.0 proposes one patch`` () =
    let path = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let nodes = [ node "Core" (ver 9 0 0) [] path ]
    let xml = Map.ofList [ "Core", source (xml "9.0.0") (Some (xml "1.4.2")) ]
    let report = propose nodes xml [ changed file file ]
    report.Selected |> List.length |> should equal 1
    let selected = report.Selected[0]
    selected.Name |> should equal "Core"
    selected.BranchVersion |> should equal (Some (ver 1 4 2))
    selected.LiveVersion |> should equal (ver 9 0 0)
    selected.ProposedVersion |> should equal (ver 1 4 3)
    selected.BumpType |> should equal Patch
    selected.Reason |> should equal "code changed"
    selected.AlreadyCurrent |> should equal false

[<Fact>]
let ``pre-release branch version keeps its label on the patch`` () =
    let path = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let branchVer = verPre 2 0 0 "beta.1"
    let nodes = [ node "Core" branchVer [] path ]
    let xml = Map.ofList [ "Core", source (xml "2.0.0-beta.1") (Some (xml "2.0.0-beta.1")) ]
    let report = propose nodes xml [ changed file file ]
    let selected = report.Selected[0]
    selected.ProposedVersion |> should equal (verPre 2 0 1 "beta.1")
    selected.BumpType |> should equal Patch

[<Fact>]
let ``project absent from the branch proposes 1.0.0`` () =
    let path = Path.Combine("/repo", "src", "Extra", "Extra.csproj")
    let nodes = [ node "Extra" (ver 0 1 0) [] path ]
    let xml = Map.ofList [ "Extra", source (xml "0.1.0") None ]
    let report = propose nodes xml []
    report.Selected |> List.length |> should equal 1
    let selected = report.Selected[0]
    selected.Name |> should equal "Extra"
    selected.BranchVersion |> should equal None
    selected.LiveVersion |> should equal (ver 0 1 0)
    selected.ProposedVersion |> should equal (ver 1 0 0)
    selected.BumpType |> should equal Major
    selected.Reason |> should equal "new package"
    selected.AlreadyCurrent |> should equal false

[<Fact>]
let ``follow-up row uses the live version`` () =
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let httpPath = Path.Combine("/repo", "src", "Http", "Http.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let nodes = [
        node "Core" (ver 9 0 0) [] corePath
        node "Http" (ver 3 0 0) [ "Core" ] httpPath
    ]
    let xml =
        Map.ofList [
            "Core", source (xml "9.0.0") (Some (xml "1.4.2"))
            "Http", source (xml "3.0.0") (Some (xml "3.0.0"))
        ]
    let report = propose nodes xml [ changed file file ]
    report.FollowUps |> List.length |> should equal 1
    let follow = report.FollowUps[0]
    follow.PackageName |> should equal "Http"
    follow.CurrentVersion |> should equal (ver 3 0 0)
    follow.ProposedVersion |> should equal (ver 3 0 1)
    follow.BumpType |> should equal Patch

[<Fact>]
let ``package already at the proposed patch is not written and still cascades`` () =
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let httpPath = Path.Combine("/repo", "src", "Http", "Http.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let nodes = [
        node "Core" (ver 1 4 3) [] corePath
        node "Http" (ver 3 0 0) [ "Core" ] httpPath
    ]
    let xml =
        Map.ofList [
            "Core", source (xml "1.4.3") (Some (xml "1.4.2"))
            "Http", source (xml "3.0.0") (Some (xml "3.0.0"))
        ]
    let report = propose nodes xml [ changed file file ]
    let core = report.Selected |> List.find (fun item -> item.Name = "Core")
    core.ProposedVersion |> should equal (ver 1 4 3)
    core.AlreadyCurrent |> should equal true
    report.FollowUps |> List.length |> should equal 1
    let follow = report.FollowUps[0]
    follow.PackageName |> should equal "Http"
    follow.CurrentVersion |> should equal (ver 3 0 0)
    follow.ProposedVersion |> should equal (ver 3 0 1)
    follow.BumpType |> should equal Patch

[<Fact>]
let ``leave unchanged at the branch version is not a cascade root`` () =
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let httpPath = Path.Combine("/repo", "src", "Http", "Http.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let nodes = [
        node "Core" (ver 1 4 2) [] corePath
        node "Http" (ver 3 0 0) [ "Core" ] httpPath
    ]
    let xml =
        Map.ofList [
            "Core", source (xml "1.4.2") (Some (xml "1.4.2"))
            "Http", source (xml "3.0.0") (Some (xml "3.0.0"))
        ]
    let decisions = Map.ofList [ "Core", BranchProposal.ReviewChoice.LeaveUnchanged ]
    let report = BranchProposal.applyDecisions (graph nodes) xml [] [ changed file file ] decisions
    report.FollowUps |> should be Empty
    report.Selected |> List.find (fun item -> item.Name = "Core") |> fun core ->
        core.AlreadyCurrent |> should equal false

[<Fact>]
let ``selected dependent takes the higher of patch and follow-up on the branch version`` () =
    let absPath = Path.Combine("/repo", "src", "Abstractions", "Abstractions.csproj")
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let nodes = [
        node "Abstractions" (ver 0 1 0) [] absPath
        node "Core" (ver 1 4 2) [ "Abstractions" ] corePath
    ]
    let xml =
        Map.ofList [
            "Abstractions", source (xml "0.1.0") None
            "Core", source (xml "1.4.2") (Some (xml "1.4.2"))
        ]
    let report = propose nodes xml [ changed file file ]
    let core = report.Selected |> List.find (fun item -> item.Name = "Core")
    core.ProposedVersion |> should equal (ver 1 5 0)
    core.BumpType |> should equal Minor
    core.BranchVersion |> should equal (Some (ver 1 4 2))

let private row name (rows: BranchProposal.ReviewRow list) =
    rows |> List.find (fun item -> item.Name = name)

[<Fact>]
let ``typed major recalculates a later dependent before it is answered`` () =
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let httpPath = Path.Combine("/repo", "src", "Http", "Http.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let nodes = [
        node "Core" (ver 1 0 0) [] corePath
        node "Http" (ver 3 0 0) [ "Core" ] httpPath
    ]
    let xml =
        Map.ofList [
            "Core", source (xml "1.0.0") (Some (xml "1.0.0"))
            "Http", source (xml "3.0.0") (Some (xml "3.0.0"))
        ]
    let decisions = Map.ofList [ "Core", BranchProposal.ReviewChoice.Entered (ver 2 0 0) ]
    let rows = BranchProposal.reviewRows (graph nodes) xml [] [ changed file file ] decisions
    let http = row "Http" rows
    http.ProposedVersion |> should equal (ver 3 1 0)
    http.BumpType |> should equal Minor
    http.LiveVersion |> should equal (ver 3 0 0)
    (rows |> List.filter (fun item -> item.Name = "Http") |> List.length) |> should equal 1

[<Fact>]
let ``review leave unchanged at the branch version drops the follow-up`` () =
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let httpPath = Path.Combine("/repo", "src", "Http", "Http.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let nodes = [
        node "Core" (ver 1 0 0) [] corePath
        node "Http" (ver 3 0 0) [ "Core" ] httpPath
    ]
    let xml =
        Map.ofList [
            "Core", source (xml "1.0.0") (Some (xml "1.0.0"))
            "Http", source (xml "3.0.0") (Some (xml "3.0.0"))
        ]
    let decisions = Map.ofList [ "Core", BranchProposal.ReviewChoice.LeaveUnchanged ]
    let rows = BranchProposal.reviewRows (graph nodes) xml [] [ changed file file ] decisions
    rows |> List.exists (fun item -> item.Name = "Http") |> should equal false

[<Fact>]
let ``review leave unchanged at the proposed patch still feeds that patch`` () =
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let httpPath = Path.Combine("/repo", "src", "Http", "Http.csproj")
    let file = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let nodes = [
        node "Core" (ver 1 0 1) [] corePath
        node "Http" (ver 3 0 0) [ "Core" ] httpPath
    ]
    let xml =
        Map.ofList [
            "Core", source (xml "1.0.1") (Some (xml "1.0.0"))
            "Http", source (xml "3.0.0") (Some (xml "3.0.0"))
        ]
    let decisions = Map.ofList [ "Core", BranchProposal.ReviewChoice.LeaveUnchanged ]
    let rows = BranchProposal.reviewRows (graph nodes) xml [] [ changed file file ] decisions
    let http = row "Http" rows
    http.ProposedVersion |> should equal (ver 3 0 1)
    http.BumpType |> should equal Patch

[<Fact>]
let ``a package is not offered twice`` () =
    let corePath = Path.Combine("/repo", "src", "Core", "Core.csproj")
    let httpPath = Path.Combine("/repo", "src", "Http", "Http.csproj")
    let coreFile = Path.Combine("/repo", "src", "Core", "Foo.cs")
    let httpFile = Path.Combine("/repo", "src", "Http", "Bar.cs")
    let nodes = [
        node "Core" (ver 1 0 0) [] corePath
        node "Http" (ver 3 0 0) [ "Core" ] httpPath
    ]
    let xml =
        Map.ofList [
            "Core", source (xml "1.0.0") (Some (xml "1.0.0"))
            "Http", source (xml "3.0.0") (Some (xml "3.0.0"))
        ]
    let rows =
        BranchProposal.reviewRows (graph nodes) xml [] [
            changed coreFile coreFile
            changed httpFile httpFile
        ] Map.empty
    let names = rows |> List.map (fun item -> item.Name)
    names |> List.distinct |> List.length |> should equal names.Length
    names |> should contain "Core"
    names |> should contain "Http"
    // Http depends on Core, so Core is offered first.
    (names |> List.findIndex ((=) "Core")) |> should be (lessThan (names |> List.findIndex ((=) "Http")))
