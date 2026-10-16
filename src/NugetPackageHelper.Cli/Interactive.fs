module NugetPackageHelper.Cli.Interactive

open Spectre.Console
open NugetPackageHelper.Core

let private prefixText (v: SemVer) =
    $"{v.Major}.{v.Minor}.{v.Patch}"

/// Absent or blank pre-release is the word none.
let private suffixText (v: SemVer) =
    match v.PreRelease with
    | Some pre when not (System.String.IsNullOrWhiteSpace pre) -> pre
    | _ -> "none"

/// Change word from Output. An earlier release uses Warning. Equal versions have no bump word.
/// knownBump is the proposal bump when the caller must display the given proposal as-is.
let private changeMarkup (current: SemVer) (next: SemVer) (knownBump: BumpType option) =
    if SemVer.compare current next = 0 then
        ""
    elif SemVer.isDowngrade current next then
        Output.markup Output.ReviewLabel.Warning
    else
        let bump =
            match knownBump with
            | Some bump -> bump
            | None -> SemVer.detectBump current next
        Output.markup (Output.ReviewLabel.Bump bump)

let private printVersionChange
    (name: string)
    (current: SemVer)
    (next: SemVer)
    (knownBump: BumpType option)
    (note: string) =
    let word = changeMarkup current next knownBump
    let wordPart = if word = "" then "" else $"  {word}"
    let notePart = if note = "" then "" else $"  [grey]({note})[/]"
    AnsiConsole.MarkupLine(
        $"  [bold]{Markup.Escape name}[/]  " +
        $"prefix {Markup.Escape (prefixText current)} → {Markup.Escape (prefixText next)}  " +
        $"suffix {Markup.Escape (suffixText current)} → {Markup.Escape (suffixText next)}" +
        wordPart +
        notePart)

let private printVersionStay (name: string) (current: SemVer) =
    AnsiConsole.MarkupLine(
        $"  [bold]{Markup.Escape name}[/]  " +
        $"prefix {Markup.Escape (prefixText current)}  " +
        $"suffix {Markup.Escape (suffixText current)}")

let private printProposalScreen (index: int) (total: int) (proposal: VersionProposal) =
    AnsiConsole.Write(Rule())
    AnsiConsole.MarkupLine $"\n[bold]Package {index} of {total}[/]"
    AnsiConsole.MarkupLine $"Current prefix: {Markup.Escape (prefixText proposal.CurrentVersion)}"
    AnsiConsole.MarkupLine $"Current suffix: {Markup.Escape (suffixText proposal.CurrentVersion)}"
    AnsiConsole.MarkupLine $"Proposed prefix: {Markup.Escape (prefixText proposal.ProposedVersion)}"
    AnsiConsole.MarkupLine $"Proposed suffix: {Markup.Escape (suffixText proposal.ProposedVersion)}"
    AnsiConsole.MarkupLine(Output.markup (Output.ReviewLabel.Bump proposal.BumpType))
    AnsiConsole.MarkupLine $"[grey]{Markup.Escape proposal.Reason}[/]"

/// Show named roots, then one follow-up package at a time.
/// Returns accepted and typed versions that differ from the package's current version.
/// force accepts an earlier typed version without the extra confirmation.
let run
    (rootChanges: (string * SemVer * SemVer) list)
    (proposals: VersionProposal list)
    (force: bool)
    : (string * SemVer) list =

    if not (List.isEmpty rootChanges) then
        AnsiConsole.MarkupLine "\n[bold]Root changes:[/]"
        for (name, old, new') in rootChanges do
            printVersionChange name old new' None ""
            if SemVer.isDowngrade old new' then
                Output.warn $"{name}: {SemVer.toString old} → {SemVer.toString new'}"

    let decisions = System.Collections.Generic.List<string * SemVer>()
    let total = proposals.Length
    let acceptChoice = "Accept proposed"
    let enterChoice = "Enter a version"
    let leaveChoice = "Leave unchanged"

    let rec askChoice (proposal: VersionProposal) : SemVer option =
        let choice =
            AnsiConsole.Prompt(
                SelectionPrompt<string>()
                    .Title("Choose:")
                    .AddChoices([| acceptChoice; enterChoice; leaveChoice |]))

        if choice = acceptChoice then
            Some proposal.ProposedVersion
        elif choice = leaveChoice then
            None
        else
            askTyped proposal

    and askTyped (proposal: VersionProposal) : SemVer option =
        let input = AnsiConsole.Ask<string>("[grey]Version:[/]")
        match SemVer.parse input with
        | None ->
            Output.error "Invalid version. Example: 1.2.3 or 1.2.3-beta.1"
            askTyped proposal
        | Some v when SemVer.compare v proposal.CurrentVersion = 0 ->
            None
        | Some v when not force && SemVer.isDowngrade proposal.CurrentVersion v ->
            Output.warn $"{SemVer.toString proposal.CurrentVersion} → {SemVer.toString v}"
            if Output.confirm "Apply this earlier version?" then
                Some v
            else
                askChoice proposal
        | Some v ->
            Some v

    for index, proposal in List.indexed proposals do
        printProposalScreen (index + 1) total proposal
        match askChoice proposal with
        | Some chosen when SemVer.compare chosen proposal.CurrentVersion <> 0 ->
            decisions.Add(proposal.PackageName, chosen)
        | _ -> ()

    decisions |> Seq.toList

/// Group explicit roots, accepted proposals, and typed versions.
/// Returns false without asking when nothing will change.
let confirmSummary
    (rootChanges: (string * SemVer * SemVer) list)
    (proposals: VersionProposal list)
    (decisions: (string * SemVer) list)
    : bool =

    let decisionMap =
        decisions
        |> List.fold (fun acc (name, version) -> Map.add name version acc) Map.empty

    let changingRoots =
        rootChanges |> List.filter (fun (_, old, new') -> SemVer.compare old new' <> 0)

    let unchangedRoots =
        rootChanges |> List.filter (fun (_, old, new') -> SemVer.compare old new' = 0)

    let acceptedOrTyped =
        proposals
        |> List.choose (fun proposal ->
            Map.tryFind proposal.PackageName decisionMap
            |> Option.map (fun chosen -> proposal, chosen))

    let skipped =
        proposals
        |> List.filter (fun proposal -> not (Map.containsKey proposal.PackageName decisionMap))

    AnsiConsole.Write(Rule())
    AnsiConsole.MarkupLine "\n[bold]Will change[/]"
    for (name, old, new') in changingRoots do
        printVersionChange name old new' None "explicit"

    for (proposal, chosen) in acceptedOrTyped do
        let how, bump =
            if SemVer.compare chosen proposal.ProposedVersion = 0 then
                "accepted", Some proposal.BumpType
            else
                "typed", None
        printVersionChange proposal.PackageName proposal.CurrentVersion chosen bump how

    AnsiConsole.MarkupLine "\n[bold]Left unchanged[/]"
    for (name, current, _) in unchangedRoots do
        printVersionStay name current

    for proposal in skipped do
        printVersionStay proposal.PackageName proposal.CurrentVersion

    if List.isEmpty changingRoots && List.isEmpty acceptedOrTyped then
        AnsiConsole.MarkupLine "Nothing will be written."
        false
    else
        let apply = Output.confirm "\nApply these version changes?"
        if not apply then
            AnsiConsole.MarkupLine "Nothing was written."
        apply
