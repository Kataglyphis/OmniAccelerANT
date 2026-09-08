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
	# Empty resolves from ContainerHub's versions.env below. That file is the
	# single source of truth for the family image ref and the workflows reach it
	# through the composite actions' `image` input defaults; a literal here would
	# be a fourth copy that nothing compares to the other three.
	[string] $Image = '',
	[string] $BuildMode = 'release',
	# Empty resolves from pubspec.yaml below — AGENTS.md § 4.
	[string] $AppName = '',
	[string] $PackageFormats = 'tar,deb,flatpak,appimage',
	[string] $InstallPackagingDeps = 'true',
	[string] $StrictChecks = 'false',
	[switch] $SkipCodeQL,
	[switch] $SkipDocs,
	[switch] $KeepContainer,
	[string] $ContainerName = "kataglyphis-linux-lane-$Lane-$Arch",
	# AGENTS.md § 4.
	[string[]] $ContainerNativePaths = @('/workspace/build'),
	# Debugging switches only; CI has no equivalent.
	[string[]] $Env = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if (-not $Image) {
	# versions.env is inert KEY=value data - parsed, never sourced, and never
	# defaulted: a wrong-but-plausible image ref is exactly the drift this is
	# here to prevent, so a missing key is a hard stop naming the file.
	$versionsEnv = Join-Path $repoRoot 'third_party/ContainerHub/linux/scripts/01-core/versions.env'
	if (-not (Test-Path -LiteralPath $versionsEnv)) {
		throw "ContainerHub versions.env not found at $versionsEnv. Run: git submodule update --init --recursive third_party/ContainerHub"
	}
	$imageKeys = @{}
	foreach ($line in Get-Content -LiteralPath $versionsEnv) {
		if ($line -match '^(IMAGE_REGISTRY_PREFIX|CI_IMAGE_LINUX_TAG)=(.+)$') {
			$imageKeys[$Matches[1]] = $Matches[2].Trim()
		}
	}
	foreach ($key in @('IMAGE_REGISTRY_PREFIX', 'CI_IMAGE_LINUX_TAG')) {
		if (-not $imageKeys.ContainsKey($key)) {
			throw "$key is not defined in $versionsEnv. Bump the ContainerHub submodule, or pass -Image explicitly."
		}
	}
	$Image = '{0}:{1}' -f $imageKeys['IMAGE_REGISTRY_PREFIX'], $imageKeys['CI_IMAGE_LINUX_TAG']
}

if (-not $AppName) {
	$pubspec = Join-Path $repoRoot 'pubspec.yaml'
	$nameLine = Select-String -LiteralPath $pubspec -Pattern '^name:\s*(\S+)' | Select-Object -First 1
	if (-not $nameLine) { throw "No 'name:' entry in $pubspec" }
	$AppName = $nameLine.Matches[0].Groups[1].Value -replace '_', '-'
}

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

# Only the android lane implements a CodeQL scan. The native lane's driver now
# REFUSES --run-codeql true rather than warning and carrying on, and the web
# lane has never passed anything but false, so this is per-lane, not global.
$runCodeQL = if ($SkipCodeQL) { 'false' } else { ($Arch -eq 'x64').ToString().ToLower() }
$runDocs = if ($SkipDocs) { 'false' } else { ($Arch -eq 'x64').ToString().ToLower() }

# A named volume over each write-heavy path, always via the long --mount form
# — AGENTS.md § 4.
$volumeArgs = @()
foreach ($nativePath in $ContainerNativePaths) {
	$volumeName = "kataglyphis-lane-$Lane-$Arch" + ($nativePath -replace '[^A-Za-z0-9]+', '-')
	& $engine 'volume' 'create' $volumeName 2>&1 | Out-Null
	# Volumes start root-owned; the image runs as uid 1001.
	& $engine 'run' '--rm' '--user' 'root' `
		'--mount' "type=volume,source=${volumeName},target=/vol" `
		'--platform' $platform 'alpine' 'chown' '1001:1001' '/vol' 2>&1 | Out-Null
	$volumeArgs += @('--mount', "type=volume,source=${volumeName},target=${nativePath}")
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
			'--strict-checks', $StrictChecks,
			'--run-codeql', 'false',
			'--run-docs', $runDocs)
	}
	'android' {
		# -apk, like the workflow and run-android.sh: the name is a path, and
		# without it this lane overwrites the native lane's out/ — AGENTS.md § 4.
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-android.sh',
			'--arch', $Arch,
			'--build-mode', $BuildMode,
			'--flutter-dir', '/opt/flutter',
			'--app-name', "$AppName-apk",
			'--run-codeql', $runCodeQL)
	}
	'web' {
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-web-linux.sh',
			'--arch', 'x64',
			'--flutter-dir', '/opt/flutter',
			'--strict-checks', $StrictChecks,
			'--run-codeql', 'false')
	}
}

# The android workflow does not pass --privileged; the other two do.
$privilegedArgs = if ($Lane -eq 'android') { @() } else { @('--privileged') }

# Only dart_on_native_linux.yml passes `-e CI=true`, so only this lane does.
# It is what makes generate-docs.sh chown the generated doc/api/ tree back to
# the workspace owner; without it the workflow needed a `sudo chown -R` step of
# its own and the same work existed twice. If a local engine cannot honour that
# chown the lane now fails instead of hiding it - that is a real difference
# between this machine and the runner, worth seeing rather than papering over.
$ciEnvArgs = if ($Lane -eq 'native') { @('-e', 'CI=true') } else { @() }

$engineArgs = @(
	'run', '--name', $ContainerName
) + $privilegedArgs + @(
	'--platform', $platform
) + $ciEnvArgs + @($Env | ForEach-Object { '-e'; $_ }) + @(
	'-v', "${repoRoot}:/workspace"
) + $volumeArgs + @(
	'-w', '/workspace',
	$Image
) + $laneArgs

Write-Host "engine : $engine"
Write-Host "command: $($engineArgs -join ' ')"
Write-Host ''

# Windows source path, never the translated /mnt form — AGENTS.md § 4.
& $engine @engineArgs
$laneExitCode = $LASTEXITCODE

if (-not $KeepContainer) {
	& $engine 'container' 'remove' $ContainerName 2>&1 | Out-Null
}

exit $laneExitCode
