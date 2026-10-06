#requires -Version 7.0

<#
.SYNOPSIS
Runs ONLY the Dart gate (format, analyze, test) in the lane's container image.

.DESCRIPTION
Uses the image's /opt/flutter SDK (~23 s warm) to iterate; only Invoke-LinuxLane.ps1 is the real verdict.
No CMake gate, native build, packaging, Rust or wasm here. See AGENTS.md § 5.

.PARAMETER Fix
Format in place instead of failing on unformatted files.

.PARAMETER SkipFormat
Skip the format step.

.PARAMETER SkipAnalyze
Skip `flutter analyze`, the slow step (~165 s).

.PARAMETER SkipTest
Skip `flutter test`.

.EXAMPLE
.\scripts\windows\Invoke-DartChecks.ps1 -SkipAnalyze          # fastest test loop
.EXAMPLE
.\scripts\windows\Invoke-DartChecks.ps1 -Fix                  # format in place
.EXAMPLE
.\scripts\windows\Invoke-DartChecks.ps1 -Engine wslc          # WSL containers, the hub's CON62 pilot
#>

param(
	[switch] $Fix,
	[switch] $SkipFormat,
	[switch] $SkipAnalyze,
	[switch] $SkipTest,
	# Empty resolves from the hub's versions.env, the image ref's one owner.
	[string] $Image = '',
	[string] $Platform = 'linux/amd64',
	# A named volume: the bind mount cannot do pub's rename out of .pub-cache/_temp (AGENTS.md § 5).
	[string] $PubCacheVolume = 'omni-dart-checks-pubcache',
	# wslc pilots hub CON62: faster bind mounts, but no --platform, so x64 images only.
	[ValidateSet('nerdctl', 'wslc')]
	[string] $Engine = 'nerdctl'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

if ($Engine -eq 'wslc') {
	$engineExe = (Get-Command 'wslc' -ErrorAction SilentlyContinue)?.Source
	if (-not $engineExe) { throw "wslc not found: it ships with WSL 3.0 or later." }
	if ($Platform -ne 'linux/amd64') { throw "wslc has no --platform (microsoft/WSL#41123); -Platform $Platform needs -Engine nerdctl." }
	$platformArgs = @()
} else {
	$engineExe = (Get-Command 'nerdctl' -ErrorAction SilentlyContinue)?.Source
	if (-not $engineExe) {
		$candidate = Join-Path $env:ProgramFiles 'Rancher Desktop\resources\resources\win32\bin\nerdctl.exe'
		if (Test-Path $candidate) { $engineExe = $candidate }
	}
	if (-not $engineExe) {
		throw "nerdctl not found. Install Rancher Desktop, or put nerdctl on PATH."
	}
	$platformArgs = @('--platform', $Platform)
}

if (-not $Image) {
	# Composed upstream by Get-CiImageReference, as in Invoke-LinuxLane.ps1.
	. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
	Import-BuildModule 'WindowsContainerImage.Common'
	if (-not (Get-Command -Name 'Get-CiImageReference' -ErrorAction SilentlyContinue)) {
		throw ("WindowsContainerImage.Common was imported but exports no Get-CiImageReference. " +
			"The pinned ANTfrastructure predates it - bump third_party/ANTfrastructure, or pass -Image explicitly.")
	}
	# It reads the pinned hub's versions.env.
	$Image = Get-CiImageReference
}

# Volumes start root-owned; the image runs as uid 1001. The chown uses that image too: no stock image (owner rule 2026-10-05).
& $engineExe 'volume' 'create' $PubCacheVolume 2>&1 | Out-Null
& $engineExe 'run' '--rm' '--user' 'root' `
	'--mount' "type=volume,source=${PubCacheVolume},target=/vol" `
	@platformArgs '--entrypoint' 'chown' $Image '1001:1001' '/vol' 2>&1 | Out-Null

$formatCmd = if ($Fix) {
	'dart format lib test integration_test test_driver'
} else {
	# Not `dart format .`: it ignores analysis_options.yaml and rewrites third_party/ (AGENTS.md § 4).
	'dart format --output=none --set-exit-if-changed lib test integration_test test_driver'
}

$steps = @()
if (-not $SkipFormat) { $steps += "echo '=== format ==='; $formatCmd" }
if (-not $SkipAnalyze) { $steps += "echo '=== analyze ==='; flutter analyze" }
# The plugin is its own package with its own lock, so the root's `flutter test` never reaches its suite.
if (-not $SkipTest) { $steps += "echo '=== test ==='; flutter test; (cd packages/kataglyphis_native_inference && flutter pub get && flutter test)" }
if ($steps.Count -eq 0) { throw 'Nothing to do: every step was skipped.' }

# set -e makes the first failing step the exit code; safe.directory, as the host user owns the checkout.
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

Write-Host "engine: $Engine ($engineExe)"
Write-Host "image : $Image"
Write-Host "steps : $($stepNames -join ', ')"
Write-Host ''

& $engineExe 'run' '--rm' `
	@platformArgs `
	'-v' "${repoRoot}:/workspace" `
	'--mount' "type=volume,source=${PubCacheVolume},target=/pubcache" `
	'-e' 'PUB_CACHE=/pubcache' `
	'-w' '/workspace' `
	$Image `
	'bash' '-lc' $script

exit $LASTEXITCODE
