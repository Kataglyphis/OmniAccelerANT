#requires -Version 7.0

<#
.SYNOPSIS
  Runs Build-Windows.ps1 in the family Windows CI image via Stevedore's docker.exe; the agentic loop's build driver.

.DESCRIPTION
  Docs and MSIX are always off. The container is reused (tar-pipe transport) so its caches survive.
  The container plumbing is the hub's Invoke-RepoContainerBuild.ps1; this file keeps only the spec.

.PARAMETER Configurations
  Build-Windows.ps1 preset alias (clangcl-release, clangcl-debug, ...).
.PARAMETER SkipTests
  Forwarded to Build-Windows.ps1; the loop's test phase runs separately.
.PARAMETER SkipFormat
  Forwarded to Build-Windows.ps1.
.PARAMETER TestsOnly
  Run the Dart gates (Invoke-WindowsDartGates.ps1) in the container instead of a build.
.PARAMETER CodeQL
  Run Build-Windows.ps1's CodeQL path in the container; pair with -CodeQLDownload for the query packs.
.PARAMETER FreshContainer
  Discard the reusable build container first.
.PARAMETER Image
  Image override; defaults to the family Windows CI image.
.PARAMETER Force
  Build even while a Linux lane rewrites the tree this transfer reads (AGENTS.md § 5).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Configurations = '',
    [switch]$SkipTests,
    [switch]$SkipFormat,
    [switch]$TestsOnly,
    [switch]$FreshContainer,
    [string]$Image = '',
    [switch]$CodeQL,
    [switch]$CodeQLDownload,
    [switch]$CleanCodeQLDb,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$guardModule = Join-Path $PSScriptRoot 'modules\WindowsLaneGuard.Common.psm1'
Import-Module $guardModule -Force

# One lane at a time per checkout (AGENTS.md § 5); Invoke-LinuxLane.ps1 guards the other direction.
$linuxLanes = @(Get-RunningLinuxLane)
if ($linuxLanes.Count -gt 0 -and -not $Force) {
    throw (Get-LaneConflictMessage -Busy $linuxLanes)
}

# The container plumbing has one owner: the hub's Invoke-RepoContainerBuild.ps1.
$runner = Join-Path $repoRoot 'third_party\ANTfrastructure\windows\scripts\build\Invoke-RepoContainerBuild.ps1'
if (-not (Test-Path -LiteralPath $runner)) { throw "Required script not found: $runner (run: git submodule update --init --recursive third_party/ANTfrastructure)" }

# Tokens must be space-free (docker CLI -> cmd /S /C -> %*); C:\ws is the tar-pipe workspace.
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
    # Without -CodeQLDownload the container lacks the query suites and both analyses fail.
    if ($CodeQL) { $buildArgv += '-CodeQL' }
    if ($CodeQLDownload) { $buildArgv += '-CodeQLDownload' }
    if ($CleanCodeQLDb) { $buildArgv += '-CleanCodeQLDb' }
}

# Only what the host runs comes back: deep cargo/cxxbridge paths exceed MAX_PATH and abort the transfer.
$outputDirs = if ($TestsOnly) {
    @()
} else {
    @('logs', 'build/windows/x64/runner', 'build/windows/x64/plugins', 'build/windows/x64/bin')
}

# bsdtar matches every pattern at every depth, so a root 'build' needs omission here, not an exclude.
# Raw enumeration: Get-ChildItem would answer with WhatIf records under -WhatIf.
$rootOnlyExclude = @('build', 'out', 'logs', '.dart_tool', '.venv')
$inboundItems = @([System.IO.Directory]::GetFileSystemEntries($repoRoot) |
    ForEach-Object { [System.IO.Path]::GetFileName($_) } |
    Where-Object { $_ -notin $rootOnlyExclude })

# See docs/source/platforms.md § Tar-pipe inbound exclusions
$inboundExclude = @(
    '.git/modules', '.git/objects/pack', '.git/objects/??',
    'ephemeral', '.dart_tool', '.venv', 'doc/api', 'third_party/DocumANTation',
    'third_party/OxidANT/target'
)

& $runner -RepoRoot $repoRoot -ContainerName 'omniaccelerant-agentic-build' `
    -BuildCommand $buildArgv -Image $Image -Isolation 'process' `
    -InboundItems $inboundItems -InboundExclude $inboundExclude `
    -KeepDirs @('logs', '.dart_tool', '.venv') `
    -OutputDirs $outputDirs `
    -OutboundExclude @('CMakeCache.txt', 'CMakeFiles', '.ninja_deps', '.ninja_log', '*.obj', '*.pdb') `
    -FreshContainer:$FreshContainer -WhatIf:$WhatIfPreference

if (-not $TestsOnly -and -not $WhatIfPreference) {
    # Build-Windows.ps1 checks the container's trees; this checks the copy that reached the host.
    $runnerRoot = Join-Path $repoRoot 'build\windows\x64\runner'
    $exe = Get-ChildItem -LiteralPath $runnerRoot -Filter 'omni_accelerant.exe' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $exe) {
        throw ("Build reported success but no omni_accelerant.exe reached the host under $runnerRoot. " +
            'The outbound artifact transfer is broken - compare the container build log under logs/.')
    }
    Write-Host "Delivered: $($exe.FullName)" -ForegroundColor Green
}

if (-not $WhatIfPreference) { Write-Host 'Container build finished successfully.' -ForegroundColor Green }
