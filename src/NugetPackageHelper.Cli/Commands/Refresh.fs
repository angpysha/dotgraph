module NugetPackageHelper.Cli.Commands.Refresh

open System.IO
open Spectre.Console
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner
open NugetPackageHelper.Cli

let run (solutionOverride: string option) =
    let dir = Directory.GetCurrentDirectory()

    match GraphPersistence.load dir with
    | Error e -> Output.error e; 1
    | Ok snapshot ->
        let slnPath =
            match solutionOverride with
            | Some p -> p
            | None   -> snapshot.SolutionPath

        match SolutionScanner.scan slnPath with
        | Error e -> Output.error e; 1
        | Ok projectPaths ->
            match ProjectScanner.buildGraph slnPath projectPaths with
            | Error e -> Output.error e; 1
            | Ok (fresh, warnings) ->
                for w in warnings do
                    Spectre.Console.AnsiConsole.MarkupLine $"[yellow]{Markup.Escape w}[/]"

                let arrow = " → "
                match Graph.detectCycle fresh with
                | Some cycle ->
                    Output.error $"Circular dependency detected: {cycle |> String.concat arrow}"
                    1
                | None ->
                    match GraphPersistence.save fresh dir with
                    | Error e -> Output.error e; 1
                    | Ok () ->
                        let pkg = fresh.Packages.Count
                        Output.success $"Graph refreshed ({pkg} packages)"
                        0
