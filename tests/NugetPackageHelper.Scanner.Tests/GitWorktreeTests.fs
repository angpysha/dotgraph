module NugetPackageHelper.Scanner.Tests.GitWorktreeTests

open System.IO
open LibGit2Sharp
open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core
open NugetPackageHelper.Scanner

let private withRepo (body: string -> unit) =
    let dir = Path.Combine(Path.GetTempPath(), "dotgraph-" + Path.GetRandomFileName())
    Directory.CreateDirectory dir |> ignore
    try
        body dir
    finally
        Directory.Delete(dir, recursive = true)

/// Create a repository whose main commit contains a project file. LibGit2Sharp only; no git process.
let private commitMain (dir: string) =
    Repository.Init(dir) |> ignore
    use repo = new Repository(dir)
    let projDir = Path.Combine(dir, "src", "Core")
    Directory.CreateDirectory projDir |> ignore
    let proj = Path.Combine(projDir, "Core.csproj")
    File.WriteAllText(proj, "<Project><PropertyGroup><Version>1.2.3</Version></PropertyGroup></Project>")
    File.WriteAllText(Path.Combine(projDir, "Tracked.cs"), "class Tracked {}")
    Commands.Stage(repo, "*")
    let author = Signature("dev", "dev@example.com", System.DateTimeOffset.UtcNow)
    repo.Commit("init", author, author) |> ignore
    if repo.Head.FriendlyName <> "main" then
        let main = repo.CreateBranch("main", repo.Head.Tip)
        Commands.Checkout(repo, main) |> ignore
    proj

let private fileNames (changes: GitWorktree.RepoChange list) =
    changes
    |> List.collect (fun change -> [ change.OldPath; change.NewPath ])
    |> List.filter (fun path -> not (System.String.IsNullOrEmpty path))
    |> List.map (fun path -> Path.GetFileName(path.Replace('/', Path.DirectorySeparatorChar)))

[<Fact>]
let ``dirty tracked file is returned and untracked or added-only paths are not`` () =
    withRepo (fun dir ->
        let proj = commitMain dir
        let tracked = Path.Combine(Path.GetDirectoryName proj, "Tracked.cs")
        File.WriteAllText(tracked, "class Tracked { void Changed() {} }")
        File.WriteAllText(Path.Combine(Path.GetDirectoryName proj, "Untracked.cs"), "class Untracked {}")
        let added = Path.Combine(Path.GetDirectoryName proj, "Added.cs")
        File.WriteAllText(added, "class Added {}")
        use repo = new Repository(dir)
        // Stage a repo-relative path. An absolute path can miss the working directory when /var is a symlink.
        Commands.Stage(repo, "src/Core/Added.cs")

        match GitWorktree.changedPaths dir "main" with
        | Error e -> failwith e
        | Ok changes ->
            let names = fileNames changes
            names |> should contain "Tracked.cs"
            names |> should not' (contain "Untracked.cs")
            names |> should not' (contain "Added.cs"))

[<Fact>]
let ``blob text at main parses through versionFromXml`` () =
    withRepo (fun dir ->
        commitMain dir |> ignore
        match GitWorktree.readTipText dir "main" "src/Core/Core.csproj" with
        | Error e -> failwith e
        | Ok None -> failwith "Expected project blob on main"
        | Ok (Some text) ->
            ProjectScanner.versionFromXml text
            |> should equal (Some { Major = 1; Minor = 2; Patch = 3; PreRelease = None }))

[<Fact>]
let ``missing local branch is an error and does not fetch`` () =
    withRepo (fun dir ->
        commitMain dir |> ignore
        match GitWorktree.changedPaths dir "does-not-exist" with
        | Ok _ -> failwith "Expected a missing-branch error"
        | Error message ->
            message |> should haveSubstring "does-not-exist"
        use repo = new Repository(dir)
        repo.Network.Remotes |> Seq.isEmpty |> should equal true)
