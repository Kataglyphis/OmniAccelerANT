#requires -Version 7.0

<#
.SYNOPSIS
Runs the Linux CI lane locally, in the same image and with the same script and
arguments the workflow uses. See AGENTS.md § 4.
#>

param(
	[ValidateSet('x64', 'arm64')]
	[string] $Arch = 'x64',
	[string] $Image = 'ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest-cross',
	[string] $BuildMode = 'release',
	[string] $AppName = 'kataglyphis-inference-engine',
	[string] $PackageFormats = 'tar,deb,flatpak,appimage',
	[string] $InstallPackagingDeps = 'true',
	[string] $StrictChecks = 'false',
	[switch] $SkipCodeQL,
	[switch] $SkipDocs,
	[switch] $KeepContainer,
	[string] $ContainerName = "kataglyphis-linux-lane-$Arch"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$engine = (Get-Command 'nerdctl' -ErrorAction SilentlyContinue)?.Source
if (-not $engine) {
	$candidate = Join-Path $env:ProgramFiles 'Rancher Desktop\resources\resources\win32\bin\nerdctl.exe'
	if (Test-Path -LiteralPath $candidate) { $engine = $candidate }
}
if (-not $engine) {
	throw "nerdctl not found. Install Rancher Desktop, or put nerdctl on PATH."
}

# The workflow matrix pairs arch with platform; keep the pairs in step.
$platform = if ($Arch -eq 'x64') { 'linux/amd64' } else { 'linux/arm64' }

$runCodeQL = if ($SkipCodeQL) { 'false' } else { ($Arch -eq 'x64').ToString().ToLower() }
$runDocs = if ($SkipDocs) { 'false' } else { ($Arch -eq 'x64').ToString().ToLower() }

# Mirrors .github/workflows/dart_on_native_linux.yml. Change both together.
$engineArgs = @(
	'run', '--name', $ContainerName,
	'--privileged', '--platform', $platform,
	'-e', 'CARGO_HOME=/tmp/cargo-home',
	'-v', "${repoRoot}:/workspace",
	'-w', '/workspace',
	$Image,
	'bash', '/workspace/scripts/linux/ci/ci-container-run-native-linux.sh',
	'--arch', $Arch,
	'--build-mode', $BuildMode,
	'--flutter-dir', '/workspace/flutter',
	'--app-name', $AppName,
	'--package-formats', $PackageFormats,
	'--install-packaging-deps', $InstallPackagingDeps,
	'--install-flutter', 'true',
	'--strict-checks', $StrictChecks,
	'--run-codeql', $runCodeQL,
	'--run-docs', $runDocs
)

Write-Host "engine : $engine"
Write-Host "command: $($engineArgs -join ' ')"
Write-Host ''

# nerdctl resolves a Windows source path itself; the already-translated
# /mnt/<drive> form binds an empty directory instead. If the mount comes up
# empty, D: is missing from containerd's own namespace — AGENTS.md § 4.
& $engine @engineArgs
$laneExitCode = $LASTEXITCODE

if (-not $KeepContainer) {
	& $engine 'container' 'remove' $ContainerName 2>&1 | Out-Null
}

exit $laneExitCode
