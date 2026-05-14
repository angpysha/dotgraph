namespace NugetPackageHelper.Scanner

open System.IO
open System.Xml.Linq
open NugetPackageHelper.Core

module ProjectScanner =

    type ScanResult = {
        Node: PackageNode
        HasVersion: bool
        Warnings: string list
    }

    let private resolveName (projPath: string) (doc: XDocument) =
        let find tag =
            doc.Descendants(XName.Get tag)
            |> Seq.tryHead
            |> Option.map (fun el -> el.Value.Trim())
            |> Option.filter (fun s -> s.Length > 0)
        find "PackageId"
        |> Option.orElseWith (fun () -> find "AssemblyName")
        |> Option.defaultWith (fun () -> Path.GetFileNameWithoutExtension projPath)

    let private resolveVersion (doc: XDocument) : SemVer option =
        let find tag =
            doc.Descendants(XName.Get tag)
            |> Seq.tryHead
            |> Option.map (fun el -> el.Value.Trim())
            |> Option.filter (fun s -> s.Length > 0)
        find "PackageVersion" |> Option.bind SemVer.parse
        |> Option.orElseWith (fun () -> find "Version" |> Option.bind SemVer.parse)
        |> Option.orElseWith (fun () ->
            find "VersionPrefix"
            |> Option.bind (fun prefix ->
                let full =
                    match find "VersionSuffix" with
                    | Some s when s.Length > 0 -> $"{prefix}-{s}"
                    | _                        -> prefix
                SemVer.parse full))

    let private scanProject (projPath: string) : Result<ScanResult, string> =
        try
            let doc  = XDocument.Load projPath
            let name = resolveName projPath doc
            let warnings = System.Collections.Generic.List<string>()

            let version = resolveVersion doc

            if version.IsNone then
                warnings.Add $"  ⚠  {name}: no <PackageVersion>, <Version>, or <VersionPrefix> tag — excluded from graph"

            let dir = Path.GetDirectoryName projPath
            let refs =
                doc.Descendants(XName.Get "ProjectReference")
                |> Seq.choose (fun el ->
                    match el.Attribute(XName.Get "Include") with
                    | null -> None
                    | a    ->
                        let rel = a.Value.Replace('\\', Path.DirectorySeparatorChar)
                        Some (Path.GetFullPath(Path.Combine(dir, rel))))
                |> Seq.toList

            let v = version |> Option.defaultValue { Major=0; Minor=0; Patch=0; PreRelease=None }
            Ok {
                Node       = { Name = name; Version = v; ProjectPath = projPath; Dependencies = refs }
                HasVersion = version.IsSome
                Warnings   = warnings |> Seq.toList
            }
        with ex ->
            Error $"Failed to parse '{projPath}': {ex.Message}"

    /// Scan all projects and build a DependencyGraph.
    /// Projects without a <PackageVersion>, <Version>, or <VersionPrefix> tag are excluded from the graph.
    let buildGraph (solutionPath: string) (projectPaths: string list) : Result<DependencyGraph * string list, string> =
        let results = projectPaths |> List.map (fun p -> scanProject p)

        let errors = results |> List.choose (function Error e -> Some e | _ -> None)
        if errors <> [] then Error (errors |> String.concat "\n")
        else
            let scanned  = results |> List.choose (function Ok s -> Some s | _ -> None)
            let warnings = scanned |> List.collect (fun s -> s.Warnings)
            let valid    = scanned |> List.filter (fun s -> s.HasVersion)
            let nodes    = valid |> List.map (fun s -> s.Node)

            let nameByPath = nodes |> List.map (fun n -> n.ProjectPath, n.Name) |> Map.ofList

            let remapped =
                nodes |> List.map (fun node ->
                    let internalDeps =
                        node.Dependencies
                        |> List.choose (fun path -> Map.tryFind path nameByPath)
                    { node with Dependencies = internalDeps })

            let packages = remapped |> List.map (fun n -> n.Name, n) |> Map.ofList
            let graph = {
                SolutionPath = solutionPath
                CreatedAt    = System.DateTime.UtcNow
                Packages     = packages
            }
            Ok (graph, warnings)
