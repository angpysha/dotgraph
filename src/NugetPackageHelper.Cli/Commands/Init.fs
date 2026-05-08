module NugetPackageHelper.Cli.Commands.Init

open System.IO
open Spectre.Console
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner
open NugetPackageHelper.Cli

let run (solutionOverride: string option) =
    let dir = Directory.GetCurrentDirectory()

    let slnResult =
        match solutionOverride with
        | Some p -> Ok p
        | None   -> SolutionScanner.findSolution dir

    match slnResult with
    | Error e -> Output.error e; 1
    | Ok slnPath ->
        match SolutionScanner.scan slnPath with
        | Error e -> Output.error e; 1
        | Ok projectPaths ->
            match ProjectScanner.buildGraph slnPath projectPaths with
            | Error e -> Output.error e; 1
            | Ok (graph, warnings) ->
                for w in warnings do Spectre.Console.AnsiConsole.MarkupLine $"[yellow]{Markup.Escape w}[/]"

                let arrow = " → "
                match Graph.detectCycle graph with
                | Some cycle ->
                    Output.error $"Circular dependency detected: {cycle |> String.concat arrow}"
                    1
                | None ->
                    for (name, node) in graph.Packages |> Map.toSeq do
                        let depCount = node.Dependencies.Length
                        Spectre.Console.AnsiConsole.MarkupLine(
                            $"  [green]✓[/] {Markup.Escape name}  [grey]v{Markup.Escape (SemVer.toString node.Version)}  ({depCount} internal deps)[/]")

                    match GraphPersistence.save graph dir with
                    | Error e -> Output.error e; 1
                    | Ok () ->
                        let pkg = graph.Packages.Count
                        let edges = graph.Packages |> Map.toSeq |> Seq.sumBy (fun (_, n) -> n.Dependencies.Length)
                        Output.success $"\nGraph saved to .dotgraph.json ({pkg} packages, {edges} edges)"
                        0
