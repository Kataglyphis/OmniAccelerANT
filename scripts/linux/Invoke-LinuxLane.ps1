#requires -Version 7.0

<#
.SYNOPSIS
Runs the Linux CI lane locally, in the same image and with the same script and
arguments the workflow uses. See AGENTS.md § 4.
#>

param(
	[ValidateSet('native', 'android', 'web')]
	[string] $Lane = 'native',
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
	[string] $ContainerName = "kataglyphis-linux-lane-$Lane-$Arch",
	# Write-heavy trees that must not live on the bind-mounted host drive.
	# See AGENTS.md § 4, "The Linux lane, locally".
	[string[]] $ContainerNativePaths = @('/workspace/build')
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

# A named volume over each write-heavy path. The bind mount is NTFS through
# drvfs, which cannot do utime/chmod for the container uid — untarring the
# Flutter SDK onto it fails on every entry. The volume keeps the lane's
# arguments identical to CI's while the writes land on a Linux filesystem.
$volumeArgs = @()
foreach ($nativePath in $ContainerNativePaths) {
	$volumeName = "kataglyphis-lane-$Lane-$Arch" + ($nativePath -replace '[^A-Za-z0-9]+', '-')
	& $engine 'volume' 'create' $volumeName 2>&1 | Out-Null
	# Volumes start root-owned; the image runs as uid 1001.
	& $engine 'run' '--rm' '--user' 'root' '-v' "${volumeName}:/vol" `
		'--platform' $platform 'alpine' 'chown' '1001:1001' '/vol' 2>&1 | Out-Null
	$volumeArgs += @('-v', "${volumeName}:${nativePath}")
	Write-Host "volume : $volumeName -> $nativePath"
}

# One entry per lane, mirroring that lane's workflow. Change the pair together:
#   native  -> .github/workflows/dart_on_native_linux.yml
#   android -> .github/workflows/dart_build_android_app.yml
#   web     -> .github/workflows/dart_on_web_linux.yml
$laneArgs = switch ($Lane) {
	'native' {
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-native-linux.sh',
			'--arch', $Arch,
			'--build-mode', $BuildMode,
			'--flutter-dir', '/opt/flutter',
			'--app-name', $AppName,
			'--package-formats', $PackageFormats,
			'--install-packaging-deps', $InstallPackagingDeps,
			'--install-flutter', 'true',
			'--strict-checks', $StrictChecks,
			'--run-codeql', $runCodeQL,
			'--run-docs', $runDocs)
	}
	'android' {
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-android.sh',
			'--arch', $Arch,
			'--build-mode', $BuildMode,
			'--flutter-dir', '/opt/flutter',
			'--app-name', $AppName,
			'--run-codeql', $runCodeQL)
	}
	'web' {
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-web-linux.sh',
			'--arch', 'x64',
			'--flutter-dir', '/opt/flutter',
			'--install-flutter', 'true',
			'--strict-checks', $StrictChecks,
			'--run-codeql', 'false')
	}
}

# The android workflow does not pass --privileged; the other two do.
$privilegedArgs = if ($Lane -eq 'android') { @() } else { @('--privileged') }

$engineArgs = @(
	'run', '--name', $ContainerName
) + $privilegedArgs + @(
	'--platform', $platform,
	'-e', 'CARGO_HOME=/tmp/cargo-home',
	# The image's own flutter_tools/.dart_tool is root-owned in a read-only
	# overlay layer, so `flutter pub get` cannot rewrite it — AGENTS.md § 3.
	'--tmpfs', '/opt/flutter/packages/flutter_tools/.dart_tool:rw,mode=1777',
	'-v', "${repoRoot}:/workspace"
) + $volumeArgs + @(
	'-w', '/workspace',
	$Image
) + $laneArgs

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
