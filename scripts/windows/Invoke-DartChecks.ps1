#requires -Version 7.0

<#
.SYNOPSIS
Runs ONLY the Dart gate (format, analyze, test) in the lane's container image.

.DESCRIPTION
There is no Flutter or Dart SDK on this host, which makes it look as though the
smallest unit of feedback is a whole container lane. It is not: the image
carries the SDK at /opt/flutter, and running just the Dart gate against a
bind-mounted checkout costs ~23 s warm (measured 2026-09-16; ~214 s the first
time, which is `flutter pub get` populating the cache volume).

This is NOT a substitute for Invoke-LinuxLane.ps1. It runs the Dart gate and
nothing else: no CMake gate, no native build, no packaging, no Rust, no wasm.
Use it to iterate; use the lane to believe the result. See AGENTS.md § 5.

.PARAMETER Fix
Rewrite files with `dart format` instead of failing on unformatted ones. Without
it the format step is the gate's own form (--set-exit-if-changed).

.PARAMETER SkipFormat
Skip the format step.

.PARAMETER SkipAnalyze
Skip `flutter analyze`. It is the slow one (~165 s — it analyses the whole
workspace), so skipping it makes a test-only loop noticeably faster.

.PARAMETER SkipTest
Skip `flutter test`.

.EXAMPLE
.\scripts\windows\Invoke-DartChecks.ps1
.EXAMPLE
.\scripts\windows\Invoke-DartChecks.ps1 -SkipAnalyze          # fastest test loop
.EXAMPLE
.\scripts\windows\Invoke-DartChecks.ps1 -Fix                  # format in place
#>

param(
	[switch] $Fix,
	[switch] $SkipFormat,
	[switch] $SkipAnalyze,
	[switch] $SkipTest,
	# Empty resolves from ANTfrastructure's versions.env, exactly as
	# Invoke-LinuxLane.ps1 does — one owner for the image ref.
	[string] $Image = '',
	[string] $Platform = 'linux/amd64',
	# Named volume for PUB_CACHE. It must not live on the bind-mounted Windows
	# drive: pub installs a package by renaming it out of .pub-cache/_temp, and
	# that mount cannot do the rename — AGENTS.md § 5.
	[string] $PubCacheVolume = 'omni-dart-checks-pubcache'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

$engine = (Get-Command 'nerdctl' -ErrorAction SilentlyContinue)?.Source
if (-not $engine) {
	$candidate = Join-Path $env:ProgramFiles 'Rancher Desktop\resources\resources\win32\bin\nerdctl.exe'
	if (Test-Path $candidate) { $engine = $candidate }
}
if (-not $engine) {
	throw "nerdctl not found. Install Rancher Desktop, or put nerdctl on PATH."
}

if (-not $Image) {
	# Get-CiImageReference, exactly as Invoke-LinuxLane.ps1 does it — see the
	# longer note there. A hand-rolled versions.env read stood here first and
	# was the fourth copy of a parse the hub owns and tests
	# (test-ci-image-ref.sh asserts it agrees with verify_ci_image_refs.py).
	. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
	Import-BuildModule 'WindowsContainerImage.Common'
	if (-not (Get-Command -Name 'Get-CiImageReference' -ErrorAction SilentlyContinue)) {
		throw ("WindowsContainerImage.Common was imported but exports no Get-CiImageReference. " +
			"The pinned ANTfrastructure predates it - bump third_party/ANTfrastructure, or pass -Image explicitly.")
	}
	# No arguments: it resolves versions.env from its own location, so the answer
	# comes out of the ANTfrastructure this repo actually pins.
	$Image = Get-CiImageReference
}

# Volumes start root-owned; the image runs as uid 1001.
& $engine 'volume' 'create' $PubCacheVolume 2>&1 | Out-Null
& $engine 'run' '--rm' '--user' 'root' `
	'--mount' "type=volume,source=${PubCacheVolume},target=/vol" `
	'--platform' $Platform 'alpine' 'chown' '1001:1001' '/vol' 2>&1 | Out-Null

$formatCmd = if ($Fix) {
	'dart format lib test integration_test test_driver'
} else {
	# The gate's own form. NOT `dart format .`, which ignores
	# analysis_options.yaml and would rewrite third_party/ — AGENTS.md § 4.
	'dart format --output=none --set-exit-if-changed lib test integration_test test_driver'
}

$steps = @()
if (-not $SkipFormat) { $steps += "echo '=== format ==='; $formatCmd" }
if (-not $SkipAnalyze) { $steps += "echo '=== analyze ==='; flutter analyze" }
if (-not $SkipTest) { $steps += "echo '=== test ==='; flutter test" }
if ($steps.Count -eq 0) { throw 'Nothing to do: every step was skipped.' }

# `set -e` so the first failing step is the exit code, and safe.directory
# because the checkout is owned by the host user, not uid 1001.
$script = @(
	'set -e'
	'export PATH=/opt/flutter/bin:$PATH'
	'git config --global --add safe.directory "*" >/dev/null 2>&1 || true'
	'flutter pub get'
) + $steps -join '; '

$stepNames = @()
if (-not $SkipFormat) { $stepNames += if ($Fix) { 'format (fix)' } else { 'format' } }
if (-not $SkipAnalyze) { $stepNames += 'analyze' }
if (-not $SkipTest) { $stepNames += 'test' }

Write-Host "image : $Image"
Write-Host "steps : $($stepNames -join ', ')"
Write-Host ''

& $engine 'run' '--rm' `
	'--platform' $Platform `
	'-v' "${repoRoot}:/workspace" `
	'--mount' "type=volume,source=${PubCacheVolume},target=/pubcache" `
	'-e' 'PUB_CACHE=/pubcache' `
	'-w' '/workspace' `
	$Image `
	'bash' '-lc' $script

exit $LASTEXITCODE
