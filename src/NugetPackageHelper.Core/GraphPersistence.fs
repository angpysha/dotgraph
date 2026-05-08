namespace NugetPackageHelper.Core

open System
open System.IO
open System.Text.Json
open System.Text.Json.Nodes

module GraphPersistence =

    let private fileName = ".dotgraph.json"

    let private findGraphFile (startDir: string) : string option =
        let candidate = Path.Combine(startDir, fileName)
        if File.Exists candidate then Some candidate else None

    // ── Serialisation ──────────────────────────────────────────────────────

    let private toJson (graph: DependencyGraph) (baseDir: string) : string =
        let root = JsonObject()
        root["solutionPath"] <- JsonValue.Create(Path.GetRelativePath(baseDir, graph.SolutionPath)) :> JsonNode
        root["createdAt"]    <- JsonValue.Create(graph.CreatedAt.ToUniversalTime().ToString("o")) :> JsonNode

        let pkgs = JsonObject()
        for (name, node) in graph.Packages |> Map.toSeq do
            let pkg = JsonObject()
            pkg["version"]     <- JsonValue.Create(SemVer.toString node.Version) :> JsonNode
            pkg["projectPath"] <- JsonValue.Create(Path.GetRelativePath(baseDir, node.ProjectPath)) :> JsonNode
            let deps = JsonArray()
            for dep in node.Dependencies do
                deps.Add(JsonValue.Create(dep) :> JsonNode)
            pkg["dependencies"] <- deps :> JsonNode
            pkgs[name] <- pkg :> JsonNode
        root["packages"] <- pkgs :> JsonNode
        root.ToJsonString(JsonSerializerOptions(WriteIndented = true))

    let private fromJson (json: string) (baseDir: string) : Result<DependencyGraph, string> =
        try
            let root = JsonNode.Parse json :?> JsonObject
            let slnRel    = root["solutionPath"].GetValue<string>()
            let createdAt = DateTime.Parse(root["createdAt"].GetValue<string>()).ToUniversalTime()
            let pkgsNode  = root["packages"] :?> JsonObject

            let packages =
                pkgsNode
                |> Seq.map (fun kv ->
                    let name = kv.Key
                    let pkg  = kv.Value :?> JsonObject
                    let version =
                        match SemVer.parse (pkg["version"].GetValue<string>()) with
                        | Some v -> v
                        | None   -> failwith $"Invalid version for package '{name}'"
                    let projectPath =
                        Path.GetFullPath(Path.Combine(baseDir, pkg["projectPath"].GetValue<string>()))
                    let deps =
                        pkg["dependencies"] :?> JsonArray
                        |> Seq.map (fun n -> n.GetValue<string>())
                        |> Seq.toList
                    name, { Name = name; Version = version; ProjectPath = projectPath; Dependencies = deps })
                |> Map.ofSeq

            Ok {
                SolutionPath = Path.GetFullPath(Path.Combine(baseDir, slnRel))
                CreatedAt    = createdAt
                Packages     = packages
            }
        with ex ->
            Error $"Failed to parse {fileName}: {ex.Message}"

    // ── Public API ─────────────────────────────────────────────────────────

    let save (graph: DependencyGraph) (baseDir: string) : Result<unit, string> =
        try
            let path = Path.Combine(baseDir, fileName)
            File.WriteAllText(path, toJson graph baseDir)
            Ok ()
        with ex ->
            Error $"Failed to write {fileName}: {ex.Message}"

    let load (baseDir: string) : Result<DependencyGraph, string> =
        match findGraphFile baseDir with
        | None      -> Error $"{fileName} not found. Run 'dotgraph init' first."
        | Some path ->
            try fromJson (File.ReadAllText path) baseDir
            with ex -> Error $"Failed to read {fileName}: {ex.Message}"
