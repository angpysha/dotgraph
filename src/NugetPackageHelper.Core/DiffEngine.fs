namespace NugetPackageHelper.Core

module DiffEngine =

    /// Compare snapshot against live .csproj versions to produce a SnapshotDiff.
    /// liveVersions: Map of package name -> current version read from .csproj files.
    let computeDiff (snapshot: DependencyGraph) (liveVersions: Map<string, SemVer>) : SnapshotDiff =
        let changed =
            snapshot.Packages
            |> Map.toList
            |> List.choose (fun (name, node) ->
                match Map.tryFind name liveVersions with
                | Some live when SemVer.compare live node.Version <> 0 ->
                    Some {
                        PackageName     = name
                        SnapshotVersion = node.Version
                        CurrentVersion  = live
                        BumpType        = SemVer.detectBump node.Version live
                    }
                | _ -> None)

        if changed.IsEmpty then
            { Changed = []; CascadeGaps = []; AlreadyCovered = [] }
        else
            // Build a live graph (snapshot structure + live versions) for proposal computation.
            let updatedPackages =
                snapshot.Packages |> Map.map (fun name node ->
                    match Map.tryFind name liveVersions with
                    | Some live -> { node with Version = live }
                    | None      -> node)
            let liveGraph = { snapshot with Packages = updatedPackages }

            let rootChanges =
                changed |> List.map (fun c -> c.PackageName, c.SnapshotVersion, c.CurrentVersion)

            let proposals = CascadeEngine.computeProposals liveGraph rootChanges

            // Partition: gaps (still at snapshot version) vs already covered (user bumped them).
            let gaps, covered =
                proposals |> List.partition (fun p ->
                    match Map.tryFind p.PackageName snapshot.Packages with
                    | Some snapshotNode -> SemVer.compare p.CurrentVersion snapshotNode.Version = 0
                    | None             -> true)

            { Changed = changed; CascadeGaps = gaps; AlreadyCovered = covered }
