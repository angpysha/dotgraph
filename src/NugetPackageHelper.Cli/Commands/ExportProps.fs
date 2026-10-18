module NugetPackageHelper.Cli.Commands.ExportProps

open System.IO
open NugetPackageHelper.Core
open NugetPackageHelper.Cli

/// Write package versions from the snapshot into the configured props file.
let run () =
    let dir = Directory.GetCurrentDirectory()
    match GraphPersistence.load dir with
    | Error message ->
        Output.error message
        1
    | Ok graph ->
        match PropsExport.export graph dir with
        | Error message ->
            Output.error message
            1
        | Ok result ->
            for name in result.Warnings do
                Output.warn $"Package '{name}' also appears outside the Dotgraph item group."
            match result.Outcome with
            | PropsExport.NoPackages ->
                Output.success "No packages to write."
                0
            | PropsExport.AlreadyMatches ->
                Output.success "Props file already matches the saved list."
                0
            | PropsExport.Wrote count ->
                let stored =
                    match graph.PropsPath with
                    | Some p -> p
                    | None -> ""
                Output.success $"Wrote {count} package versions to {stored}"
                0
