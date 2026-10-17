namespace NugetPackageHelper.Core

open System
open System.IO
open System.Xml.Linq

/// Which packages a branch diff selects, and the patch taken from that branch.
/// Git facts stay in the scanner. This module only sees paths, XML, and versions.
module BranchProposal =

    /// A path the scanner kept. Added and untracked paths are not included.
    type ChangedPath = {
        OldPath: string
        NewPath: string
    }

    /// Project XML for one live package. BranchXml is absent when the file is not on the compare branch.
    type PackageXml = {
        LiveXml: string
        BranchXml: string option
    }

    type BranchWarning = {
        Name: string
        Detail: string
    }

    type SelectedPackage = {
        Name: string
        BranchVersion: SemVer option
        LiveVersion: SemVer
        ProposedVersion: SemVer
        BumpType: BumpType
        Reason: string
        AlreadyCurrent: bool
    }

    type BranchReport = {
        Selected: SelectedPackage list
        FollowUps: VersionProposal list
        Warnings: BranchWarning list
    }

    let private versionTagNames = [
        "PackageVersion"
        "Version"
        "VersionPrefix"
        "VersionSuffix"
        "PackagePrefix"
        "PackageSuffix"
    ]

    let private tryParseXml (xml: string) =
        try Some (XDocument.Parse xml)
        with _ -> None

    let private elementText (doc: XDocument) (tag: string) =
        doc.Descendants(XName.Get tag)
        |> Seq.tryHead
        |> Option.map (fun el -> el.Value.Trim())
        |> Option.filter (fun text -> text.Length > 0)

    /// Same tag order as ProjectScanner.resolveVersion.
    let private versionFromDoc (doc: XDocument) =
        let fromPrefix prefixTag suffixTag =
            elementText doc prefixTag
            |> Option.bind (fun prefix ->
                let full =
                    match elementText doc suffixTag with
                    | Some suffix -> $"{prefix}-{suffix}"
                    | None -> prefix
                SemVer.parse full)

        elementText doc "PackageVersion"
        |> Option.bind SemVer.parse
        |> Option.orElseWith (fun () -> elementText doc "Version" |> Option.bind SemVer.parse)
        |> Option.orElseWith (fun () -> fromPrefix "VersionPrefix" "VersionSuffix")
        |> Option.orElseWith (fun () -> fromPrefix "PackagePrefix" "PackageSuffix")

    let private withoutVersionTags (doc: XDocument) =
        let copy = XDocument(doc)
        copy.Descendants()
        |> Seq.filter (fun el -> List.contains el.Name.LocalName versionTagNames)
        |> Seq.toList
        |> List.iter (fun el -> el.Remove())
        copy

    let private versionTagsOnly (liveXml: string) (branchXml: string) =
        match tryParseXml liveXml, tryParseXml branchXml with
        | Some liveDoc, Some branchDoc ->
            XNode.DeepEquals(withoutVersionTags liveDoc, withoutVersionTags branchDoc)
        | _ -> false

    let private normalize (path: string) =
        if String.IsNullOrEmpty path then ""
        else path.Replace('\\', '/').TrimEnd('/')

    /// Longer project directories win. The project file itself belongs to that package.
    let private prefixLength (projectPath: string) (filePath: string) =
        let file = normalize filePath
        if file.Length = 0 then None
        else
            let project = normalize projectPath
            let dir = normalize (Path.GetDirectoryName projectPath)
            if file = project || file.StartsWith(dir + "/", StringComparison.Ordinal) then
                Some dir.Length
            else
                None

    let private owner (packages: PackageNode list) (filePath: string) =
        packages
        |> List.choose (fun package ->
            prefixLength package.ProjectPath filePath
            |> Option.map (fun length -> package, length))
        |> List.sortByDescending snd
        |> List.tryHead
        |> Option.map fst

    let private pathsOf (change: ChangedPath) =
        [ change.OldPath; change.NewPath ]
        |> List.filter (fun path -> not (String.IsNullOrEmpty path))

    let private filesFor (packages: PackageNode list) (package: PackageNode) (changes: ChangedPath list) =
        changes
        |> List.collect pathsOf
        |> List.filter (fun path ->
            match owner packages path with
            | Some found -> found.Name = package.Name
            | None -> false)

    let private isProjectFile (projectPath: string) (filePath: string) =
        normalize projectPath = normalize filePath

    let private oneZero =
        { Major = 1; Minor = 0; Patch = 0; PreRelease = None }

    let private zero =
        { Major = 0; Minor = 0; Patch = 0; PreRelease = None }

    type private Candidate = {
        Node: PackageNode
        BranchVersion: SemVer option
        Reason: string
    }

    /// A review answer. Leave unchanged is the default. Entered versions are already validated.
    type ReviewChoice =
        | LeaveUnchanged
        | AcceptProposed
        | Entered of SemVer

    let private inDependencyOrder (candidates: Candidate list) =
        let names = candidates |> List.map (fun c -> c.Node.Name) |> Set.ofList
        let rec take (remaining: Candidate list) (placed: Set<string>) =
            if remaining.IsEmpty then []
            else
                let ready, rest =
                    remaining
                    |> List.partition (fun candidate ->
                        candidate.Node.Dependencies
                        |> List.filter (fun dep -> Set.contains dep names)
                        |> List.forall (fun dep -> Set.contains dep placed))
                match ready with
                | [] ->
                    let head = List.head rest
                    head :: take (List.tail rest) (Set.add head.Node.Name placed)
                | _ ->
                    let ordered = ready |> List.sortBy (fun candidate -> candidate.Node.Name)
                    let placedNow =
                        ordered |> List.fold (fun acc candidate -> Set.add candidate.Node.Name acc) placed
                    List.append ordered (take rest placedNow)
        take candidates Set.empty

    /// Higher of the branch patch and the follow-up size applied to that same branch version.
    let private offerFor (candidate: Candidate) (rootBumps: Map<string, BumpType>) =
        let branchBase = candidate.BranchVersion |> Option.defaultValue oneZero
        let own = SemVer.applyBump Patch branchBase
        let triggers =
            candidate.Node.Dependencies
            |> List.choose (fun dep -> Map.tryFind dep rootBumps)
        match triggers with
        | [] -> own
        | first :: rest ->
            let maxTrigger = rest |> List.fold SemVer.maxBump first
            let follow = SemVer.applyBump (SemVer.cascadeBump maxTrigger) branchBase
            if SemVer.compare follow own > 0 then follow else own

    let private triggerBump (candidate: Candidate) (offer: SemVer) =
        match candidate.BranchVersion with
        | Some branch -> SemVer.detectBump branch offer
        | None ->
            if SemVer.compare candidate.Node.Version offer = 0 then Major
            elif SemVer.isDowngrade candidate.Node.Version offer then Major
            else SemVer.detectBump candidate.Node.Version offer

    let private rootPair (candidate: Candidate) (offer: SemVer) =
        match candidate.BranchVersion with
        | Some branch -> candidate.Node.Name, branch, offer
        | None -> candidate.Node.Name, zero, offer

    let private displayBump (candidate: Candidate) (offer: SemVer) =
        match candidate.BranchVersion with
        | Some branch -> SemVer.detectBump branch offer
        | None ->
            if SemVer.compare candidate.Node.Version offer >= 0 then Major
            else SemVer.detectBump candidate.Node.Version offer

    /// Initial report. Every selected package counts as a cascade root, including one already at the patch.
    let propose
        (graph: DependencyGraph)
        (xmlByName: Map<string, PackageXml>)
        (snapshotNames: string list)
        (changedPaths: ChangedPath list)
        : BranchReport =

        let packages = graph.Packages |> Map.toList |> List.map snd
        let branchName =
            if String.IsNullOrWhiteSpace graph.CompareBranch then "main"
            else graph.CompareBranch.Trim()

        let warnings = ResizeArray<BranchWarning>()
        let candidates = ResizeArray<Candidate>()

        for package in packages |> List.sortBy (fun node -> node.Name) do
            let touched = filesFor packages package changedPaths
            match Map.tryFind package.Name xmlByName with
            | None -> ()
            | Some source ->
                match source.BranchXml with
                | None ->
                    candidates.Add {
                        Node = package
                        BranchVersion = None
                        Reason = "new package"
                    }
                | Some branchXml ->
                    match tryParseXml branchXml |> Option.bind versionFromDoc with
                    | None ->
                        if not touched.IsEmpty then
                            warnings.Add {
                                Name = package.Name
                                Detail = $"no numeric version on {branchName}"
                            }
                    | Some branchVersion ->
                        let projectOnly =
                            not touched.IsEmpty
                            && touched |> List.forall (isProjectFile package.ProjectPath)
                        let tagOnly = projectOnly && versionTagsOnly source.LiveXml branchXml
                        if not touched.IsEmpty && not tagOnly then
                            candidates.Add {
                                Node = package
                                BranchVersion = Some branchVersion
                                Reason = "code changed"
                            }

        let mutable rootBumps = Map.empty
        let selected = ResizeArray<SelectedPackage>()
        let roots = ResizeArray<string * SemVer * SemVer>()

        for candidate in inDependencyOrder (candidates |> Seq.toList) do
            let proposed =
                match candidate.BranchVersion with
                | None -> oneZero
                | Some _ -> offerFor candidate rootBumps
            let bump = triggerBump candidate proposed
            rootBumps <- Map.add candidate.Node.Name bump rootBumps
            roots.Add(rootPair candidate proposed)
            selected.Add {
                Name = candidate.Node.Name
                BranchVersion = candidate.BranchVersion
                LiveVersion = candidate.Node.Version
                ProposedVersion = proposed
                BumpType = displayBump candidate proposed
                Reason = candidate.Reason
                AlreadyCurrent = SemVer.compare candidate.Node.Version proposed = 0
            }

        let selectedNames = selected |> Seq.map (fun item -> item.Name) |> Set.ofSeq
        let followUps =
            CascadeEngine.computeProposals graph (roots |> Seq.toList)
            |> List.filter (fun proposal -> not (Set.contains proposal.PackageName selectedNames))

        let removed =
            snapshotNames
            |> List.filter (fun name -> not (graph.Packages.ContainsKey name))
            |> List.distinct
            |> List.sort
            |> List.map (fun name -> { Name = name; Detail = "removed" })

        {
            Selected = selected |> Seq.toList
            FollowUps = followUps
            Warnings = List.append removed (warnings |> Seq.toList)
        }

    /// Drop a leave-unchanged package from the cascade when its live version is still the branch version.
    /// A package already at the proposed patch stays a root. Typed rebuilds are applied later.
    let applyDecisions
        (graph: DependencyGraph)
        (xmlByName: Map<string, PackageXml>)
        (snapshotNames: string list)
        (changedPaths: ChangedPath list)
        (decisions: Map<string, ReviewChoice>)
        : BranchReport =

        let preview = propose graph xmlByName snapshotNames changedPaths
        let selectedNames = preview.Selected |> List.map (fun item -> item.Name) |> Set.ofList
        let roots =
            preview.Selected
            |> List.choose (fun item ->
                let leftAtBranch =
                    match Map.tryFind item.Name decisions with
                    | Some LeaveUnchanged -> SemVer.compare item.LiveVersion item.ProposedVersion <> 0
                    | Some (Entered version) ->
                        SemVer.compare version item.LiveVersion = 0
                        && SemVer.compare item.LiveVersion item.ProposedVersion <> 0
                    | _ -> false
                if leftAtBranch then None
                else
                    let oldVersion = item.BranchVersion |> Option.defaultValue zero
                    Some (item.Name, oldVersion, item.ProposedVersion))
        let followUps =
            CascadeEngine.computeProposals graph roots
            |> List.filter (fun proposal -> not (Set.contains proposal.PackageName selectedNames))
        { preview with FollowUps = followUps }

    type ReviewRow = {
        Name: string
        IsSelected: bool
        BranchVersion: SemVer option
        LiveVersion: SemVer
        ProposedVersion: SemVer
        BumpType: BumpType
        Reason: string
        AlreadyCurrent: bool
    }

    let private collectCandidates
        (graph: DependencyGraph)
        (xmlByName: Map<string, PackageXml>)
        (changedPaths: ChangedPath list) =

        let packages = graph.Packages |> Map.toList |> List.map snd
        let branchName =
            if String.IsNullOrWhiteSpace graph.CompareBranch then "main"
            else graph.CompareBranch.Trim()
        let warnings = ResizeArray<BranchWarning>()
        let candidates = ResizeArray<Candidate>()
        for package in packages |> List.sortBy (fun node -> node.Name) do
            let touched = filesFor packages package changedPaths
            match Map.tryFind package.Name xmlByName with
            | None -> ()
            | Some source ->
                match source.BranchXml with
                | None ->
                    candidates.Add { Node = package; BranchVersion = None; Reason = "new package" }
                | Some branchXml ->
                    match tryParseXml branchXml |> Option.bind versionFromDoc with
                    | None ->
                        if not touched.IsEmpty then
                            warnings.Add { Name = package.Name; Detail = $"no numeric version on {branchName}" }
                    | Some branchVersion ->
                        let projectOnly =
                            not touched.IsEmpty
                            && touched |> List.forall (isProjectFile package.ProjectPath)
                        let tagOnly = projectOnly && versionTagsOnly source.LiveXml branchXml
                        if not touched.IsEmpty && not tagOnly then
                            candidates.Add {
                                Node = package
                                BranchVersion = Some branchVersion
                                Reason = "code changed"
                            }
        candidates |> Seq.toList, warnings |> Seq.toList

    /// Rows in review order. Decisions already made rebuild every later row. Each package appears once.
    let reviewRows
        (graph: DependencyGraph)
        (xmlByName: Map<string, PackageXml>)
        (_snapshotNames: string list)
        (changedPaths: ChangedPath list)
        (decisions: Map<string, ReviewChoice>)
        : ReviewRow list =

        let candidates, _warnings = collectCandidates graph xmlByName changedPaths
        let mutable rootBumps = Map.empty
        let roots = ResizeArray<string * SemVer * SemVer>()
        let selectedRows = ResizeArray<ReviewRow>()

        for candidate in inDependencyOrder candidates do
            let offer =
                match candidate.BranchVersion with
                | None -> oneZero
                | Some _ -> offerFor candidate rootBumps
            let decision = Map.tryFind candidate.Node.Name decisions
            let chosen, isRoot =
                match decision with
                | Some LeaveUnchanged ->
                    let already = SemVer.compare candidate.Node.Version offer = 0
                    (if already then offer else candidate.Node.Version), already
                | Some AcceptProposed ->
                    offer, true
                | Some (Entered version) when SemVer.compare version candidate.Node.Version = 0 ->
                    offer, SemVer.compare candidate.Node.Version offer = 0
                | Some (Entered version) ->
                    version, true
                | None ->
                    offer, true
            if isRoot then
                let oldVersion = candidate.BranchVersion |> Option.defaultValue zero
                // Equal versions are not a bump. detectBump would otherwise report a patch.
                if SemVer.compare oldVersion chosen <> 0 then
                    let bump =
                        match candidate.BranchVersion with
                        | Some branch -> SemVer.detectBump branch chosen
                        | None -> triggerBump candidate chosen
                    rootBumps <- Map.add candidate.Node.Name bump rootBumps
                    roots.Add(candidate.Node.Name, oldVersion, chosen)
            selectedRows.Add {
                Name = candidate.Node.Name
                IsSelected = true
                BranchVersion = candidate.BranchVersion
                LiveVersion = candidate.Node.Version
                ProposedVersion = chosen
                BumpType =
                    match candidate.BranchVersion with
                    | Some branch -> SemVer.detectBump branch chosen
                    | None -> displayBump candidate chosen
                Reason = candidate.Reason
                AlreadyCurrent = SemVer.compare candidate.Node.Version chosen = 0
            }

        let selectedNames = selectedRows |> Seq.map (fun row -> row.Name) |> Set.ofSeq
        let followRows =
            CascadeEngine.computeProposals graph (roots |> Seq.toList)
            |> List.filter (fun proposal ->
                not (Set.contains proposal.PackageName selectedNames)
                && SemVer.compare proposal.CurrentVersion proposal.ProposedVersion <> 0)
            |> List.map (fun proposal ->
                let chosen =
                    match Map.tryFind proposal.PackageName decisions with
                    | Some LeaveUnchanged -> proposal.CurrentVersion
                    | Some AcceptProposed -> proposal.ProposedVersion
                    | Some (Entered version) when SemVer.compare version proposal.CurrentVersion = 0 ->
                        proposal.CurrentVersion
                    | Some (Entered version) -> version
                    | None -> proposal.ProposedVersion
                {
                    Name = proposal.PackageName
                    IsSelected = false
                    BranchVersion = None
                    LiveVersion = proposal.CurrentVersion
                    ProposedVersion = chosen
                    BumpType = proposal.BumpType
                    Reason = proposal.Reason
                    AlreadyCurrent = SemVer.compare proposal.CurrentVersion chosen = 0
                })
        List.append (selectedRows |> Seq.toList) followRows
