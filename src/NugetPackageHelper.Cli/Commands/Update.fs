module NugetPackageHelper.Cli.Commands.Update

open System.IO
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner
open NugetPackageHelper.Cli

let private traverseResults (f: 'a -> Result<'b, string>) (list: 'a list) : Result<'b list, string> =
    let rec loop acc = function
        | [] -> Ok (List.rev acc)
        | head :: tail ->
            match f head with
            | Error e -> Error e
            | Ok v    -> loop (v :: acc) tail
    loop [] list

/// Parse variadic "<pkg> <version> [<pkg> <version>...]" args.
let parsePackageVersionPairs (args: string[]) : Result<(string * SemVer) list, string> =
    if args.Length = 0 then Error "Specify at least one <package> <version> pair."
    elif args.Length % 2 <> 0 then Error "Arguments must be <package> <version> pairs (even count required)."
    else
        args
        |> Array.chunkBySize 2
        |> Array.toList
        |> traverseResults (fun pair ->
            match SemVer.parse pair[1] with
            | None   -> Error $"Invalid version '{pair[1]}' for package '{pair[0]}'."
            | Some v -> Ok (pair[0], v))

let private applyAll (graph: DependencyGraph) (allChanges: (string * SemVer) list) : Result<DependencyGraph, string> =
    let mutable updatedPackages = graph.Packages
    let mutable firstError = None
    for (name, newVersion) in allChanges do
        if firstError.IsNone then
            match Map.tryFind name graph.Packages with
            | None -> firstError <- Some $"Package '{name}' not found in graph"
            | Some node ->
                match ProjectScanner.writeVersion node.ProjectPath newVersion with
                | Error e -> firstError <- Some e
                | Ok ()   ->
                    updatedPackages <- Map.add name { node with Version = newVersion } updatedPackages
    match firstError with
    | Some e -> Error e
    | None   -> Ok { graph with Packages = updatedPackages; CreatedAt = System.DateTime.UtcNow }

let private explicitDiffering (graph: DependencyGraph) (pairs: (string * SemVer) list) =
    pairs
    |> List.filter (fun (name, newVer) ->
        SemVer.compare graph.Packages[name].Version newVer <> 0)

let run (args: string[]) (dryRun: bool) (interactive: bool) (force: bool) =
    let dir = Directory.GetCurrentDirectory()
    match GraphPersistence.load dir with
    | Error e -> Output.error e; 1
    | Ok graph ->
        match parsePackageVersionPairs args with
        | Error e -> Output.error e; 1
        | Ok pairs ->
            let unknown = pairs |> List.filter (fun (name, _) -> not (graph.Packages.ContainsKey name))
            if unknown <> [] then
                for (name, _) in unknown do Output.error $"Unknown package '{name}'."
                1
            else
                let downgrades =
                    pairs |> List.filter (fun (name, newVer) ->
                        graph.Packages
                        |> Map.tryFind name
                        |> Option.exists (fun n -> SemVer.isDowngrade n.Version newVer))
                if downgrades <> [] && not force && not interactive then
                    for (name, v) in downgrades do
                        let curr = graph.Packages[name].Version
                        Output.warn $"{name}: {SemVer.toString curr} → {SemVer.toString v} is a downgrade. Use --force to apply."
                    1
                else
                    let rootChanges =
                        pairs |> List.map (fun (name, newVer) ->
                            name, graph.Packages[name].Version, newVer)
                    let proposals = CascadeEngine.computeProposals graph rootChanges
                    let differing = explicitDiffering graph pairs

                    let finalChanges =
                        if interactive then
                            if dryRun then
                                Output.printProposals rootChanges proposals
                                None
                            else
                                let decisions = Interactive.run rootChanges proposals force
                                if Interactive.confirmSummary rootChanges proposals decisions then
                                    Some (List.append differing decisions)
                                else None
                        else
                            Output.printProposals rootChanges proposals
                            if dryRun then
                                None
                            else
                                let cascadeChanges =
                                    proposals |> List.map (fun p -> p.PackageName, p.ProposedVersion)
                                let total = differing.Length + cascadeChanges.Length
                                if total = 0 then
                                    None
                                elif Output.confirm $"\nApply all {total} version change(s)?" then
                                    Some (List.append differing cascadeChanges)
                                else None

                    match finalChanges with
                    | None -> 0
                    | Some allChanges ->
                        match applyAll graph allChanges with
                        | Error e -> Output.error e; 1
                        | Ok updatedGraph ->
                            match GraphPersistence.save updatedGraph dir with
                            | Error e -> Output.error e; 1
                            | Ok () ->
                                Output.success $"Applied {allChanges.Length} version change(s) and updated .dotgraph.json"
                                0
