module NugetPackageHelper.Cli.Output

open Spectre.Console
open NugetPackageHelper.Core

let private bumpMarkup = function
    | Major -> "[red]MAJOR[/]"
    | Minor -> "[yellow]MINOR[/]"
    | Patch -> "[green]PATCH[/]"

let private vStr = SemVer.toString

let error (msg: string) =
    AnsiConsole.MarkupLine $"[red]Error:[/] {Markup.Escape msg}"

let warn (msg: string) =
    AnsiConsole.MarkupLine $"[yellow]Warning:[/] {Markup.Escape msg}"

let success (msg: string) =
    AnsiConsole.MarkupLine $"[green]{Markup.Escape msg}[/]"

let printProposals
    (rootChanges: (string * SemVer * SemVer) list)
    (proposals: VersionProposal list) =

    let table = Table().BorderColor(Color.Grey)
    table.AddColumn("Package") |> ignore
    table.AddColumn("From") |> ignore
    table.AddColumn("To") |> ignore
    table.AddColumn("Bump") |> ignore
    table.AddColumn("Reason") |> ignore

    for (name, old, new') in rootChanges do
        let bump = SemVer.detectBump old new'
        table.AddRow(
            $"[bold]{Markup.Escape name}[/]",
            Markup.Escape (vStr old),
            $"[bold]{Markup.Escape (vStr new')}[/]",
            bumpMarkup bump,
            "(explicit)"
        ) |> ignore

    for p in proposals do
        table.AddRow(
            Markup.Escape p.PackageName,
            Markup.Escape (vStr p.CurrentVersion),
            Markup.Escape (vStr p.ProposedVersion),
            bumpMarkup p.BumpType,
            Markup.Escape p.Reason
        ) |> ignore

    AnsiConsole.Write table

let printDiff (diff: SnapshotDiff) =
    if diff.Changed.IsEmpty then
        AnsiConsole.MarkupLine "[grey]No version changes detected vs snapshot.[/]"
    else
        AnsiConsole.MarkupLine "\n[bold]Changed packages (vs snapshot):[/]"
        for c in diff.Changed do
            AnsiConsole.MarkupLine(
                $"  [bold]{Markup.Escape c.PackageName}[/]  " +
                $"{Markup.Escape (vStr c.SnapshotVersion)} → " +
                $"[bold]{Markup.Escape (vStr c.CurrentVersion)}[/]  " +
                $"{bumpMarkup c.BumpType}")

    if diff.CascadeGaps <> [] then
        AnsiConsole.MarkupLine "\n[bold yellow]Cascade gaps (need version bumps):[/]"
        for p in diff.CascadeGaps do
            AnsiConsole.MarkupLine(
                $"  {Markup.Escape p.PackageName}  " +
                $"{Markup.Escape (vStr p.CurrentVersion)} → propose " +
                $"[bold]{Markup.Escape (vStr p.ProposedVersion)}[/]  " +
                $"{bumpMarkup p.BumpType}  [grey]{Markup.Escape p.Reason}[/]")

    if diff.AlreadyCovered <> [] then
        AnsiConsole.MarkupLine "\n[bold green]Already covered (no action needed):[/]"
        for p in diff.AlreadyCovered do
            AnsiConsole.MarkupLine(
                $"  {Markup.Escape p.PackageName}  " +
                $"{Markup.Escape (vStr p.CurrentVersion)} [green]✓[/]  " +
                $"[grey]{Markup.Escape p.Reason}[/]")

let confirm (msg: string) : bool =
    AnsiConsole.Confirm msg
