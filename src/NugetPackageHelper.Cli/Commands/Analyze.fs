module NugetPackageHelper.Cli.Commands.Analyze

open System.IO
open Spectre.Console
open NugetPackageHelper.Core
open NugetPackageHelper.Cli

let run (packages: string list) =
    let dir = Directory.GetCurrentDirectory()
    let sep = ", "
    match GraphPersistence.load dir with
    | Error e -> Output.error e; 1
    | Ok graph ->
        let unknown = packages |> List.filter (fun p -> not (graph.Packages.ContainsKey p))
        if unknown <> [] then
            for name in unknown do
                let suggestions =
                    graph.Packages |> Map.keys
                    |> Seq.filter (fun k -> k.ToLower().Contains(name.ToLower()))
                    |> Seq.truncate 3
                    |> Seq.toList
                let hint = if suggestions.IsEmpty then "" else $"  Did you mean: {suggestions |> String.concat sep}?"
                Output.error $"Unknown package '{name}'.{hint}"
            1
        else
            let upstream = Graph.findUpstreamOrdered graph packages
            let pkgList = packages |> String.concat sep
            if upstream.IsEmpty then
                Spectre.Console.AnsiConsole.MarkupLine $"[grey]No packages depend on {pkgList}.[/]"
            else
                Spectre.Console.AnsiConsole.MarkupLine $"\n[bold]Packages affected by a change to {pkgList}:[/]\n"
                for name in upstream do
                    match Map.tryFind name graph.Packages with
                    | None -> ()
                    | Some node ->
                        let deps = node.Dependencies |> List.filter (fun d -> List.contains d packages || List.contains d upstream)
                        let depList = deps |> String.concat sep
                        Spectre.Console.AnsiConsole.MarkupLine(
                            $"  [bold]{Markup.Escape name}[/]  [grey]v{Markup.Escape (SemVer.toString node.Version)}[/]" +
                            $"  [grey](depends on {depList})[/]")
                Spectre.Console.AnsiConsole.MarkupLine $"\n[grey]{upstream.Length} package(s) would need version bumps.[/]"
            0
