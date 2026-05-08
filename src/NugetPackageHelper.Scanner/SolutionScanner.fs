namespace NugetPackageHelper.Scanner

open System.IO
open System.Text.RegularExpressions
open System.Xml.Linq

module SolutionScanner =

    /// Returns absolute paths to all .csproj / .fsproj files listed in the solution.
    let scan (solutionPath: string) : Result<string list, string> =
        let dir = Path.GetDirectoryName solutionPath
        let ext = Path.GetExtension(solutionPath).ToLowerInvariant()
        try
            let relativePaths =
                if ext = ".slnx" then
                    let doc = XDocument.Load solutionPath
                    doc.Descendants(XName.Get "Project")
                    |> Seq.choose (fun el ->
                        match el.Attribute(XName.Get "Path") with
                        | null -> None
                        | a    -> Some a.Value)
                    |> Seq.toList
                else
                    // Classic .sln format — capture project file path from Project(...) lines.
                    // Pattern: Project("...") = "Name", "path\to\file.csproj", "..."
                    let pattern = @"Project\(""[^""]+""\)\s*=\s*""[^""]+"",\s*""([^""]+\.(?:cs|fs)proj)"
                    Regex.Matches(File.ReadAllText solutionPath, pattern)
                    |> Seq.cast<Match>
                    |> Seq.map (fun m -> m.Groups[1].Value)
                    |> Seq.toList

            let absolute =
                relativePaths
                |> List.map (fun rel ->
                    let rel = rel.Replace('\\', Path.DirectorySeparatorChar)
                    Path.GetFullPath(Path.Combine(dir, rel)))
                |> List.filter File.Exists

            Ok absolute
        with ex ->
            Error $"Failed to parse solution file '{solutionPath}': {ex.Message}"

    /// Find the first .slnx or .sln file in a directory.
    let findSolution (dir: string) : Result<string, string> =
        let slnx = Directory.GetFiles(dir, "*.slnx")
        let sln  = Directory.GetFiles(dir, "*.sln")
        match slnx, sln with
        | [| f |], _  -> Ok f
        | _,  [| f |] -> Ok f
        | [||], [||]  -> Error "No .slnx or .sln file found in current directory."
        | _ ->
            let all = Array.append slnx sln
            let sep = "\n  "
            Error $"Multiple solution files found. Specify one with --solution.\n  {all |> String.concat sep}"
