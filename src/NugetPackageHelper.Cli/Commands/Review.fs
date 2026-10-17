module NugetPackageHelper.Cli.Commands.Review

open NugetPackageHelper.Cli

/// Review only the branch-selected packages and their follow-ups. Writes after confirmation.
let run (force: bool) =
    match Propose.prepare () with
    | Error message ->
        Output.error message
        1
    | Ok context ->
        let snapshotNames = context.Snapshot.Packages |> Map.toList |> List.map fst
        let writes =
            Interactive.runBranchReview
                context.Live
                context.Xml
                snapshotNames
                context.Changes
                force
        if List.isEmpty writes then
            0
        else
            Propose.applyConfirmed context writes
