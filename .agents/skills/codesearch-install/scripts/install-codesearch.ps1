# install-codesearch.ps1 — download + install flupkede/codesearch by platform (pwsh 7+).
#
# codesearch (https://github.com/flupkede/codesearch) is a Rust MCP server for multi-repo
# semantic code search. The `-with-csharp` release variant bundles the scip-csharp helper for
# C# semantic analysis and is the default here.
#
# Supported platforms (only these release assets exist):
#   windows x86_64 (.zip) | linux x86_64 (.tar.gz) | macos arm64 (.tar.gz)
param(
    [string]$Version = 'latest',            # release tag (e.g. v1.1.29) or 'latest'
    [switch]$NoCsharp,                       # install the plain variant instead of -with-csharp
    [string]$InstallDir = (Join-Path $HOME '.local/bin'),
    [switch]$Force,                          # reinstall even if already present
    [switch]$AddToPath,                      # add InstallDir to user PATH if missing
    [switch]$ConfigureMcp,                   # register codesearch in the host MCP config
    [string]$McpHost = 'auto',               # auto | cursor | claude | windsurf
    [string]$Target = (Get-Location).Path,   # repo root (for report + MCP config)
    [switch]$DryRun                          # resolve + print the asset URL, then exit
)

$ErrorActionPreference = 'Stop'

$Repo = 'flupkede/codesearch'
$WithCsharp = -not $NoCsharp

function Find-RepoRoot {
    param([string]$Start)
    $dir = (Resolve-Path $Start).Path
    while ($dir) {
        foreach ($marker in @('pipeline.manifest.json', 'AGENTS.md', '.git', '.agents/pipeline.home', '.beads')) {
            if (Test-Path (Join-Path $dir $marker)) { return $dir }
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return (Resolve-Path $Start).Path
}

function Get-Platform {
    $rt = [System.Runtime.InteropServices.RuntimeInformation]
    $winPlat = [System.Runtime.InteropServices.OSPlatform]::Windows
    $osxPlat = [System.Runtime.InteropServices.OSPlatform]::OSX
    $linPlat = [System.Runtime.InteropServices.OSPlatform]::Linux

    $os =
        if ($rt::IsOSPlatform($winPlat)) { 'windows' }
        elseif ($rt::IsOSPlatform($osxPlat)) { 'macos' }
        elseif ($rt::IsOSPlatform($linPlat)) { 'linux' }
        else { throw "Unsupported OS: $($rt::OSDescription)" }

    $arch = switch ($rt::OSArchitecture) {
        'X64' { 'x86_64' }
        'Arm64' { 'arm64' }
        default { [string]$rt::OSArchitecture }
    }

    # Only these three OS/arch combinations have release assets.
    $supported = @{
        'windows-x86_64' = 'zip'
        'linux-x86_64'   = 'tar.gz'
        'macos-arm64'    = 'tar.gz'
    }
    $key = "$os-$arch"
    if (-not $supported.ContainsKey($key)) {
        throw "No codesearch release for $key. Supported: $($supported.Keys -join ', '). See https://github.com/$Repo/releases"
    }
    return [pscustomobject]@{
        Os      = $os
        Arch    = $arch
        Key     = $key
        Ext     = $supported[$key]
        BinName = if ($os -eq 'windows') { 'codesearch.exe' } else { 'codesearch' }
    }
}

function Get-GitHubHeaders {
    $h = @{ 'User-Agent' = 'codesearch-install.ps1'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $h['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    return $h
}

function Resolve-Asset {
    param($Platform)
    $variant = if ($WithCsharp) { '-with-csharp' } else { '' }
    $assetName = "codesearch-$($Platform.Key)$variant.$($Platform.Ext)"

    $api =
        if ($Version -eq 'latest') { "https://api.github.com/repos/$Repo/releases/latest" }
        else { "https://api.github.com/repos/$Repo/releases/tags/$Version" }

    $release = Invoke-RestMethod -Uri $api -Headers (Get-GitHubHeaders)
    $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) {
        $have = ($release.assets | ForEach-Object { $_.name }) -join ', '
        throw "Asset '$assetName' not found in release $($release.tag_name). Available: $have"
    }
    return [pscustomobject]@{
        Name = $assetName
        Tag  = $release.tag_name
        Url  = $asset.browser_download_url
    }
}

function Test-AlreadyInstalled {
    param([string]$BinPath)
    $existing = $null
    if (Test-Path $BinPath) { $existing = $BinPath }
    else {
        $cmd = Get-Command codesearch -ErrorAction SilentlyContinue
        if ($cmd) { $existing = $cmd.Source }
    }
    if ($existing -and -not $Force) {
        Write-Host "codesearch already installed: $existing"
        try { & $existing --version } catch { }
        return $true
    }
    return $false
}

function Expand-Asset {
    param([string]$ArchivePath, [string]$Ext, [string]$DestDir)
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    if ($Ext -eq 'zip') {
        Expand-Archive -Path $ArchivePath -DestinationPath $DestDir -Force
    }
    else {
        # tar ships with Windows 10+, macOS, and Linux.
        & tar -xzf $ArchivePath -C $DestDir
        if ($LASTEXITCODE -ne 0) { throw "tar failed (exit $LASTEXITCODE) extracting $ArchivePath" }
    }
}

function Install-Binary {
    param([string]$ExtractDir, $Platform)
    $bin = Get-ChildItem -Path $ExtractDir -Recurse -File -Filter $Platform.BinName -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $bin) { throw "'$($Platform.BinName)' not found inside the downloaded archive" }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    # Copy the binary plus any sibling payload (e.g. scip-csharp helper) that ships next to it.
    $payloadRoot = Split-Path $bin.FullName -Parent
    Copy-Item -Path (Join-Path $payloadRoot '*') -Destination $InstallDir -Recurse -Force

    $installedBin = Join-Path $InstallDir $Platform.BinName
    if ($Platform.Os -ne 'windows') {
        & chmod +x $installedBin
        if ($Platform.Os -eq 'macos') {
            # best-effort: clear Gatekeeper quarantine so the binary can run
            & xattr -d com.apple.quarantine $installedBin 2>$null
        }
    }
    return $installedBin
}

function Add-ToUserPath {
    param([string]$Dir, $Platform)
    $onPath = ($env:PATH -split [System.IO.Path]::PathSeparator) -contains $Dir
    if ($onPath) { return }
    if ($Platform.Os -eq 'windows') {
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if (($userPath -split ';') -notcontains $Dir) {
            [Environment]::SetEnvironmentVariable('PATH', "$userPath;$Dir", 'User')
            Write-Host "Added $Dir to user PATH (restart shell to pick it up)."
        }
    }
    else {
        Write-Host "NOTE: $Dir is not on PATH. Add to your shell rc:"
        Write-Host "      export PATH=`"$Dir`:`$PATH`""
    }
}

function Set-McpConfig {
    param([string]$RepoRoot, [string]$HostName)

    $detected = $HostName
    if ($HostName -eq 'auto') {
        $detected =
            if (Test-Path (Join-Path $RepoRoot '.cursor')) { 'cursor' }
            elseif ((Test-Path (Join-Path $RepoRoot '.claude')) -or (Test-Path (Join-Path $RepoRoot 'CLAUDE.md'))) { 'claude' }
            elseif (Test-Path (Join-Path $RepoRoot '.windsurf')) { 'windsurf' }
            else { 'cursor' }
    }

    $configPath = switch ($detected) {
        'cursor' { Join-Path $RepoRoot '.cursor/mcp.json' }
        'claude' { Join-Path $RepoRoot '.mcp.json' }
        'windsurf' { Join-Path $RepoRoot '.windsurf/mcp.json' }
        default { throw "unknown MCP host: $detected" }
    }

    $config = [ordered]@{ mcpServers = [ordered]@{} }
    if (Test-Path $configPath) {
        $raw = Get-Content $configPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $existing = $raw | ConvertFrom-Json
            $config = [ordered]@{ mcpServers = [ordered]@{} }
            if ($existing.PSObject.Properties.Name -contains 'mcpServers' -and $existing.mcpServers) {
                foreach ($p in $existing.mcpServers.PSObject.Properties) {
                    $config.mcpServers[$p.Name] = $p.Value
                }
            }
            foreach ($p in $existing.PSObject.Properties) {
                if ($p.Name -ne 'mcpServers') { $config[$p.Name] = $p.Value }
            }
        }
    }

    $config.mcpServers['codesearch'] = [ordered]@{ command = 'codesearch'; args = @('mcp') }

    New-Item -ItemType Directory -Force -Path (Split-Path $configPath -Parent) | Out-Null
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
    Write-Host "MCP config updated ($detected): $configPath"
    return $configPath
}

# --- main ---
$RepoRoot = Find-RepoRoot -Start $Target
$platform = Get-Platform
$asset = Resolve-Asset -Platform $platform
$installedBin = Join-Path $InstallDir $platform.BinName

Write-Host "=== codesearch install ==="
Write-Host "  platform : $($platform.Key)"
Write-Host "  variant  : $(if ($WithCsharp) { 'with-csharp' } else { 'plain' })"
Write-Host "  release  : $($asset.Tag)"
Write-Host "  asset    : $($asset.Name)"
Write-Host "  url      : $($asset.Url)"
Write-Host "  installTo: $InstallDir"

if ($DryRun) {
    Write-Host 'DRY RUN — resolved asset only, nothing downloaded.'
    exit 0
}

if (Test-AlreadyInstalled -BinPath $installedBin) {
    if ($ConfigureMcp) { Set-McpConfig -RepoRoot $RepoRoot -HostName $McpHost | Out-Null }
    exit 0
}

$tmpArchive = Join-Path ([System.IO.Path]::GetTempPath()) $asset.Name
$tmpExtract = Join-Path ([System.IO.Path]::GetTempPath()) "codesearch-extract-$PID"

try {
    Write-Host "Downloading $($asset.Name) ..."
    Invoke-WebRequest -Uri $asset.Url -OutFile $tmpArchive -Headers (Get-GitHubHeaders)

    Write-Host 'Extracting ...'
    Expand-Asset -ArchivePath $tmpArchive -Ext $platform.Ext -DestDir $tmpExtract

    $installedBin = Install-Binary -ExtractDir $tmpExtract -Platform $platform
    Write-Host "Installed -> $installedBin"

    if ($AddToPath) { Add-ToUserPath -Dir $InstallDir -Platform $platform }

    Write-Host 'Verifying ...'
    & $installedBin --version
    if ($LASTEXITCODE -ne 0) { throw "verification failed: '$installedBin --version' exited $LASTEXITCODE" }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
finally {
    Remove-Item $tmpArchive -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
}

$mcpConfigPath = ''
if ($ConfigureMcp) { $mcpConfigPath = Set-McpConfig -RepoRoot $RepoRoot -HostName $McpHost }

$report = [ordered]@{
    schemaVersion = '1'
    tool          = 'codesearch'
    version       = $asset.Tag
    variant       = if ($WithCsharp) { 'with-csharp' } else { 'plain' }
    platform      = $platform.Key
    asset         = $asset.Name
    installPath   = $installedBin
    mcpConfig     = $mcpConfigPath
}
$reportDir = Join-Path $RepoRoot '.agents'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$report | ConvertTo-Json | Set-Content -Path (Join-Path $reportDir 'codesearch-install-report.json') -Encoding UTF8

Write-Host ''
Write-Host "PASS: codesearch $($asset.Tag) installed" -ForegroundColor Green
Write-Host 'Report: .agents/codesearch-install-report.json'
exit 0
