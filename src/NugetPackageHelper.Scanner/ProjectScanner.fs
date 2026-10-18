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

    let private findElement (doc: XDocument) tag =
        doc.Descendants(XName.Get tag) |> Seq.tryHead

    let private hasNonEmptyValue (el: XElement) =
        el.Value.Trim().Length > 0

    /// Combine a prefix tag with an optional suffix tag. An empty suffix is treated as absent.
    let private combinePrefixAndSuffix (prefix: string) (suffix: string option) =
        let full =
            match suffix with
            | Some s when s.Length > 0 -> $"{prefix}-{s}"
            | _                        -> prefix
        SemVer.parse full

    let private resolveVersion (doc: XDocument) : SemVer option =
        let find tag =
            findElement doc tag
            |> Option.map (fun el -> el.Value.Trim())
            |> Option.filter (fun s -> s.Length > 0)
        let fromPrefix prefixTag suffixTag =
            find prefixTag
            |> Option.bind (fun prefix -> combinePrefixAndSuffix prefix (find suffixTag))
        // First tag that parses as a numeric version wins. Later tags are left unread.
        find "PackageVersion" |> Option.bind SemVer.parse
        |> Option.orElseWith (fun () -> find "Version" |> Option.bind SemVer.parse)
        |> Option.orElseWith (fun () -> fromPrefix "VersionPrefix" "VersionSuffix")
        |> Option.orElseWith (fun () -> fromPrefix "PackagePrefix" "PackageSuffix")

    /// Parse a version from project XML text using the same tag order as a live project file.
    let versionFromXml (xml: string) : SemVer option =
        try
            resolveVersion (XDocument.Parse xml)
        with _ ->
            None

    type private VersionWriteTarget =
        | SingleTag of XElement
        | PrefixSuffixTags of prefixEl: XElement * suffixEl: XElement option * suffixTag: string

    let private resolvePrefixSuffixTarget (doc: XDocument) prefixTag suffixTag =
        findElement doc prefixTag
        |> Option.filter hasNonEmptyValue
        |> Option.map (fun prefixEl ->
            PrefixSuffixTags (prefixEl, findElement doc suffixTag, suffixTag))

    let private resolveVersionWriteTarget (doc: XDocument) : VersionWriteTarget option =
        findElement doc "PackageVersion"
        |> Option.filter hasNonEmptyValue
        |> Option.map SingleTag
        |> Option.orElseWith (fun () ->
            findElement doc "Version"
            |> Option.filter hasNonEmptyValue
            |> Option.map SingleTag)
        |> Option.orElseWith (fun () -> resolvePrefixSuffixTarget doc "VersionPrefix" "VersionSuffix")
        |> Option.orElseWith (fun () -> resolvePrefixSuffixTarget doc "PackagePrefix" "PackageSuffix")

    /// Write a version back to the winning tag only
    /// (PackageVersion, Version, VersionPrefix/VersionSuffix, or PackagePrefix/PackageSuffix).
    /// A missing suffix element is created beside the winning prefix tag when the new version has a suffix.
    let writeVersion (projectPath: string) (version: SemVer) : Result<unit, string> =
        let writePrefixSuffix (prefixEl: XElement) (suffixEl: XElement option) (suffixTag: string) =
            prefixEl.Value <- $"{version.Major}.{version.Minor}.{version.Patch}"
            match version.PreRelease with
            | None ->
                suffixEl |> Option.iter (fun el -> el.Value <- "")
            | Some pre ->
                match suffixEl with
                | Some el -> el.Value <- pre
                | None ->
                    let suffix = XElement(XName.Get suffixTag, pre)
                    prefixEl.AddAfterSelf suffix

        try
            let doc = XDocument.Load projectPath
            match resolveVersionWriteTarget doc with
            | None ->
                Error $"No <PackageVersion>, <Version>, <VersionPrefix>, or <PackagePrefix> element in {projectPath}"
            | Some (PrefixSuffixTags (prefixEl, suffixEl, suffixTag)) ->
                writePrefixSuffix prefixEl suffixEl suffixTag
                doc.Save projectPath
                Ok ()
            | Some (SingleTag el) ->
                el.Value <- SemVer.toString version
                doc.Save projectPath
                Ok ()
        with ex ->
            Error $"Failed to write {projectPath}: {ex.Message}"

    let private scanProject (projPath: string) : Result<ScanResult, string> =
        try
            let doc  = XDocument.Load projPath
            let name = resolveName projPath doc
            let warnings = System.Collections.Generic.List<string>()

            let version = resolveVersion doc

            if version.IsNone then
                warnings.Add $"  ⚠  {name}: no <PackageVersion>, <Version>, <VersionPrefix>, or <PackagePrefix> tag — excluded from graph"

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
    /// Projects without a <PackageVersion>, <Version>, <VersionPrefix>, or <PackagePrefix> tag are excluded from the graph.
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
                SolutionPath  = solutionPath
                CreatedAt     = System.DateTime.UtcNow
                CompareBranch = "main"
                PropsPath     = None
                Packages      = packages
            }
            Ok (graph, warnings)
