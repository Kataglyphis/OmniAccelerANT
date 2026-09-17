#requires -Version 7.0

<#
.SYNOPSIS
  Runs scripts/windows/Build-Windows.ps1 inside the family Windows CI image via
  Stevedore's docker.exe. This is the agentic loop's Windows build driver.

.DESCRIPTION
  The agentic loop invokes this as
  `pwsh -File scripts/windows/Build-Windows-Container.ps1 -Configurations <preset> -SkipTests`
  and, for its test phase, as `-TestsOnly`. Documentation generation and MSIX
  packaging are always off: both are release concerns and dominate a loop build.

  The container is REUSED across builds (ANTfrastructure's
  WindowsContainerBuild.Reuse, tar-pipe transport), so its container-local
  Cargo, sccache and pub caches survive. Discard it with -FreshContainer when a
  build behaves strangely. Background:
  third_party/ANTfrastructure/docs/windows-container-build-performance.md.

  The image reference is not written here on purpose: Get-CiImageReference
  composes it from the submodule's versions.env, the fleet's single owner.

.PARAMETER Configurations
  Build-Windows.ps1 preset alias (clangcl-release, clangcl-debug, ...).
.PARAMETER SkipTests
  Forwarded to Build-Windows.ps1; the loop's test phase runs separately.
.PARAMETER SkipFormat
  Forwarded to Build-Windows.ps1.
.PARAMETER TestsOnly
  Run the Dart gates in the container instead of a build
  (scripts/windows/Invoke-WindowsDartGates.ps1).
.PARAMETER CodeQL
  Run Build-Windows.ps1's CodeQL path (database cluster + analysis) inside the
  container. -CodeQLDownload fetches the query packs; the first run also
  downloads the CodeQL CLI into the container.
.PARAMETER FreshContainer
  Discard the reusable build container first.
.PARAMETER Image
  Image override; defaults to the family Windows CI image.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'containerResult',
    Justification = 'Assigned inside a ForEach-Object scriptblock and read after the pipeline; PSSA cannot see that.')]
[CmdletBinding()]
param(
    [string]$Configurations = '',
    [switch]$SkipTests,
    [switch]$SkipFormat,
    [switch]$TestsOnly,
    [switch]$FreshContainer,
    [string]$Image = '',
    [switch]$CodeQL,
    [switch]$CodeQLDownload,
    [switch]$CleanCodeQLDb
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulesDir = Join-Path $repoRoot 'third_party\ANTfrastructure\windows\scripts\modules'

$reuseModule = Join-Path $modulesDir 'WindowsContainerBuild.Reuse.psm1'
if (-not (Test-Path -LiteralPath $reuseModule -PathType Leaf)) {
    throw "Required module not found: $reuseModule (run: git submodule update --init --recursive third_party/ANTfrastructure)"
}
Import-Module $reuseModule -Force

$imageModule = Join-Path $modulesDir 'WindowsContainerImage.Common.psm1'
if (-not (Test-Path -LiteralPath $imageModule -PathType Leaf)) {
    throw "Required module not found: $imageModule (run: git submodule update --init --recursive third_party/ANTfrastructure)"
}
Import-Module $imageModule -Force

if ([string]::IsNullOrWhiteSpace($Image)) { $Image = Get-CiImageReference -Windows }
$docker = Resolve-DockerExe
Write-Host "Image:  $Image"
Write-Host "Docker: $docker"

# In-container argv. Every token must be space-free: it travels
# docker CLI -> cmd /S /C -> %* (see Resolve-ContainerBuildCommand).
# C:\ws is the tar-pipe workspace and is absent from the image.
$workspacePath = 'C:\ws'
if ($TestsOnly) {
    $buildArgv = @(
        'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        "$workspacePath\scripts\windows\Invoke-WindowsDartGates.ps1"
    )
} else {
    $buildArgv = @(
        'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        "$workspacePath\scripts\windows\Build-Windows.ps1",
        '-SkipDocs', '-SkipMsixPackaging'
    )
    if (-not [string]::IsNullOrWhiteSpace($Configurations)) { $buildArgv += @('-Configurations', $Configurations) }
    if ($SkipTests) { $buildArgv += '-SkipTests' }
    if ($SkipFormat) { $buildArgv += '-SkipFormat' }
    # CodeQL mode: Build-Windows.ps1 exits after Invoke-BuildCodeQL, which runs
    # the inner build itself. Without -CodeQLDownload the query suites are not
    # in the container and both analyze attempts fail.
    if ($CodeQL) { $buildArgv += '-CodeQL' }
    if ($CodeQLDownload) { $buildArgv += '-CodeQLDownload' }
    if ($CleanCodeQLDb) { $buildArgv += '-CleanCodeQLDb' }
}

# Only what the host actually runs comes back; the container keeps the full
# tree. Deep cargo/cxxbridge paths are excluded because they exceed MAX_PATH on
# extraction and abort the whole transfer.
$outputDirs = if ($TestsOnly) {
    @()
} else {
    @('logs', 'build/windows/x64/runner', 'build/windows/x64/plugins', 'build/windows/x64/bin')
}

# Inbound transfer exclusions. The .git entries are load-bearing in BOTH
# directions: Build-Windows.ps1's CMake format gate runs `git ls-files`, so the
# container needs a valid repo (HEAD + index + refs/ + objects/), but streaming
# the real .git costs ~1.2 GB per build (.git/modules 1 GB, .git/objects 164 MB)
# and .git/modules is the deep-path tree that aborts tar transfers. Excluding
# only pack/ and the 2-char loose-object fanout keeps the directory skeleton -
# `git ls-files` reads the index and never needs a single object.
# Patterns are matched on path COMPONENTS by bsdtar, so they must be exact:
# `out*` here excluded nlohmann's `include/nlohmann/detail/output/` and broke
# the C++ build with a missing binary_writer.hpp.
# `ephemeral` is load-bearing: the host checkout's Flutter plugin symlinks
# (windows/flutter/ephemeral/.plugin_symlinks/*) are junctions created by
# earlier local builds, and bsdtar ABORTS the whole archive on their stat
# failure - the stream silently lost everything after them. The build
# regenerates the ephemeral tree in-container (Flutter Pub Get + config-only).
# `third_party/OxidANT/target` joined this list on 2026-09-17, after it broke a
# build: the sync-back of the container's cargo cache writes Linux symlinks into
# this host tree as Windows reparse points with no readable target (found on
# cxxbridge/rust/cxx.h), and bsdtar then ABORTS the whole inbound archive on the
# stat failure - the build started with no scripts at all. The container builds
# into its own rust_target (CARGO_TARGET_DIR), so the host copy is not an input.
$inboundExclude = @(
    '.git/modules', '.git/objects/pack', '.git/objects/??',
    'build', 'out', 'logs', 'ephemeral',
    '.dart_tool', '.venv', 'doc/api', 'third_party/DocumANTation',
    'third_party/OxidANT/target'
)

# Invoke-ContainerBuild emits the in-container command's stdout as pipeline
# objects AND a result object. Capture the result, stream everything else, so
# the agentic loop's log gets live output instead of a buffer held to the end.
$containerResult = $null
Invoke-ContainerBuild -DockerExe $docker -Image $Image `
    -ContainerName 'omniaccelerant-agentic-build' `
    -RepoRoot $repoRoot -WorkspacePath $workspacePath `
    -BuildCommand $buildArgv `
    -InboundExclude $inboundExclude `
    -KeepDirs @('logs', '.dart_tool', '.venv') `
    -OutputDirs $outputDirs `
    -OutboundExclude @('CMakeCache.txt', 'CMakeFiles', '.ninja_deps', '.ninja_log', '*.obj', '*.pdb') `
    -IsolationArgs (Get-ContainerIsolationArgs -Isolation 'process') `
    -FreshContainer:$FreshContainer | ForEach-Object {
        if ($_ -is [System.Management.Automation.PSCustomObject]) {
            $containerResult = $_
        } else {
            Write-Host $_
        }
    }

if (-not $TestsOnly) {
    # A green build is not proof of delivery. Build-Windows.ps1 checks the
    # in-container trees; this checks the copy that actually reached the host.
    $runnerRoot = Join-Path $repoRoot 'build\windows\x64\runner'
    $exe = Get-ChildItem -LiteralPath $runnerRoot -Filter 'omni_accelerant.exe' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $exe) {
        throw ("Build reported success but no omni_accelerant.exe reached the host under $runnerRoot. " +
            'The outbound artifact transfer is broken - compare the container build log under logs/.')
    }
    Write-Host "Delivered: $($exe.FullName)" -ForegroundColor Green
}

if ($containerResult) {
    Write-Host "Container run complete (transport: $($containerResult.Transport), container: $($containerResult.Container))." -ForegroundColor Green
}
