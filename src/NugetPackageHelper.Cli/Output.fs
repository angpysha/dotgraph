module NugetPackageHelper.Cli.Output

open Spectre.Console
open NugetPackageHelper.Core

/// Shared Spectre.Console words and colors for diff, proposals, and interactive review.
/// MAJOR is red, MINOR is yellow, PATCH is green, SUFFIX is grey, Error is red, Warning is yellow.
[<RequireQualifiedAccess>]
type ReviewLabel =
    | Bump of BumpType
    | Error
    | Warning

/// One helper owns the review words and their markup. The word remains when color is stripped.
let markup = function
    | ReviewLabel.Bump Major -> "[red]MAJOR[/]"
    | ReviewLabel.Bump Minor -> "[yellow]MINOR[/]"
    | ReviewLabel.Bump Patch -> "[green]PATCH[/]"
    | ReviewLabel.Bump Suffix -> "[grey]SUFFIX[/]"
    | ReviewLabel.Error -> "[red]Error[/]"
    | ReviewLabel.Warning -> "[yellow]Warning[/]"

let private prefixText (v: SemVer) =
    $"{v.Major}.{v.Minor}.{v.Patch}"

/// Absent or blank pre-release is the word none.
let private suffixText (v: SemVer) =
    match v.PreRelease with
    | Some pre when not (System.String.IsNullOrWhiteSpace pre) -> pre
    | _ -> "none"

let error (msg: string) =
    AnsiConsole.MarkupLine $"{markup ReviewLabel.Error}: {Markup.Escape msg}"

let warn (msg: string) =
    AnsiConsole.MarkupLine $"{markup ReviewLabel.Warning}: {Markup.Escape msg}"

let success (msg: string) =
    AnsiConsole.MarkupLine $"[green]{Markup.Escape msg}[/]"

let private addReviewRow
    (table: Table)
    (name: string)
    (current: SemVer)
    (proposed: SemVer)
    (bump: BumpType)
    (reason: string) =
    table.AddRow(
        name,
        Markup.Escape (prefixText current),
        Markup.Escape (suffixText current),
        Markup.Escape (prefixText proposed),
        Markup.Escape (suffixText proposed),
        markup (ReviewLabel.Bump bump),
        Markup.Escape reason
    ) |> ignore

let printProposals
    (rootChanges: (string * SemVer * SemVer) list)
    (proposals: VersionProposal list) =

    let table = Table().BorderColor(Color.Grey)
    table.AddColumn("Package") |> ignore
    table.AddColumn("Current prefix") |> ignore
    table.AddColumn("Current suffix") |> ignore
    table.AddColumn("Proposed prefix") |> ignore
    table.AddColumn("Proposed suffix") |> ignore
    table.AddColumn("Change") |> ignore
    table.AddColumn("Reason") |> ignore

    for (name, old, new') in rootChanges do
        addReviewRow
            table
            $"[bold]{Markup.Escape name}[/]"
            old
            new'
            (SemVer.detectBump old new')
            "(explicit)"

    for p in proposals do
        addReviewRow
            table
            (Markup.Escape p.PackageName)
            p.CurrentVersion
            p.ProposedVersion
            p.BumpType
            p.Reason

    AnsiConsole.Write table

let private printReviewLine
    (name: string)
    (current: SemVer)
    (proposed: SemVer)
    (bump: BumpType)
    (reason: string) =
    AnsiConsole.MarkupLine(
        $"  [bold]{Markup.Escape name}[/]  " +
        $"prefix {Markup.Escape (prefixText current)} → {Markup.Escape (prefixText proposed)}  " +
        $"suffix {Markup.Escape (suffixText current)} → {Markup.Escape (suffixText proposed)}  " +
        $"{markup (ReviewLabel.Bump bump)}  " +
        $"[grey]{Markup.Escape reason}[/]")

let printDiff (diff: SnapshotDiff) =
    if diff.Changed.IsEmpty then
        AnsiConsole.MarkupLine "[grey]No version changes detected vs snapshot.[/]"
    else
        AnsiConsole.MarkupLine "\n[bold]Changed packages (vs snapshot):[/]"
        for c in diff.Changed do
            printReviewLine
                c.PackageName
                c.SnapshotVersion
                c.CurrentVersion
                c.BumpType
                "changed vs snapshot"

    if diff.CascadeGaps <> [] then
        AnsiConsole.MarkupLine "\n[bold yellow]Cascade gaps (need version bumps):[/]"
        for p in diff.CascadeGaps do
            printReviewLine
                p.PackageName
                p.CurrentVersion
                p.ProposedVersion
                p.BumpType
                p.Reason

    if diff.AlreadyCovered <> [] then
        AnsiConsole.MarkupLine "\n[bold green]Already covered (no action needed):[/]"
        for p in diff.AlreadyCovered do
            printReviewLine
                p.PackageName
                p.CurrentVersion
                p.ProposedVersion
                p.BumpType
                p.Reason

let confirm (msg: string) : bool =
    AnsiConsole.Confirm msg

/// Branch proposal report. The change word stays visible when color is stripped.
let printBranchReport (branchName: string) (report: BranchProposal.BranchReport) =
    AnsiConsole.WriteLine $"Compare branch: {branchName}"
    AnsiConsole.MarkupLine "\n[bold]Selected:[/]"
    if report.Selected.IsEmpty then
        AnsiConsole.MarkupLine "  [grey](none)[/]"
    else
        for item in report.Selected do
            let branchText =
                match item.BranchVersion with
                | Some version -> SemVer.toString version
                | None -> "(none)"
            let currentText =
                match item.BranchVersion with
                | Some branch when SemVer.compare branch item.LiveVersion = 0 -> ""
                | _ -> $"   current {SemVer.toString item.LiveVersion}"
            let already = if item.AlreadyCurrent then "   already current" else ""
            AnsiConsole.MarkupLine(
                $"  [bold]{Markup.Escape item.Name}[/]   " +
                $"branch {Markup.Escape branchText}{Markup.Escape currentText}   " +
                $"→ {Markup.Escape (SemVer.toString item.ProposedVersion)}   " +
                $"{markup (ReviewLabel.Bump item.BumpType)}   " +
                $"{Markup.Escape item.Reason}{Markup.Escape already}")

    if report.FollowUps <> [] then
        AnsiConsole.MarkupLine "\n[bold]Follow-ups:[/]"
        for proposal in report.FollowUps do
            AnsiConsole.MarkupLine(
                $"  [bold]{Markup.Escape proposal.PackageName}[/]   " +
                $"{Markup.Escape (SemVer.toString proposal.CurrentVersion)} → {Markup.Escape (SemVer.toString proposal.ProposedVersion)}   " +
                $"{markup (ReviewLabel.Bump proposal.BumpType)}   " +
                $"{Markup.Escape proposal.Reason}")

    if report.Warnings <> [] then
        AnsiConsole.MarkupLine "\n[bold]Warnings:[/]"
        for warning in report.Warnings do
            warn $"{warning.Name}   {warning.Detail}"
