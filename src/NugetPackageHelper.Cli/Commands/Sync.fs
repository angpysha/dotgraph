module NugetPackageHelper.Cli.Commands.Sync

open System.IO
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner
open NugetPackageHelper.Cli

let private applyChanges
    (graph: DependencyGraph)
    (changes: (string * SemVer) list)
    (baseDir: string)
    : Result<DependencyGraph, string> =

    let mutable updatedPackages = graph.Packages
    let mutable firstError = None

    for (name, newVersion) in changes do
        if firstError.IsNone then
            match Map.tryFind name graph.Packages with
            | None -> firstError <- Some $"Package '{name}' not found in graph"
            | Some node ->
                match ProjectScanner.writeVersion node.ProjectPath newVersion with
                | Error e -> firstError <- Some e
                | Ok () ->
                    updatedPackages <- updatedPackages |> Map.add name { node with Version = newVersion }

    match firstError with
    | Some e -> Error e
    | None ->
        Ok { graph with Packages = updatedPackages; CreatedAt = System.DateTime.UtcNow }

let run (dryRun: bool) (interactive: bool) =
    let dir = Directory.GetCurrentDirectory()
    match GraphPersistence.load dir with
    | Error e -> Output.error e; 1
    | Ok snapshot ->
        match SolutionScanner.scan snapshot.SolutionPath with
        | Error e -> Output.error e; 1
        | Ok projectPaths ->
            match ProjectScanner.buildGraph snapshot.SolutionPath projectPaths with
            | Error e -> Output.error e; 1
            | Ok (liveGraph, _) ->
                let liveVersions = liveGraph.Packages |> Map.map (fun _ n -> n.Version)
                let diff = DiffEngine.computeDiff snapshot liveVersions

                if diff.Changed.IsEmpty then
                    Spectre.Console.AnsiConsole.MarkupLine "[grey]No changes detected vs snapshot. Nothing to sync.[/]"
                    Spectre.Console.AnsiConsole.MarkupLine "[grey]Run 'dotgraph refresh' if you added new projects.[/]"
                    0
                elif diff.CascadeGaps.IsEmpty then
                    Output.printDiff diff
                    Spectre.Console.AnsiConsole.MarkupLine "\n[green]All dependents are already bumped. No cascade gaps.[/]"
                    Spectre.Console.AnsiConsole.MarkupLine "[grey]Run 'dotgraph refresh' to update the snapshot baseline.[/]"
                    0
                else
                    let rootChanges =
                        diff.Changed |> List.map (fun c -> c.PackageName, c.SnapshotVersion, c.CurrentVersion)
                    let proposals = diff.CascadeGaps

                    let finalChanges =
                        if interactive then
                            let decisions = Interactive.run rootChanges proposals
                            if not (Interactive.confirmSummary rootChanges decisions) then None
                            else Some decisions
                        else
                            Output.printDiff diff
                            if dryRun then
                                Spectre.Console.AnsiConsole.MarkupLine "\n[grey]Dry run — no files changed.[/]"
                                None
                            else
                                if Output.confirm $"\nApply {proposals.Length} cascade version change(s)?" then
                                    Some (proposals |> List.map (fun p -> p.PackageName, p.ProposedVersion))
                                else None

                    match finalChanges with
                    | None -> 0
                    | Some changes ->
                        // Apply to graph that already reflects the manually changed root versions.
                        match applyChanges liveGraph changes dir with
                        | Error e -> Output.error e; 1
                        | Ok updatedGraph ->
                            match GraphPersistence.save updatedGraph dir with
                            | Error e -> Output.error e; 1
                            | Ok () ->
                                Output.success $"Applied {changes.Length} version change(s) and updated .dotgraph.json"
                                0
