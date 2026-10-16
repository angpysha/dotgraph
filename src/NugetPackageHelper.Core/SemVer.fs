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

    // SemVer 2.0 pre-release precedence: dot-separated identifiers, numeric < non-numeric,
    // all-digit identifiers compared as integers, and a longer remainder ranks higher.
    let private compareIdentifiers (left: string) (right: string) : int =
        let isNumeric (id: string) =
            id.Length > 0 && String.forall Char.IsDigit id

        let compareNumeric (a: string) (b: string) =
            let trimZeros (s: string) =
                let trimmed = s.TrimStart('0')
                if trimmed.Length = 0 then "0" else trimmed
            let ta, tb = trimZeros a, trimZeros b
            let byLength = Operators.compare ta.Length tb.Length
            if byLength <> 0 then byLength else String.CompareOrdinal(ta, tb)

        match isNumeric left, isNumeric right with
        | true, true -> compareNumeric left right
        | true, false -> -1
        | false, true -> 1
        | false, false -> String.CompareOrdinal(left, right)

    let private comparePreRelease (left: string) (right: string) : int =
        let idsA = left.Split('.')
        let idsB = right.Split('.')
        let rec loop i =
            if i >= idsA.Length && i >= idsB.Length then 0
            elif i >= idsA.Length then -1
            elif i >= idsB.Length then 1
            else
                let cmp = compareIdentifiers idsA[i] idsB[i]
                if cmp <> 0 then cmp else loop (i + 1)
        loop 0

    let compare (a: SemVer) (b: SemVer) : int =
        let mc = Operators.compare a.Major b.Major
        if mc <> 0 then mc
        else
            let nc = Operators.compare a.Minor b.Minor
            if nc <> 0 then nc
            else
                let pc = Operators.compare a.Patch b.Patch
                if pc <> 0 then pc
                else
                    match a.PreRelease, b.PreRelease with
                    | None, None -> 0
                    | Some _, None -> -1
                    | None, Some _ -> 1
                    | Some left, Some right -> comparePreRelease left right

    let isDowngrade (old: SemVer) (new': SemVer) = compare new' old < 0

    let detectBump (old: SemVer) (new': SemVer) : BumpType =
        if new'.Major > old.Major then Major
        elif new'.Minor > old.Minor then Minor
        elif new'.Patch > old.Patch then Patch
        elif new'.Major = old.Major
             && new'.Minor = old.Minor
             && new'.Patch = old.Patch
             && old.PreRelease <> new'.PreRelease then Suffix
        else Patch

    let applyBump (bumpType: BumpType) (v: SemVer) : SemVer =
        match bumpType with
        | Major -> { v with Major = v.Major + 1; Minor = 0; Patch = 0 }
        | Minor -> { v with Minor = v.Minor + 1; Patch = 0 }
        | Patch -> { v with Patch = v.Patch + 1 }
        | Suffix -> v

    let cascadeBump (trigger: BumpType) : BumpType =
        match trigger with
        | Major -> Minor
        | Minor | Patch -> Patch
        | Suffix -> Suffix

    let maxBump (a: BumpType) (b: BumpType) : BumpType =
        match a, b with
        | Major, _ | _, Major -> Major
        | Minor, _ | _, Minor -> Minor
        | Patch, _ | _, Patch -> Patch
        | Suffix, Suffix -> Suffix

    let bumpLabel = function
        | Major -> "MAJOR"
        | Minor -> "MINOR"
        | Patch -> "PATCH"
        | Suffix -> "SUFFIX"
