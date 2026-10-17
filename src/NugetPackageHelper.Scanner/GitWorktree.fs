namespace NugetPackageHelper.Scanner

open System
open System.IO
open LibGit2Sharp

/// Reads a local branch tip with LibGit2Sharp. Does not start git and does not fetch.
module GitWorktree =

    type RepoChange = {
        OldPath: string
        NewPath: string
    }

    let private discover (startPath: string) =
        let found =
            if Directory.Exists startPath || File.Exists startPath then
                Repository.Discover startPath
            else
                null
        if String.IsNullOrEmpty found then
            Error $"No git repository found at '{startPath}'."
        else
            Ok found

    let private useRepo (startPath: string) (action: Repository -> Result<'a, string>) =
        match discover startPath with
        | Error message -> Error message
        | Ok gitDir ->
            try
                use repo = new Repository(gitDir)
                action repo
            with ex ->
                Error $"Failed to read the git repository: {ex.Message}"

    let private localBranch (repo: Repository) (name: string) =
        let branch =
            repo.Branches
            |> Seq.tryFind (fun candidate ->
                not candidate.IsRemote && candidate.FriendlyName = name && not (isNull candidate.Tip))
        match branch with
        | Some found -> Ok found
        | None -> Error $"Local branch '{name}' was not found."

    let private textOrEmpty (value: string) =
        if isNull value then "" else value

    let private oldPathExists (tree: Tree) (oldPath: string) =
        not (String.IsNullOrEmpty oldPath) && not (isNull tree.[oldPath])

    let private keep (tree: Tree) (change: TreeEntryChanges) =
        let trackedKind =
            match change.Status with
            | ChangeKind.Modified
            | ChangeKind.Deleted
            | ChangeKind.Renamed
            | ChangeKind.Copied
            | ChangeKind.TypeChanged -> true
            | _ -> false
        trackedKind && oldPathExists tree (textOrEmpty change.OldPath)

    /// Working directory of the repository that contains the start path.
    let workingDirectory (startPath: string) : Result<string, string> =
        useRepo startPath (fun repo ->
            let raw = repo.Info.WorkingDirectory
            if String.IsNullOrEmpty raw then
                Error $"No git repository found at '{startPath}'."
            else
                Ok (raw.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)))

    /// Diff the named local branch tip against the index and the working directory.
    /// Untracked files and added-only paths are omitted.
    let changedPaths (startPath: string) (branchName: string) : Result<RepoChange list, string> =
        useRepo startPath (fun repo ->
            match localBranch repo branchName with
            | Error message -> Error message
            | Ok branch ->
                let tree = branch.Tip.Tree
                let targets = DiffTargets.Index ||| DiffTargets.WorkingDirectory
                let diff = repo.Diff.Compare<TreeChanges>(tree, targets)
                let changes =
                    diff
                    |> Seq.filter (keep tree)
                    |> Seq.map (fun change ->
                        { OldPath = textOrEmpty change.OldPath
                          NewPath = textOrEmpty change.Path })
                    |> Seq.distinct
                    |> Seq.toList
                Ok changes)

    /// Project file text at the branch tip, relative to the repository root. None when the path is absent.
    let readTipText (startPath: string) (branchName: string) (relativePath: string) : Result<string option, string> =
        useRepo startPath (fun repo ->
            match localBranch repo branchName with
            | Error message -> Error message
            | Ok branch ->
                let path = relativePath.Replace('\\', '/')
                let entry = branch.Tip.Tree.[path]
                if isNull entry then
                    Ok None
                else
                    match entry.Target with
                    | :? Blob as blob -> Ok (Some (blob.GetContentText()))
                    | _ -> Ok None)
