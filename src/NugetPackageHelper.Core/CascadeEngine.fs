namespace NugetPackageHelper.Core

open System.Collections.Generic

module CascadeEngine =

    /// Compute cascade version proposals for all upstream dependents of one or more root changes.
    /// rootChanges: (packageName, oldVersion, newVersion)
    /// Proposals are returned in BFS level-order (direct dependents first).
    let computeProposals
        (graph: DependencyGraph)
        (rootChanges: (string * SemVer * SemVer) list)
        : VersionProposal list =

        let roots = rootChanges |> List.map (fun (n, _, _) -> n)
        let upstream = Graph.findUpstreamOrdered graph roots

        // Track the effective bump type for each package (roots + proposed dependents).
        // Record a root only for a numeric bump that is not a downgrade.
        // Suffix-only changes and earlier releases do not cascade.
        let effectiveBumps = Dictionary<string, BumpType>()
        for (name, old, new') in rootChanges do
            match SemVer.detectBump old new' with
            | Suffix -> ()
            | bump when SemVer.isDowngrade old new' -> ()
            | bump -> effectiveBumps[name] <- bump

        let proposals = ResizeArray<VersionProposal>()

        for pkgName in upstream do
            match Map.tryFind pkgName graph.Packages with
            | None -> ()
            | Some node ->
                let triggerBumps =
                    node.Dependencies
                    |> List.choose (fun dep ->
                        match effectiveBumps.TryGetValue dep with
                        | true, b -> Some (dep, b)
                        | _       -> None)

                if not triggerBumps.IsEmpty then
                    let maxTriggerBump =
                        triggerBumps |> List.map snd |> List.reduce SemVer.maxBump

                    let actualBump = SemVer.cascadeBump maxTriggerBump

                    let maxDepName, maxDepBump =
                        triggerBumps |> List.maxBy (fun (_, b) ->
                            match b with
                            | Major -> 2
                            | Minor -> 1
                            | Patch -> 0
                            | Suffix -> -1)

                    let depList = triggerBumps |> List.map fst |> String.concat ", "
                    let reason  = $"depends on {depList} ({SemVer.bumpLabel maxDepBump} bump)"

                    effectiveBumps[pkgName] <- actualBump

                    proposals.Add {
                        PackageName     = pkgName
                        CurrentVersion  = node.Version
                        ProposedVersion = SemVer.applyBump actualBump node.Version
                        BumpType        = actualBump
                        Reason          = reason
                    }

        proposals |> Seq.toList
