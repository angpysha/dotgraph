module NugetPackageHelper.Cli.Commands.Diff

open System.IO
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner
open NugetPackageHelper.Cli

let run () =
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
                Output.printDiff diff
                if diff.CascadeGaps <> [] then
                    Spectre.Console.AnsiConsole.MarkupLine "\n[grey]Run 'dotgraph sync' to apply the proposed cascade bumps.[/]"
                0
