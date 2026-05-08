namespace NugetPackageHelper.Core

type SemVer = {
    Major: int
    Minor: int
    Patch: int
    PreRelease: string option
}

type BumpType = Major | Minor | Patch

type PackageNode = {
    Name: string
    Version: SemVer
    ProjectPath: string
    Dependencies: string list
}

type DependencyGraph = {
    SolutionPath: string
    CreatedAt: System.DateTime
    Packages: Map<string, PackageNode>
}

type VersionProposal = {
    PackageName: string
    CurrentVersion: SemVer
    ProposedVersion: SemVer
    BumpType: BumpType
    Reason: string
}

type PackageChange = {
    PackageName: string
    SnapshotVersion: SemVer
    CurrentVersion: SemVer
    BumpType: BumpType
}

type SnapshotDiff = {
    Changed: PackageChange list
    CascadeGaps: VersionProposal list
    AlreadyCovered: VersionProposal list
}
