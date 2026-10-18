module NugetPackageHelper.Cli.Commands.Propose

open System.IO
open Spectre.Console
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner
open NugetPackageHelper.Cli

type ProposalContext = {
    Directory: string
    Snapshot: DependencyGraph
    Live: DependencyGraph
    Xml: Map<string, BranchProposal.PackageXml>
    Changes: BranchProposal.ChangedPath list
    Report: BranchProposal.BranchReport
}

/// Resolve parent directory symlinks so /tmp and /private/tmp describe the same file.
let private physicalPath (path: string) =
    if System.String.IsNullOrEmpty path then ""
    else
        let full = Path.GetFullPath path
        let root = Path.GetPathRoot full
        let parts =
            full.Substring(root.Length).Split(Path.DirectorySeparatorChar, System.StringSplitOptions.RemoveEmptyEntries)
        let mutable current = root
        for part in parts do
            current <- Path.Combine(current, part)
            if File.Exists current || Directory.Exists current then
                let info : System.IO.FileSystemInfo =
                    if Directory.Exists current then DirectoryInfo(current)
                    else FileInfo(current)
                let link = info.ResolveLinkTarget true
                if not (isNull link) then
                    current <- link.FullName
        current

let private absolute (root: string) (relative: string) =
    if System.String.IsNullOrEmpty relative then ""
    else
        let parts = relative.Replace('\\', Path.DirectorySeparatorChar).Replace('/', Path.DirectorySeparatorChar)
        physicalPath (Path.Combine(root, parts))

let private readXml
    (workDir: string)
    (branchName: string)
    (live: DependencyGraph)
    : Result<Map<string, BranchProposal.PackageXml>, string> =

    let rec loop acc remaining =
        match remaining with
        | [] -> Ok (Map.ofList acc)
        | (name, node: PackageNode) :: rest ->
            let relative = Path.GetRelativePath(workDir, physicalPath node.ProjectPath).Replace('\\', '/')
            match GitWorktree.readTipText workDir branchName relative with
            | Error message -> Error message
            | Ok branchXml ->
                try
                    let liveXml = File.ReadAllText node.ProjectPath
                    let source = { BranchProposal.LiveXml = liveXml; BranchProposal.BranchXml = branchXml }
                    loop ((name, source) :: acc) rest
                with ex ->
                    Error $"Failed to read '{node.ProjectPath}': {ex.Message}"
    loop [] (live.Packages |> Map.toList)

let private unknownProjects (live: DependencyGraph) (changes: BranchProposal.ChangedPath list) =
    let known =
        live.Packages
        |> Map.toSeq
        |> Seq.map (fun (_, node) -> physicalPath node.ProjectPath)
        |> Set.ofSeq
    let isProject (path: string) =
        match Path.GetExtension(path).ToLowerInvariant() with
        | ".csproj" | ".fsproj" -> true
        | _ -> false
    changes
    |> List.collect (fun change -> [ change.OldPath; change.NewPath ])
    |> List.filter (fun path -> path <> "" && isProject path && not (known.Contains(physicalPath path)))
    |> List.map Path.GetFileNameWithoutExtension
    |> List.distinct
    |> List.sort
    |> List.map (fun name -> { BranchProposal.Name = name; BranchProposal.Detail = "not in the package graph" })

/// Load the snapshot, diff the saved branch, and build the in-memory proposal. Writes nothing.
let prepare () : Result<ProposalContext, string> =
    let dir = Directory.GetCurrentDirectory()
    match GraphPersistence.load dir with
    | Error message -> Error message
    | Ok snapshot ->
        let start = Path.GetDirectoryName snapshot.SolutionPath
        match GitWorktree.workingDirectory start with
        | Error message -> Error message
        | Ok rawWorkDir ->
            let workDir = physicalPath rawWorkDir
            match GitWorktree.changedPaths start snapshot.CompareBranch with
            | Error message -> Error message
            | Ok repoChanges ->
                match SolutionScanner.scan snapshot.SolutionPath with
                | Error message -> Error message
                | Ok projectPaths ->
                    match ProjectScanner.buildGraph snapshot.SolutionPath projectPaths with
                    | Error message -> Error message
                    | Ok (live, _) ->
                        let live = {
                            live with
                                Packages =
                                    live.Packages
                                    |> Map.map (fun _ node ->
                                        { node with ProjectPath = physicalPath node.ProjectPath })
                        }
                        match readXml workDir snapshot.CompareBranch live with
                        | Error message -> Error message
                        | Ok xml ->
                            let changes =
                                repoChanges
                                |> List.map (fun change ->
                                    { BranchProposal.OldPath = absolute workDir change.OldPath
                                      BranchProposal.NewPath = absolute workDir change.NewPath })
                            let report =
                                BranchProposal.propose
                                    live
                                    xml
                                    (snapshot.Packages |> Map.toList |> List.map fst)
                                    changes
                            let extras = unknownProjects live changes
                            let report = { report with Warnings = report.Warnings @ extras }
                            Ok {
                                Directory = dir
                                Snapshot = snapshot
                                Live = live
                                Xml = xml
                                Changes = changes
                                Report = report
                            }

let private versionsToWrite (report: BranchProposal.BranchReport) (declined: Set<string>) =
    let selected =
        report.Selected
        |> List.filter (fun item ->
            not item.AlreadyCurrent && not (Set.contains item.Name declined))
        |> List.map (fun item -> item.Name, item.ProposedVersion)
    let followUps =
        report.FollowUps
        |> List.filter (fun proposal ->
            SemVer.compare proposal.CurrentVersion proposal.ProposedVersion <> 0
            && not (Set.contains proposal.PackageName declined))
        |> List.map (fun proposal -> proposal.PackageName, proposal.ProposedVersion)
    selected @ followUps
    |> List.fold (fun acc (name, version) ->
        if List.exists (fun (existing, _) -> existing = name) acc then acc
        else (name, version) :: acc) []
    |> List.rev

let private declineEarlier (force: bool) (name: string) (live: SemVer) (proposed: SemVer) =
    if force || not (SemVer.isDowngrade live proposed) then
        false
    else
        Output.warn $"{name}: {SemVer.toString live} → {SemVer.toString proposed}"
        not (Output.confirm "Apply this earlier version?")

/// Write confirmed versions, then rescan so dependency links match the files. Does not keep a version-only graph.
let applyConfirmed (context: ProposalContext) (changes: (string * SemVer) list) =
    if changes.IsEmpty then
        AnsiConsole.WriteLine "Nothing will be written."
        0
    else
        let mutable failure = None
        for (name, version) in changes do
            if failure.IsNone then
                match Map.tryFind name context.Live.Packages with
                | None -> failure <- Some $"Package '{name}' not found in the live solution."
                | Some node ->
                    match ProjectScanner.writeVersion node.ProjectPath version with
                    | Error message -> failure <- Some message
                    | Ok () -> ()
        match failure with
        | Some message ->
            Output.error message
            1
        | None ->
            match SolutionScanner.scan context.Snapshot.SolutionPath with
            | Error message -> Output.error message; 1
            | Ok projectPaths ->
                match ProjectScanner.buildGraph context.Snapshot.SolutionPath projectPaths with
                | Error message -> Output.error message; 1
                | Ok (fresh, warnings) ->
                    for warning in warnings do
                        AnsiConsole.MarkupLine $"[yellow]{Markup.Escape warning}[/]"
                    match Graph.detectCycle fresh with
                    | Some cycle ->
                        let arrow = " → "
                        Output.error $"Circular dependency detected: {cycle |> String.concat arrow}"
                        1
                    | None ->
                        let refreshed =
                            { fresh with
                                CompareBranch = context.Snapshot.CompareBranch
                                PropsPath = context.Snapshot.PropsPath }
                        match GraphPersistence.save refreshed context.Directory with
                        | Error message -> Output.error message; 1
                        | Ok () ->
                            Output.success $"Applied {changes.Length} version change(s) and updated .dotgraph.json"
                            0

let private confirmAndApply (context: ProposalContext) (force: bool) =
    let declinedSelected =
        context.Report.Selected
        |> List.filter (fun item ->
            not item.AlreadyCurrent
            && declineEarlier force item.Name item.LiveVersion item.ProposedVersion)
        |> List.map (fun item -> item.Name)
        |> Set.ofList

    let decisions =
        declinedSelected
        |> Set.fold (fun acc name -> Map.add name BranchProposal.ReviewChoice.LeaveUnchanged acc) Map.empty

    let report =
        if Set.isEmpty declinedSelected then context.Report
        else
            BranchProposal.applyDecisions
                context.Live
                context.Xml
                (context.Snapshot.Packages |> Map.toList |> List.map fst)
                context.Changes
                decisions

    let declinedFollowUps =
        report.FollowUps
        |> List.filter (fun proposal ->
            declineEarlier force proposal.PackageName proposal.CurrentVersion proposal.ProposedVersion)
        |> List.map (fun proposal -> proposal.PackageName)
        |> Set.ofList

    let declined = Set.union declinedSelected declinedFollowUps
    let writes = versionsToWrite report declined
    if writes.IsEmpty then
        AnsiConsole.WriteLine "Nothing will be written."
        0
    elif Output.confirm "Apply these version changes?" then
        applyConfirmed context writes
    else
        AnsiConsole.WriteLine "Nothing was written."
        0

let run (dryRun: bool) (force: bool) =
    match prepare () with
    | Error message ->
        Output.error message
        1
    | Ok context ->
        Output.printBranchReport context.Snapshot.CompareBranch context.Report
        if dryRun then 0
        else confirmAndApply context force
