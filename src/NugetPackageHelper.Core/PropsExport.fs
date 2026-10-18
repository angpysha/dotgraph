namespace NugetPackageHelper.Core

open System
open System.IO
open System.Text
open System.Text.RegularExpressions
open System.Xml.Linq

module PropsExport =

    let private dotgraphLabel = "Dotgraph"
    let private settingsFileName = ".dotgraph.json"

    let private dotgraphGroupRegex =
        Regex(
            """<ItemGroup\s+Label\s*=\s*"Dotgraph"[^>]*>.*?</ItemGroup>""",
            RegexOptions.Singleline)

    type ExportOutcome =
        | Wrote of packageCount: int
        | AlreadyMatches
        | NoPackages

    type ExportResult = {
        Outcome: ExportOutcome
        Warnings: string list
    }

    let resolveStoredPath (baseDir: string) (stored: string) =
        if Path.IsPathRooted stored then Path.GetFullPath stored
        else Path.GetFullPath(Path.Combine(baseDir, stored))

    let validateExportPath (baseDir: string) (stored: string) : Result<string, string> =
        let trimmed = stored.Trim()
        let full = resolveStoredPath baseDir trimmed
        let settingsPath = Path.GetFullPath(Path.Combine(baseDir, settingsFileName))
        if String.Equals(full, settingsPath, StringComparison.OrdinalIgnoreCase) then
            Error "The props path cannot be the dotgraph settings file."
        elif File.Exists full && (File.GetAttributes full).HasFlag FileAttributes.Directory then
            Error $"The path is a directory: {trimmed}"
        else
            let parent = Path.GetDirectoryName full
            if String.IsNullOrEmpty parent then Error "Invalid props path."
            elif not (Directory.Exists parent) then
                Error $"Parent folder does not exist: {parent}"
            else Ok full

    let private escapeAttr (value: string) =
        System.Security.SecurityElement.Escape value

    let private orderedPackages (packages: Map<string, PackageNode>) =
        packages
        |> Map.toList
        |> List.sortBy (fun (name, _) -> name.ToLowerInvariant(), name)

    let buildDotgraphGroup (packages: Map<string, PackageNode>) =
        let sb = StringBuilder()
        sb.AppendLine("  <ItemGroup Label=\"Dotgraph\">") |> ignore
        for name, node in orderedPackages packages do
            let version = SemVer.toString node.Version
            sb.AppendLine(
                $"    <PackageVersion Include=\"{escapeAttr name}\" Version=\"{escapeAttr version}\" />")
            |> ignore
        sb.Append("  </ItemGroup>") |> ignore
        sb.ToString()

    let private normalizeText (text: string) =
        text.Replace("\r\n", "\n", StringComparison.Ordinal)

    let private newFileContent (groupText: string) =
        $"<Project>{Environment.NewLine}{groupText}{Environment.NewLine}</Project>{Environment.NewLine}"

    let private parseProject (text: string) : Result<XDocument, string> =
        try
            let doc = XDocument.Parse text
            match doc.Root with
            | null -> Error "The props file has no root element."
            | root when root.Name.LocalName <> "Project" ->
                Error "The props file root must be Project."
            | _ -> Ok doc
        with ex ->
            Error $"The props file is not valid XML: {ex.Message}"

    let private findDotgraphGroups (doc: XDocument) =
        doc.Descendants(XName.Get("ItemGroup"))
        |> Seq.filter (fun el ->
            match el.Attribute(XName.Get("Label")) with
            | null -> false
            | attr -> attr.Value = dotgraphLabel)
        |> Seq.toList

    let private packageVersionStrings (packages: Map<string, PackageNode>) =
        packages
        |> Map.map (fun _ node -> SemVer.toString node.Version)
        |> Map.toList
        |> List.sortBy (fun (name, _) -> name.ToLowerInvariant(), name)
        |> Map.ofList

    let private readManagedVersions (text: string) =
        match parseProject text with
        | Error message -> Error message
        | Ok doc ->
            let groups = findDotgraphGroups doc
            match groups with
            | [group] ->
                let versions =
                    group.Elements(XName.Get("PackageVersion"))
                    |> Seq.choose (fun el ->
                        match el.Attribute(XName.Get("Include")), el.Attribute(XName.Get("Version")) with
                        | null, _ | _, null -> None
                        | includeAttr, versionAttr -> Some (includeAttr.Value, versionAttr.Value))
                    |> Seq.toList
                    |> List.sortBy (fun (name, _) -> name.ToLowerInvariant(), name)
                    |> Map.ofList
                Ok versions
            | [] -> Error "The props file has no Dotgraph item group."
            | _ -> Error "The props file has more than one Dotgraph item group."

    let alreadyMatchesSnapshot (packages: Map<string, PackageNode>) (text: string) =
        match readManagedVersions text with
        | Error _ -> false
        | Ok actual ->
            dotgraphGroupRegex.Matches(text).Count = 1
            && actual = packageVersionStrings packages

    let findExternalDuplicateNames (text: string) (packageNames: Set<string>) =
        match parseProject text with
        | Error _ -> []
        | Ok doc ->
            doc.Descendants(XName.Get("PackageVersion"))
            |> Seq.choose (fun el ->
                let parent = el.Parent
                if isNull parent || parent.Name.LocalName <> "ItemGroup" then None
                else
                    match parent.Attribute(XName.Get("Label")) with
                    | label when not (isNull label) && label.Value = dotgraphLabel -> None
                    | _ ->
                        match el.Attribute(XName.Get("Include")) with
                        | null -> None
                        | attr when packageNames.Contains attr.Value -> Some attr.Value
                        | _ -> None)
            |> Seq.distinct
            |> Seq.toList

    type ContentApplyResult =
        | Changed of text: string
        | Unchanged

    let applyContent (packages: Map<string, PackageNode>) (existingText: string option) =
        let groupText = buildDotgraphGroup packages
        match existingText with
        | None -> Ok (Changed (newFileContent groupText))
        | Some text ->
            match parseProject text with
            | Error message -> Error message
            | Ok _ ->
                let groupCount = dotgraphGroupRegex.Matches(text).Count
                match groupCount with
                | 0 ->
                    let closing =
                        text.LastIndexOf("</Project>", StringComparison.OrdinalIgnoreCase)
                    if closing < 0 then
                        Error "The props file has no Project end tag."
                    else
                        let insert = $"{Environment.NewLine}{groupText}{Environment.NewLine}"
                        let merged = text.Insert(closing, insert)
                        if merged = text then Ok Unchanged else Ok (Changed merged)
                | 1 ->
                    let match' = dotgraphGroupRegex.Match text
                    if not match'.Success then
                        Error "The Dotgraph item group could not be located in the props file."
                    elif normalizeText match'.Value = normalizeText groupText then
                        Ok Unchanged
                    else
                        let merged =
                            text.Substring(0, match'.Index)
                            + groupText
                            + text.Substring(match'.Index + match'.Length)
                        if normalizeText merged = normalizeText text then Ok Unchanged else Ok (Changed merged)
                | _ ->
                    Error "The props file has more than one Dotgraph item group."

    let private writeAtomic (fullPath: string) (content: string) =
        try
            let parent = Path.GetDirectoryName fullPath
            let temp = Path.Combine(parent, $".{Path.GetFileName fullPath}.{Guid.NewGuid():N}.tmp")
            File.WriteAllText(temp, content, Encoding.UTF8)
            if File.Exists fullPath then File.Replace(temp, fullPath, null) |> ignore
            else File.Move(temp, fullPath)
            Ok ()
        with ex ->
            Error $"Failed to write props file: {ex.Message}"

    let export (graph: DependencyGraph) (baseDir: string) : Result<ExportResult, string> =
        match graph.PropsPath with
        | None -> Error "No props path is saved."
        | Some stored ->
            match validateExportPath baseDir stored with
            | Error message -> Error message
            | Ok fullPath ->
                let names = graph.Packages |> Map.keys |> Set.ofSeq
                let existing =
                    if File.Exists fullPath then Some (File.ReadAllText fullPath)
                    else None
                let warnings =
                    match existing with
                    | None -> []
                    | Some text -> findExternalDuplicateNames text names
                match existing with
                | Some text when alreadyMatchesSnapshot graph.Packages text ->
                    Ok {
                        Outcome =
                            if graph.Packages.IsEmpty then NoPackages
                            else AlreadyMatches
                        Warnings = warnings
                    }
                | _ ->
                    match applyContent graph.Packages existing with
                    | Error message -> Error message
                    | Ok Unchanged ->
                        Ok {
                            Outcome =
                                if graph.Packages.IsEmpty then NoPackages
                                else AlreadyMatches
                            Warnings = warnings
                        }
                    | Ok (Changed content) ->
                        match existing with
                        | Some text when normalizeText text = normalizeText content ->
                            Ok {
                                Outcome =
                                    if graph.Packages.IsEmpty then NoPackages
                                    else AlreadyMatches
                                Warnings = warnings
                            }
                        | _ ->
                            match writeAtomic fullPath content with
                            | Error message -> Error message
                            | Ok () ->
                                Ok {
                                    Outcome =
                                        if graph.Packages.IsEmpty then NoPackages
                                        else Wrote graph.Packages.Count
                                    Warnings = warnings
                                }
