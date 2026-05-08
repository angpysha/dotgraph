namespace NugetPackageHelper.Core

open System

[<CompilationRepresentation(CompilationRepresentationFlags.ModuleSuffix)>]
module SemVer =

    let parse (s: string) : SemVer option =
        if String.IsNullOrWhiteSpace s then None
        else
            let s = s.Trim()
            let dashIdx = s.IndexOf('-')
            let pre = if dashIdx >= 0 then Some (s.Substring(dashIdx + 1)) else None
            let numPart = if dashIdx >= 0 then s.Substring(0, dashIdx) else s
            let parts = numPart.Split('.')
            if parts.Length <> 3 then None
            else
                match Int32.TryParse parts[0], Int32.TryParse parts[1], Int32.TryParse parts[2] with
                | (true, maj), (true, min), (true, pat) when maj >= 0 && min >= 0 && pat >= 0 ->
                    Some { Major = maj; Minor = min; Patch = pat; PreRelease = pre }
                | _ -> None

    let toString (v: SemVer) =
        let base' = $"{v.Major}.{v.Minor}.{v.Patch}"
        match v.PreRelease with
        | Some pre -> $"{base'}-{pre}"
        | None -> base'

    let compare (a: SemVer) (b: SemVer) : int =
        let mc = Operators.compare a.Major b.Major
        if mc <> 0 then mc
        else
            let nc = Operators.compare a.Minor b.Minor
            if nc <> 0 then nc
            else Operators.compare a.Patch b.Patch

    let isDowngrade (old: SemVer) (new': SemVer) = compare new' old < 0

    let detectBump (old: SemVer) (new': SemVer) : BumpType =
        if new'.Major > old.Major then Major
        elif new'.Minor > old.Minor then Minor
        else Patch

    let applyBump (bumpType: BumpType) (v: SemVer) : SemVer =
        match bumpType with
        | Major -> { v with Major = v.Major + 1; Minor = 0; Patch = 0; PreRelease = None }
        | Minor -> { v with Minor = v.Minor + 1; Patch = 0; PreRelease = None }
        | Patch -> { v with Patch = v.Patch + 1; PreRelease = None }

    let cascadeBump (trigger: BumpType) : BumpType =
        match trigger with
        | Major -> Minor
        | Minor | Patch -> Patch

    let maxBump (a: BumpType) (b: BumpType) : BumpType =
        match a, b with
        | Major, _ | _, Major -> Major
        | Minor, _ | _, Minor -> Minor
        | Patch, Patch -> Patch

    let bumpLabel = function
        | Major -> "MAJOR"
        | Minor -> "MINOR"
        | Patch -> "PATCH"
