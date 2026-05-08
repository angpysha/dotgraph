module NugetPackageHelper.Cli.Program

open System.CommandLine
open NugetPackageHelper.Cli.Commands

[<EntryPoint>]
let main argv =
    let solutionOpt = Option<string>("--solution")
    solutionOpt.Description <- "Path to solution file when multiple exist"

    // ── init ───────────────────────────────────────────────────────────────
    let initCmd = Command("init", "Scan solution and build initial dependency graph")
    initCmd.Add solutionOpt
    initCmd.SetAction(fun result ->
        let sln = result.GetValue solutionOpt |> Option.ofObj
        Init.run sln |> ignore)

    // ── refresh ────────────────────────────────────────────────────────────
    let refreshCmd = Command("refresh", "Rescan solution and update the graph snapshot")
    refreshCmd.Add solutionOpt
    refreshCmd.SetAction(fun result ->
        let sln = result.GetValue solutionOpt |> Option.ofObj
        Refresh.run sln |> ignore)

    // ── analyze ────────────────────────────────────────────────────────────
    let analyzeArg = Argument<string[]>("packages")
    analyzeArg.Description <- "Package name(s) to analyze"
    analyzeArg.Arity <- ArgumentArity.OneOrMore
    let analyzeCmd = Command("analyze", "Show packages affected by a version change (dry run)")
    analyzeCmd.Add analyzeArg
    analyzeCmd.SetAction(fun result ->
        let pkgs = result.GetValue analyzeArg |> Array.toList
        Analyze.run pkgs |> ignore)

    // ── diff ───────────────────────────────────────────────────────────────
    let diffCmd = Command("diff", "Compare live .csproj versions to snapshot")
    diffCmd.SetAction(fun _ ->
        Diff.run () |> ignore)

    // ── sync ───────────────────────────────────────────────────────────────
    let dryRunOpt = Option<bool>("--dry-run")
    dryRunOpt.Description <- "Print proposals without writing files"
    let interactiveOpt = Option<bool>("--interactive")
    interactiveOpt.Description <- "Walk through each proposal interactively"
    let syncCmd = Command("sync", "Auto-detect version changes and apply cascade bumps")
    syncCmd.Add dryRunOpt
    syncCmd.Add interactiveOpt
    syncCmd.SetAction(fun result ->
        let dry   = result.GetValue dryRunOpt
        let inter = result.GetValue interactiveOpt
        Sync.run dry inter |> ignore)

    // ── update ─────────────────────────────────────────────────────────────
    let updateArgs = Argument<string[]>("pkg-version-pairs")
    updateArgs.Description <- "<package> <version> [<package> <version>...]"
    updateArgs.Arity <- ArgumentArity.OneOrMore
    let forceOpt = Option<bool>("--force")
    forceOpt.Description <- "Allow version downgrades"
    let updateDryRunOpt = Option<bool>("--dry-run")
    updateDryRunOpt.Description <- "Print proposals without writing files"
    let updateInteractiveOpt = Option<bool>("--interactive")
    updateInteractiveOpt.Description <- "Walk through each proposal interactively"
    let updateCmd = Command("update", "Bump one or more package versions and cascade")
    updateCmd.Add updateArgs
    updateCmd.Add forceOpt
    updateCmd.Add updateDryRunOpt
    updateCmd.Add updateInteractiveOpt
    updateCmd.SetAction(fun result ->
        let args  = result.GetValue updateArgs
        let dry   = result.GetValue updateDryRunOpt
        let inter = result.GetValue updateInteractiveOpt
        let force = result.GetValue forceOpt
        Update.run args dry inter force |> ignore)

    // ── root ───────────────────────────────────────────────────────────────
    let root = RootCommand("dotgraph — .NET Package Dependency Graph Tool")
    root.Add initCmd
    root.Add refreshCmd
    root.Add analyzeCmd
    root.Add diffCmd
    root.Add syncCmd
    root.Add updateCmd

    root.Parse(argv).Invoke()
