module NugetPackageHelper.Cli.Interactive

open Spectre.Console
open NugetPackageHelper.Core

type Decision = Accept of SemVer | Manual of SemVer | Skip

let run
    (rootChanges: (string * SemVer * SemVer) list)
    (proposals: VersionProposal list)
    : (string * SemVer) list =

    AnsiConsole.MarkupLine "\n[bold]Root changes:[/]"
    for (name, old, new') in rootChanges do
        let bump      = SemVer.detectBump old new'
        let color     = match bump with Major -> "red" | Minor -> "yellow" | Patch -> "green"
        let bumpLabel = SemVer.bumpLabel bump
        let oldStr    = SemVer.toString old
        let newStr    = SemVer.toString new'
        AnsiConsole.MarkupLine(
            $"  [bold]{Markup.Escape name}[/]  " +
            $"{Markup.Escape oldStr} → [bold]{Markup.Escape newStr}[/]  [{color}]{bumpLabel}[/]")

    let decisions = System.Collections.Generic.List<string * SemVer>()

    for proposal in proposals do
        AnsiConsole.Write(Rule())
        AnsiConsole.MarkupLine $"\n[bold]Package:[/]  {Markup.Escape proposal.PackageName}"
        AnsiConsole.MarkupLine $"[bold]Current:[/]  {Markup.Escape (SemVer.toString proposal.CurrentVersion)}"
        let propStr = SemVer.toString proposal.ProposedVersion
        AnsiConsole.MarkupLine(
            $"[bold]Proposed:[/] [bold]{Markup.Escape propStr}[/]  " +
            $"[grey]{Markup.Escape proposal.Reason}[/]")

        let currStr   = SemVer.toString proposal.CurrentVersion
        let acceptLbl = $"Accept proposed → {propStr}"
        let skipLbl   = $"Skip (leave at {currStr})"

        let choice =
            AnsiConsole.Prompt(
                SelectionPrompt<string>()
                    .AddChoices([| acceptLbl; "Enter version manually"; skipLbl |]))

        if choice = acceptLbl then
            decisions.Add(proposal.PackageName, proposal.ProposedVersion)
        elif choice = "Enter version manually" then
            let mutable version = None
            while version.IsNone do
                let input = AnsiConsole.Ask<string>("[grey]Version:[/]")
                match SemVer.parse input with
                | Some v -> version <- Some v
                | None   -> AnsiConsole.MarkupLine "[red]Invalid semver. Use MAJOR.MINOR.PATCH[/]"
            decisions.Add(proposal.PackageName, version.Value)

    decisions |> Seq.toList

let confirmSummary
    (rootChanges: (string * SemVer * SemVer) list)
    (decisions: (string * SemVer) list)
    : bool =

    AnsiConsole.Write(Rule())
    AnsiConsole.MarkupLine "\n[bold]Summary of changes:[/]"
    for (name, _, new') in rootChanges do
        AnsiConsole.MarkupLine $"  [bold]{Markup.Escape name}[/]  → {Markup.Escape (SemVer.toString new')}  [grey](explicit)[/]"
    for (name, v) in decisions do
        AnsiConsole.MarkupLine $"  [bold]{Markup.Escape name}[/]  → {Markup.Escape (SemVer.toString v)}"

    let total = rootChanges.Length + decisions.Length
    AnsiConsole.Confirm $"\nApply {total} version change(s)?"
