module NugetPackageHelper.Cli.Commands.PropsPath

open System.IO
open Spectre.Console
open NugetPackageHelper.Core
open NugetPackageHelper.Cli

/// Print, store, or clear the props file path on .dotgraph.json. Does not write the props file.
let run (path: string option) (clear: bool) =
    let dir = Directory.GetCurrentDirectory()

    if clear && path.IsSome then
        Output.error "Cannot use --clear together with a path."
        1
    else
        match GraphPersistence.load dir with
        | Error message ->
            Output.error message
            1
        | Ok graph ->
            if clear then
                match GraphPersistence.save { graph with PropsPath = None } dir with
                | Error message ->
                    Output.error message
                    1
                | Ok () ->
                    AnsiConsole.WriteLine "No props path is saved."
                    0
            else
                match path with
                | Some raw when System.String.IsNullOrWhiteSpace raw ->
                    Output.error "Props path cannot be empty."
                    1
                | Some raw ->
                    let trimmed = raw.Trim()
                    match GraphPersistence.save { graph with PropsPath = Some trimmed } dir with
                    | Error message ->
                        Output.error message
                        1
                    | Ok () ->
                        AnsiConsole.WriteLine trimmed
                        0
                | None ->
                    match graph.PropsPath with
                    | Some stored -> AnsiConsole.WriteLine stored; 0
                    | None ->
                        AnsiConsole.WriteLine "No props path is saved."
                        0
