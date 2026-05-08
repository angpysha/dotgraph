namespace NugetPackageHelper.Core

open System.Collections.Generic

module Graph =

    let private buildReverseMap (graph: DependencyGraph) : Map<string, string list> =
        graph.Packages
        |> Map.fold (fun acc name node ->
            node.Dependencies |> List.fold (fun acc dep ->
                let existing = acc |> Map.tryFind dep |> Option.defaultValue []
                Map.add dep (name :: existing) acc
            ) acc
        ) Map.empty

    /// BFS upstream from roots; returns dependents in level-order (direct deps first).
    /// Roots themselves are excluded from the result.
    let findUpstreamOrdered (graph: DependencyGraph) (roots: string list) : string list =
        let reverseMap = buildReverseMap graph
        let visited = HashSet<string>(roots)
        let result  = ResizeArray<string>()
        let queue   = Queue<string>(roots)
        while queue.Count > 0 do
            let current = queue.Dequeue()
            match Map.tryFind current reverseMap with
            | Some dependents ->
                for dep in dependents do
                    if visited.Add dep then
                        result.Add dep
                        queue.Enqueue dep
            | None -> ()
        result |> Seq.toList

    /// DFS cycle detection. Returns the cycle path if one exists.
    let detectCycle (graph: DependencyGraph) : string list option =
        let White, Grey, Black = 0, 1, 2
        let color = Dictionary<string, int>()
        for name in graph.Packages |> Map.keys do
            color[name] <- White
        let mutable cycle = None
        let path = ResizeArray<string>()

        let rec dfs (name: string) =
            if cycle.IsNone then
                color[name] <- Grey
                path.Add name
                match Map.tryFind name graph.Packages with
                | Some node ->
                    for dep in node.Dependencies do
                        if cycle.IsNone then
                            match color.TryGetValue dep with
                            | true, c when c = Grey  ->
                                let idx = path.IndexOf dep
                                cycle <- Some (path |> Seq.skip idx |> Seq.toList)
                            | true, c when c = White -> dfs dep
                            | _ -> ()
                | None -> ()
                path.Remove name |> ignore
                color[name] <- Black

        for name in graph.Packages |> Map.keys do
            if color[name] = White && cycle.IsNone then dfs name
        cycle
