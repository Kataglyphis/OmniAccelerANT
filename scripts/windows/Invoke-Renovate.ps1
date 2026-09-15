#requires -Version 7.0

param(
	[switch] $Apply,
	[switch] $DryRun,
	[switch] $Refresh,
	[string] $Managers = '',
	[switch] $PrintBin,
	[switch] $Recurse,
	[string] $Image = '',
	[switch] $KeepContainer,
	[string] $ContainerName = 'kataglyphis-renovate',
	[string] $CacheVolume = 'kataglyphis-renovate-cache'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Dot-sourced unconditionally: BOTH module imports below need it, and one of
# them is not inside the -Image guard.
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')

if (-not $Image) {
	Import-BuildModule 'WindowsContainerImage.Common'
	if (-not (Get-Command -Name 'Get-CiImageReference' -ErrorAction SilentlyContinue)) {
		throw "WindowsContainerImage.Common exports no Get-CiImageReference; bump third_party/ANTfrastructure or pass -Image explicitly."
	}
	$Image = Get-CiImageReference
}

$engine = (Get-Command 'nerdctl' -ErrorAction SilentlyContinue)?.Source
if (-not $engine) {
	$candidate = Join-Path $env:ProgramFiles 'Rancher Desktop\resources\resources\win32\bin\nerdctl.exe'
	if (Test-Path -LiteralPath $candidate) { $engine = $candidate }
}
if (-not $engine) {
	throw "nerdctl not found. Install Rancher Desktop, or put nerdctl on PATH."
}

$renovateArgs = @()
if ($Apply) { $renovateArgs += '--apply' }
if ($DryRun) { $renovateArgs += '--dry-run' }
if ($Refresh) { $renovateArgs += '--refresh' }
if ($PrintBin) { $renovateArgs += '--print-bin' }
if ($Managers) { $renovateArgs += @('--managers', $Managers) }

# -Recurse is ANTfrastructure's renovate-fleet.sh in --vendored mode, not a local
# walker any more. This repo carried one (scripts/linux/renovate-submodules.sh,
# 135 lines) because the fleet driver refused to write inside a vendored
# checkout; --vendored/--in-place is the opt-in for exactly the two cases that
# refusal was never about, and this container is the second of them - it mounts
# ONE superproject, so every repo the run can reach is vendored and the default
# order is empty. third_party/ANTfrastructure/docs/dependency-updates.md
# #-vendored-the-two-cases-where-writing-in-place-is-right
if ($Recurse) {
	$entry = 'third_party/ANTfrastructure/linux/scripts/renovate-fleet.sh'
	$renovateArgs += '--vendored'
} else {
	$entry = 'scripts/linux/renovate-local.sh'
}

# Embedded in the command rather than passed after a `bash -c ... --`: the
# shared driver runs one bash string and forwards no trailing argv. Single
# quoted, with the POSIX '\'' escape, so a --managers value cannot reach the
# shell as syntax.
$quotedArgs = ($renovateArgs | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' '

# NO url.insteadOf REWRITE ANY MORE. It stood here while the vendored
# checkouts' own .gitmodules still carried ssh remotes, which a container with
# no ssh key cannot resolve. As of 2026-09-15 every .gitmodules this recursion
# reaches is https: third_party/AccelerANTgine (7 entries, including nanobind),
# third_party/OxidANT (1), third_party/ANTfrastructure (1, DocumANTation) and
# this repo's own 4. Re-check before reinstating it, do not assume.
$inner = @'
set -e
git config --global --add safe.directory '/workspace'
git config --global --add safe.directory '/workspace/*'
__AUTOCRLF__
export RENOVATE_LOCAL_CACHE=/cache/kataglyphis
test -f __ENTRY__ || { echo "no __ENTRY__ in the mounted workspace" >&2; exit 1; }
bash __ENTRY__ __ARGS__
'@
$inner = $inner.Replace('__ENTRY__', $entry).Replace('__ARGS__', $quotedArgs)

$autocrlf = ''
$gitCmd = Get-Command 'git' -ErrorAction SilentlyContinue
if ($gitCmd) {
	$value = (& $gitCmd.Source -C $repoRoot config --get core.autocrlf 2>$null | Select-Object -First 1)
	if ($value) { $autocrlf = "git config --global core.autocrlf $value" }
}
$inner = $inner.Replace('__AUTOCRLF__', $autocrlf)

$envFile = ''
$ghCmd = Get-Command 'gh' -ErrorAction SilentlyContinue
if ($ghCmd) {
	$token = (& $ghCmd.Source auth token 2>$null | Select-Object -First 1)
	if ($token) {
		$envFile = Join-Path ([System.IO.Path]::GetTempPath()) "kataglyphis-renovate-$([guid]::NewGuid().ToString('N')).env"
		Set-Content -LiteralPath $envFile -Value "GITHUB_COM_TOKEN=$token" -NoNewline
	}
}

# THE CONTAINER INVOCATION IS NOT THIS REPO'S. A hand-typed `run --name
# --platform -v --mount -w --env-file` line stood here, one of a family of such
# lines across the consumers that had each drifted. ANTfrastructure's
# WindowsBuildSweep.Common owns it as Invoke-InLinuxContainerBuild, which grew
# -Engine/-Platform/-Name/-KeepContainer/-NamedVolumes/-EnvFile for exactly this
# caller; it also creates and chowns the cache volume (a fresh one is
# root-owned and the image runs as uid 1001), which was a second copy here.
# -DockerExe wins over -Engine and keeps the resolved Rancher Desktop path.
Import-BuildModule 'WindowsBuildSweep.Common'
if (-not (Get-Command -Name 'Invoke-InLinuxContainerBuild' -ErrorAction SilentlyContinue)) {
	throw ("WindowsBuildSweep.Common was imported but exports no Invoke-InLinuxContainerBuild. " +
		"The pinned ANTfrastructure predates it - bump third_party/ANTfrastructure.")
}

$runnerArgs = @{
	RepoRoot      = $repoRoot
	Image         = $Image
	Command       = $inner
	DockerExe     = $engine
	Engine        = 'nerdctl'
	Platform      = 'linux/amd64'
	Name          = $ContainerName
	KeepContainer = [bool]$KeepContainer
	NamedVolumes  = @("${CacheVolume}:/cache")
}
if ($envFile) { $runnerArgs['EnvFile'] = $envFile }

Write-Host "engine : $engine"
Write-Host "cache  : $CacheVolume -> /cache"
Write-Host "entry  : $entry $quotedArgs"
Write-Host "token  : $(if ($envFile) { 'GITHUB_COM_TOKEN from gh' } else { 'none (GitHub lookups may be rate-limited)' })"
Write-Host ''

Invoke-InLinuxContainerBuild @runnerArgs
$exitCode = $LASTEXITCODE

if ($envFile) { Remove-Item -LiteralPath $envFile -Force -ErrorAction SilentlyContinue }

exit $exitCode
