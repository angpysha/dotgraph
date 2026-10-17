module NugetPackageHelper.Cli.Commands.CompareBranch

open System.IO
open Spectre.Console
open NugetPackageHelper.Core
open NugetPackageHelper.Cli

/// Print or store the compare branch. Does not check that the branch exists and does not rescan.
let run (name: string option) =
    let dir = Directory.GetCurrentDirectory()
    match name with
    | Some raw when System.String.IsNullOrWhiteSpace raw ->
        Output.error "Branch name cannot be empty."
        1
    | Some raw ->
        match GraphPersistence.load dir with
        | Error message ->
            Output.error message
            1
        | Ok graph ->
            let trimmed = raw.Trim()
            match GraphPersistence.save { graph with CompareBranch = trimmed } dir with
            | Error message ->
                Output.error message
                1
            | Ok () ->
                AnsiConsole.WriteLine trimmed
                0
    | None ->
        match GraphPersistence.load dir with
        | Error message ->
            Output.error message
            1
        | Ok graph ->
            AnsiConsole.WriteLine graph.CompareBranch
            0
