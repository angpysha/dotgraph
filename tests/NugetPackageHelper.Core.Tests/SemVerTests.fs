module NugetPackageHelper.Core.Tests.SemVerTests

open Xunit
open FsUnit.Xunit
open NugetPackageHelper.Core

// ── parse ──────────────────────────────────────────────────────────────────

[<Theory>]
[<InlineData("1.2.3",  1, 2, 3, null)>]
[<InlineData("0.0.0",  0, 0, 0, null)>]
[<InlineData("10.20.30", 10, 20, 30, null)>]
[<InlineData("1.0.0-alpha", 1, 0, 0, "alpha")>]
[<InlineData("2.1.0-rc.1",  2, 1, 0, "rc.1")>]
let ``parse valid semver`` input major minor patch pre =
    let result = SemVer.parse input
    result |> should not' (equal None)
    let v = result.Value
    v.Major     |> should equal major
    v.Minor     |> should equal minor
    v.Patch     |> should equal patch
    v.PreRelease |> should equal (Option.ofObj pre)

[<Theory>]
[<InlineData("")>]
[<InlineData("1.2")>]
[<InlineData("1.2.x")>]
[<InlineData("abc")>]
[<InlineData("1.2.3.4")>]
let ``parse invalid semver returns None`` input =
    SemVer.parse input |> should equal None

// ── toString ───────────────────────────────────────────────────────────────

[<Fact>]
let ``toString formats without pre-release`` () =
    SemVer.toString { Major=1; Minor=2; Patch=3; PreRelease=None }
    |> should equal "1.2.3"

[<Fact>]
let ``toString includes pre-release`` () =
    SemVer.toString { Major=1; Minor=0; Patch=0; PreRelease=Some "beta" }
    |> should equal "1.0.0-beta"

// ── compare ────────────────────────────────────────────────────────────────

[<Theory>]
[<InlineData("1.0.0", "2.0.0", -1)>]
[<InlineData("2.0.0", "1.0.0",  1)>]
[<InlineData("1.2.3", "1.2.3",  0)>]
[<InlineData("1.2.3", "1.2.4", -1)>]
[<InlineData("1.3.0", "1.2.9",  1)>]
let ``compare returns correct sign`` a b expected =
    let va = SemVer.parse a |> Option.get
    let vb = SemVer.parse b |> Option.get
    sign (SemVer.compare va vb) |> should equal expected

// ── detectBump ─────────────────────────────────────────────────────────────

[<Theory>]
[<InlineData("1.0.0", "2.0.0", "Major")>]
[<InlineData("1.0.0", "1.1.0", "Minor")>]
[<InlineData("1.0.0", "1.0.1", "Patch")>]
[<InlineData("1.2.3", "2.0.0", "Major")>]
let ``detectBump identifies bump type`` oldV newV expected =
    let old = SemVer.parse oldV |> Option.get
    let new' = SemVer.parse newV |> Option.get
    let bump = SemVer.detectBump old new'
    bump.ToString() |> should equal expected

// ── applyBump ──────────────────────────────────────────────────────────────

[<Fact>]
let ``applyBump Major resets minor and patch`` () =
    let v = SemVer.parse "1.2.3" |> Option.get
    SemVer.applyBump Major v |> should equal { Major=2; Minor=0; Patch=0; PreRelease=None }

[<Fact>]
let ``applyBump Minor resets patch`` () =
    let v = SemVer.parse "1.2.3" |> Option.get
    SemVer.applyBump Minor v |> should equal { Major=1; Minor=3; Patch=0; PreRelease=None }

[<Fact>]
let ``applyBump Patch increments patch only`` () =
    let v = SemVer.parse "1.2.3" |> Option.get
    SemVer.applyBump Patch v |> should equal { Major=1; Minor=2; Patch=4; PreRelease=None }

// ── cascadeBump ────────────────────────────────────────────────────────────

[<Fact>]
let ``cascadeBump Major trigger yields Minor`` () =
    SemVer.cascadeBump Major |> should equal Minor

[<Fact>]
let ``cascadeBump Minor trigger yields Patch`` () =
    SemVer.cascadeBump Minor |> should equal Patch

[<Fact>]
let ``cascadeBump Patch trigger yields Patch`` () =
    SemVer.cascadeBump Patch |> should equal Patch

// ── maxBump ────────────────────────────────────────────────────────────────

[<Fact>]
let ``maxBump picks the larger bump`` () =
    SemVer.maxBump Major Minor |> should equal Major
    SemVer.maxBump Patch Minor |> should equal Minor
    SemVer.maxBump Patch Patch |> should equal Patch

// ── suffix ordering and bumps ──────────────────────────────────────────────

[<Fact>]
let ``suffix compare orders 1.0.0-beta before 1.0.0`` () =
    let beta = SemVer.parse "1.0.0-beta" |> Option.get
    let release = SemVer.parse "1.0.0" |> Option.get
    sign (SemVer.compare beta release) |> should equal -1

[<Fact>]
let ``suffix compare orders 1.0.0-beta.2 before 1.0.0-beta.10`` () =
    let beta2 = SemVer.parse "1.0.0-beta.2" |> Option.get
    let beta10 = SemVer.parse "1.0.0-beta.10" |> Option.get
    sign (SemVer.compare beta2 beta10) |> should equal -1

[<Fact>]
let ``suffix isDowngrade from 1.2.0 to 1.2.0-beta`` () =
    let current = SemVer.parse "1.2.0" |> Option.get
    let earlier = SemVer.parse "1.2.0-beta" |> Option.get
    SemVer.isDowngrade current earlier |> should equal true

[<Fact>]
let ``suffix isDowngrade is false from 1.2.0-beta to 1.2.0`` () =
    let current = SemVer.parse "1.2.0-beta" |> Option.get
    let release = SemVer.parse "1.2.0" |> Option.get
    SemVer.isDowngrade current release |> should equal false

[<Theory>]
[<InlineData("1.2.0", "1.2.0-beta")>]
[<InlineData("1.2.0-beta", "1.2.0")>]
let ``suffix detectBump names equal numbers with a different suffix`` oldV newV =
    let old = SemVer.parse oldV |> Option.get
    let new' = SemVer.parse newV |> Option.get
    let bump = SemVer.detectBump old new'
    bump.ToString() |> should equal "Suffix"

[<Fact>]
let ``suffix applyBump Patch keeps pre-release`` () =
    let v = SemVer.parse "1.2.3-beta" |> Option.get
    SemVer.applyBump Patch v
    |> should equal { Major = 1; Minor = 2; Patch = 4; PreRelease = Some "beta" }
