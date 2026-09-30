#requires -Version 7.0

<#
.SYNOPSIS
  Runs Build-Windows.ps1 in the family Windows CI image via Stevedore's docker.exe; the agentic loop's build driver.

.DESCRIPTION
  Docs and MSIX are always off. The container is reused (tar-pipe transport) so its caches survive.

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
    [switch]$CleanCodeQLDb,
    [switch]$Force
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

$guardModule = Join-Path $PSScriptRoot 'modules\WindowsLaneGuard.Common.psm1'
Import-Module $guardModule -Force

# One lane at a time per checkout (AGENTS.md § 5); Invoke-LinuxLane.ps1 guards the other direction.
$linuxLanes = @(Get-RunningLinuxLane)
if ($linuxLanes.Count -gt 0 -and -not $Force) {
    throw (Get-LaneConflictMessage -Busy $linuxLanes)
}

if ([string]::IsNullOrWhiteSpace($Image)) { $Image = Get-CiImageReference -Windows }
$docker = Resolve-DockerExe
Write-Host "Image:  $Image"
Write-Host "Docker: $docker"

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

# See docs/source/platforms.md § Tar-pipe inbound exclusions
$inboundExclude = @(
    '.git/modules', '.git/objects/pack', '.git/objects/??',
    'build', 'out', 'logs', 'ephemeral',
    '.dart_tool', '.venv', 'doc/api', 'third_party/DocumANTation',
    'third_party/OxidANT/target'
)

# Stream the command's output live and keep only the result object.
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

if ($containerResult) {
    Write-Host "Container run complete (transport: $($containerResult.Transport), container: $($containerResult.Container))." -ForegroundColor Green
}
