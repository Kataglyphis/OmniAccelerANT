#requires -Version 7.0

<#
.SYNOPSIS
Runs the Linux CI lane locally, in the same image and with the same script and
arguments the workflow uses. See AGENTS.md § 5.
#>

param(
	[ValidateSet('native', 'android', 'web')]
	[string] $Lane = 'native',
	[ValidateSet('x64', 'arm64')]
	[string] $Arch = 'x64',
	# Empty resolves from ANTfrastructure's versions.env below. That file is the
	# single source of truth for the family image ref and the workflows reach it
	# through the composite actions' `image` input defaults; a literal here would
	# be a fourth copy that nothing compares to the other three.
	[string] $Image = '',
	[string] $BuildMode = 'release',
	# Empty resolves from pubspec.yaml below — AGENTS.md § 5.
	[string] $AppName = '',
	[string] $PackageFormats = 'tar,deb,flatpak,appimage',
	[string] $InstallPackagingDeps = 'true',
	# 'true' because both Linux workflows pass --strict-checks true
	# (reusable-linux.yml for both architectures, and web.yml) and this driver's
	# entire contract is "same image, same script, same arguments as the
	# workflow". It defaulted to 'false' until 2026-09-16, which meant the local
	# lane graded LESS than CI: a format or analyze failure warned here and red
	# there, so the one run that was supposed to catch it was the one that could
	# not. Note this is not the same switch as the android lane's non-strict
	# checks (ci-container-run-android.sh), which are deliberate.
	[string] $StrictChecks = 'true',
	# CodeQL is OFF by default since 2026-09-17 (owner directive): the android
	# scan is budgeted in hours and no longer runs in CI, so the driver and the
	# workflow both send --run-codeql false. This switch is the local opt-in for
	# a manual, scoped run — it deliberately makes -CheckParity differ.
	[switch] $RunCodeQL,
	[switch] $SkipDocs,
	[switch] $KeepContainer,
	# Compare the arguments this driver would send against the lane's workflow
	# (`script:` + `extra-args`), resolving ${{ matrix.* }}, ${{ env.* }} and a
	# reusable workflow's ${{ inputs.* }} the way the workflow would. Reports and
	# exits before touching the container engine: no volume, no container.
	# BACKLOG.md: a checker that diffs flag NAMES would not have caught
	# -StrictChecks defaulting to 'false' against a workflow passing 'true'.
	[switch] $CheckParity,
	# Run even though another lane's container is up. The generated files at the
	# checkout root are per-host, so two lanes on one tree overwrite each other
	# and the failure names the innocent lane — AGENTS.md § 5.
	[switch] $Force,
	[string] $ContainerName = "kataglyphis-linux-lane-$Lane-$Arch",
	# AGENTS.md § 5.
	#
	# '/workspace/.pub-cache' joined this list on 2026-09-16. PUB_CACHE defaults
	# to <repo>/.pub-cache (ANTfrastructure's lane-prologue.sh:63), which on this
	# box is a bind-mounted Windows drive — and pub installs a package by
	# renaming it out of .pub-cache/_temp, which is exactly the operation a
	# Windows bind mount cannot do for the container uid:
	#   Rename failed, path = '/workspace/.pub-cache/_temp/dirXXXXXX'
	#   (OS Error: Permission denied, errno = 13)
	# The trap is that it only fires when pub actually DOWNLOADS something. With
	# a warm cache the lane resolves from disk, renames nothing and passes — so
	# this sat undetected until a pubspec.yaml edit changed the resolution. In
	# other words the local lane was green precisely as long as you did not touch
	# dependencies, which is when you most want it. CI is unaffected: there the
	# workspace is a real Linux filesystem.
	# '/workspace/third_party/OxidANT/target' joined for the same reason on the
	# same day, found by the web lane: cargo builds an rlib by writing a
	# temp-archive directory and then REMOVING it, and the bind mount refuses the
	# remove for the container uid:
	#   error: failed to build archive at '.../libwasm_bindgen_macro_support-*.rlib':
	#   failed to remove temporary directory: Permission denied (os error 13)
	#   at path '.../out/.tmpXXXXXX.temp-archive'
	# The web lane hits it hardest because `-Z build-std` recompiles the standard
	# library, so it is doing archive work for hundreds of crates.
	[string[]] $ContainerNativePaths = @(
		'/workspace/build',
		'/workspace/.pub-cache',
		'/workspace/third_party/OxidANT/target'
	),
	# Debugging switches only; CI has no equivalent.
	[string[]] $Env = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Reads a lane workflow's container invocation: the folded `script:` block and
# the one-line `extra-args:` with their ${{ }} expressions unresolved, and every
# `env:` block of the file keyed by name. Deliberately not a YAML parser — the
# files are controlled here, and a generic parser is a dependency this driver
# does not carry.
function Get-LaneWorkflowSpec {
	param([Parameter(Mandatory)][string] $Path)

	$lines = Get-Content -LiteralPath $Path
	$envMap = @{}
	$envIndent = -1
	$scriptIndent = -1
	$scriptParts = @()
	$extraArgs = $null

	foreach ($line in $lines) {
		if ($null -eq $extraArgs -and $line -match '^\s*extra-args:\s*(\S.*?)\s*$') {
			$extraArgs = $Matches[1]
			continue
		}
		if ($line -match '^(\s*)env:\s*$') {
			$envIndent = $Matches[1].Length
			continue
		}
		if ($envIndent -ge 0) {
			if ($line -match '^\s*$') { continue }
			$indent = $line.Length - $line.TrimStart().Length
			if ($indent -le $envIndent) {
				$envIndent = -1
			}
			elseif ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*):\s*(.+?)\s*$') {
				$envMap[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
			}
		}
		if ($scriptIndent -lt 0) {
			if ($line -match '^(\s*)script:\s*>?-?\s*$') { $scriptIndent = $Matches[1].Length }
			continue
		}
		if ($line -match '^\s*$') { continue }
		$indent = $line.Length - $line.TrimStart().Length
		if ($indent -le $scriptIndent) { break }
		$scriptParts += $line.Trim()
	}

	if ($scriptIndent -lt 0) {
		throw "No folded 'script:' block in $Path"
	}
	if ($null -eq $extraArgs) {
		throw "No one-line 'extra-args:' in $Path"
	}
	return [pscustomobject]@{ Script = ($scriptParts -join ' '); ExtraArgs = $extraArgs; Env = $envMap }
}

# A per-arch caller (linux-x64.yml, linux-arm64.yml) holds no container step of
# its own: one job runs a LOCAL reusable workflow, and its `with:` block is what
# that workflow's ${{ inputs.* }} resolve to. Returns the callee's repo-relative
# path and that block keyed by input name, or $null when the file calls no local
# reusable workflow and so carries its steps itself. Flat `key: value` lines
# only; blank and comment lines never end the job.
function Get-LaneCallerInputs {
	param([Parameter(Mandatory)][string] $Path)

	$lines = @(Get-Content -LiteralPath $Path)
	$calls = @()
	for ($i = 0; $i -lt $lines.Count; $i++) {
		if ($lines[$i] -match '^(\s*)uses:\s*\./(\.github/workflows/[^\s#]+\.ya?ml)\s*$') {
			$calls += [pscustomobject]@{ Line = $i; Indent = $Matches[1].Length; Callee = $Matches[2] }
		}
	}
	if ($calls.Count -eq 0) { return $null }
	if ($calls.Count -gt 1) {
		throw "parity: $Path calls $($calls.Count) local reusable workflows; this reader expects at most one"
	}
	$call = $calls[0]

	# Back to the line after the job id, then forward through the job's keys.
	$first = $call.Line
	while ($first -gt 0) {
		$previous = $lines[$first - 1]
		if ($previous -notmatch '^\s*(#|$)' -and ($previous.Length - $previous.TrimStart().Length) -lt $call.Indent) { break }
		$first--
	}
	$withMap = @{}
	$inWith = $false
	for ($i = $first; $i -lt $lines.Count; $i++) {
		$line = $lines[$i]
		if ($line -match '^\s*(#|$)') { continue }
		$indent = $line.Length - $line.TrimStart().Length
		if ($indent -lt $call.Indent) { break }
		if ($indent -eq $call.Indent) {
			$inWith = $line -match '^\s*with:\s*$'
			continue
		}
		if ($inWith -and $line -match '^\s*([A-Za-z_][A-Za-z0-9_-]*):\s*(.+?)\s*$') {
			$withMap[$Matches[1]] = ($Matches[2] -replace '\s+#.*$', '').Trim('"').Trim("'")
		}
	}
	return [pscustomobject]@{ Callee = $call.Callee; Inputs = $withMap }
}

# Turns ${{ ... }} into values this run would have. Everything unresolvable
# throws: a placeholder nobody taught this function about must not compare as
# an empty string and pass.
function Resolve-LaneExpression {
	param(
		[Parameter(Mandatory)][string] $Text,
		[Parameter(Mandatory)][hashtable] $Values,
		[Parameter(Mandatory)][hashtable] $EnvMap,
		[hashtable] $CallerInputs = @{}
	)

	$evaluator = {
		param($match)
		$expr = $match.Groups[1].Value.Trim()
		if ($expr -match '^inputs\.([A-Za-z_][A-Za-z0-9_-]*)$') {
			$key = $Matches[1]
			if ($CallerInputs.ContainsKey($key)) { return $CallerInputs[$key] }
			throw "parity: no resolution for `${{ inputs.$key }} - the caller's with: block passes no '$key'"
		}
		if ($expr -match '^matrix\.([A-Za-z_][A-Za-z0-9_]*)$') {
			$key = $Matches[1]
			if ($Values.ContainsKey($key)) { return $Values[$key] }
			throw "parity: no resolution for `${{ matrix.$key }}"
		}
		if ($expr -match '^env\.([A-Za-z_][A-Za-z0-9_]*)$') {
			$key = $Matches[1]
			if ($EnvMap.ContainsKey($key)) { return $EnvMap[$key] }
			throw "parity: no resolution for `${{ env.$key }}"
		}
		throw "parity: unresolvable expression `${{ $expr }}"
	}
	return [regex]::Replace($Text, '\$\{\{\s*([^}]+?)\s*\}\}', $evaluator)
}

# --flag value pairs as an ordered map; a flag with no value maps to '<flag>'.
function Get-FlagMap {
	param([string[]] $Tokens)
	$map = [ordered]@{}
	for ($i = 0; $i -lt $Tokens.Count; $i++) {
		if (-not $Tokens[$i].StartsWith('--')) { continue }
		$value = '<flag>'
		if (($i + 1) -lt $Tokens.Count -and -not $Tokens[$i + 1].StartsWith('--')) {
			$value = $Tokens[$i + 1]
		}
		$map[$Tokens[$i]] = $value.Trim('"').Trim("'")
	}
	return $map
}

if (-not $Image) {
	# The family image reference is composed UPSTREAM, by
	# WindowsContainerImage.Common's Get-CiImageReference, whose Linux twin is
	# linux/scripts/ci-image-ref.sh and which ANTfrastructure's own
	# test-ci-image-ref.sh asserts composes the same string as
	# verify_ci_image_refs.py. What stood here was a third hand-rolled read of
	# versions.env, and a subtly weaker one: its `(.+)$` kept surrounding
	# quotes, which the upstream parser strips on purpose because a quoted value
	# once propagated as data into CMake.
	#
	# Resolve-BuildModule looks the module up in third_party/ANTfrastructure first,
	# so this is the same copy Build-Windows.ps1 builds against.
	. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
	Import-BuildModule 'WindowsContainerImage.Common'
	if (-not (Get-Command -Name 'Get-CiImageReference' -ErrorAction SilentlyContinue)) {
		throw ("WindowsContainerImage.Common was imported but exports no Get-CiImageReference. " +
			"The pinned ANTfrastructure predates it - bump third_party/ANTfrastructure, or pass -Image explicitly.")
	}
	# No arguments: the function resolves versions.env from its OWN location, so
	# the answer always comes out of the ANTfrastructure this repo actually pins.
	# A missing key throws there, naming the file - never an empty image ref,
	# which `nerdctl run` would read as "the next argument is the image".
	$Image = Get-CiImageReference
}

if (-not $AppName) {
	$pubspec = Join-Path $repoRoot 'pubspec.yaml'
	$nameLine = Select-String -LiteralPath $pubspec -Pattern '^name:\s*(\S+)' | Select-Object -First 1
	if (-not $nameLine) { throw "No 'name:' entry in $pubspec" }
	$AppName = $nameLine.Matches[0].Groups[1].Value -replace '_', '-'
}

# The workflows pair arch with platform; keep the pairs in step.
$platform = if ($Arch -eq 'x64') { 'linux/amd64' } else { 'linux/arm64' }

# Only the android lane implements a CodeQL scan, and since 2026-09-17 it is a
# manual opt-in: the workflow passes false, so the driver's default matches it
# (AGENTS.md § 5). -RunCodeQL is the local deviation. The local's name must not
# collide with the switch: PowerShell variable names are case-insensitive.
$runCodeQLArg = if ($RunCodeQL) { 'true' } else { 'false' }
$runDocs = if ($SkipDocs) { 'false' } else { ($Arch -eq 'x64').ToString().ToLower() }

# One entry per lane, mirroring that lane's workflow. Change the pair together:
#   native  -> .github/workflows/linux-x64.yml / linux-arm64.yml (by -Arch), whose
#              build job runs .github/workflows/reusable-linux.yml
#   android -> .github/workflows/android.yml
#   web     -> .github/workflows/web.yml
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
		# without it this lane overwrites the native lane's out/ — AGENTS.md § 5.
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-android.sh',
			'--arch', $Arch,
			'--build-mode', $BuildMode,
			'--flutter-dir', '/opt/flutter',
			'--app-name', "$AppName-apk",
			'--run-codeql', $runCodeQLArg)
	}
	'web' {
		# $Arch, not a literal: the workflow only has an x64 row today, but the
		# driver still selects the container --platform from -Arch, so a literal
		# here built an x64 app inside an arm64 container and said nothing.
		# The lane script validates the value, so a bad one exits 2 rather than
		# guessing.
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-web-linux.sh',
			'--arch', $Arch,
			'--flutter-dir', '/opt/flutter',
			'--strict-checks', $StrictChecks,
			'--run-codeql', 'false')
	}
}

# The android workflow does not pass --privileged; the other two do.
$privilegedArgs = if ($Lane -eq 'android') { @() } else { @('--privileged') }

# Only reusable-linux.yml - the native build, for both architectures - passes
# `-e CI=true`, so only this lane does.
# It is what makes generate-docs.sh chown the generated doc/api/ tree back to
# the workspace owner; without it the workflow needed a `sudo chown -R` step of
# its own and the same work existed twice. If a local engine cannot honour that
# chown the lane now fails instead of hiding it - that is a real difference
# between this machine and the runner, worth seeing rather than papering over.
$ciEnvArgs = if ($Lane -eq 'native') { @('-e', 'CI=true') } else { @() }

# Parity is about the VALUES the driver sends, not the flag names: the recorded
# failure was -StrictChecks defaulting to 'false' against workflows passing
# 'true', which a name-only diff cannot see. BACKLOG.md § duplication and drift.
# It runs before the engine is looked up, so it needs no nerdctl and creates no
# volume or container.
if ($CheckParity) {
	# The native lane is one workflow per architecture since 2026-09-24, and
	# both call reusable-linux.yml, which holds the container step. -Arch picks
	# the caller, and the caller's `with:` block supplies ${{ inputs.* }} - so
	# this grades against what linux-<arch>.yml really passes, not against this
	# run's own parameters.
	$workflowFile = switch ($Lane) {
		'native' { "linux-$Arch.yml" }
		'android' { 'android.yml' }
		'web' { 'web.yml' }
	}
	$workflowPath = Join-Path $repoRoot ".github/workflows/$workflowFile"
	$callerInputs = @{}
	$specPath = $workflowPath
	$laneCaller = Get-LaneCallerInputs -Path $workflowPath
	if ($laneCaller) {
		$callerInputs = $laneCaller.Inputs
		$specPath = Join-Path $repoRoot $laneCaller.Callee
		$workflowFile = "$workflowFile -> $(Split-Path -Leaf $laneCaller.Callee)"
	}
	$spec = Get-LaneWorkflowSpec -Path $specPath
	# Exactly the values a workflow LOCAL run would have; job-level env comes
	# from the file, inputs from the caller, and the android lane's one-row
	# matrix from this run's parameters.
	$parityValues = @{
		arch        = $Arch
		build_mode  = $BuildMode
		flutter_dir = '/opt/flutter'
		app_name    = if ($Lane -eq 'android') { "$AppName-apk" } else { $AppName }
		platform    = $platform
	}
	$resolvedScript = Resolve-LaneExpression -Text $spec.Script -Values $parityValues -EnvMap $spec.Env -CallerInputs $callerInputs
	$workflowTokens = @($resolvedScript -split '\s+' | Where-Object { $_ })
	$workflowMap = Get-FlagMap -Tokens $workflowTokens
	$driverMap = Get-FlagMap -Tokens $laneArgs

	$mismatches = @()
	if ($workflowTokens[0] -ne $laneArgs[0] -or $workflowTokens[1] -ne $laneArgs[1]) {
		$mismatches += "script: workflow '$($workflowTokens[0..1] -join ' ')' vs driver '$($laneArgs[0..1] -join ' ')'"
	}
	foreach ($flag in $workflowMap.Keys) {
		if (-not $driverMap.Contains($flag)) {
			$mismatches += "workflow sends $flag '$($workflowMap[$flag])'; driver does not"
		}
		elseif ($driverMap[$flag] -ne $workflowMap[$flag]) {
			$mismatches += "${flag}: workflow '$($workflowMap[$flag])' vs driver '$($driverMap[$flag])'"
		}
	}
	foreach ($flag in $driverMap.Keys) {
		if (-not $workflowMap.Contains($flag)) {
			$mismatches += "driver sends $flag '$($driverMap[$flag])'; workflow does not"
		}
	}

	# The engine half: `extra-args` against what this driver puts in front of
	# the image, token by token and in order. -Env stays out - debugging
	# switches with no CI twin.
	$resolvedExtra = Resolve-LaneExpression -Text $spec.ExtraArgs -Values $parityValues -EnvMap $spec.Env -CallerInputs $callerInputs
	$workflowExtra = @($resolvedExtra -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Trim('"').Trim("'") })
	$driverExtra = @(@() + $privilegedArgs + @('--platform', $platform) + $ciEnvArgs | Where-Object { $_ })
	if (($workflowExtra -join ' ') -cne ($driverExtra -join ' ')) {
		$mismatches += "extra-args: workflow '$($workflowExtra -join ' ')' vs driver '$($driverExtra -join ' ')'"
	}

	if ($mismatches.Count -gt 0) {
		Write-Host "parity FAILED ($Lane vs $workflowFile):"
		$mismatches | ForEach-Object { Write-Host "  - $_" }
		exit 1
	}
	Write-Host "parity ok ($Lane vs $workflowFile)"
	exit 0
}

$engine = (Get-Command 'nerdctl' -ErrorAction SilentlyContinue)?.Source
if (-not $engine) {
	$candidate = Join-Path $env:ProgramFiles 'Rancher Desktop\resources\resources\win32\bin\nerdctl.exe'
	if (Test-Path -LiteralPath $candidate) { $engine = $candidate }
}
if (-not $engine) {
	throw "nerdctl not found. Install Rancher Desktop, or put nerdctl on PATH."
}

# One lane at a time against this checkout — AGENTS.md § 5. The generated files
# at the root (android/local.properties, .dart_tool, the ephemeral plugin
# symlinks) are per-host, and two lanes running together overwrite each other
# mid-build while the failure names the innocent lane. The Windows build
# container is in the pattern because the trap spans platforms.
$laneContainers = & $engine 'ps' '--format' '{{.Names}}' 2>$null
$busy = @($laneContainers | Where-Object {
		($_ -like 'kataglyphis-linux-lane-*' -and $_ -ne $ContainerName) -or
		$_ -eq 'omniaccelerant-agentic-build'
	})
if ($busy.Count -gt 0 -and -not $Force) {
	throw ("Another lane's container is up: $($busy -join ', '). Two lanes on one checkout " +
		"overwrite each other's generated files (AGENTS.md § 5). Wait for it to exit, " +
		"or pass -Force when you know it is idle.")
}

# A named volume over each write-heavy path, always via the long --mount form
# — AGENTS.md § 5.
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

# Pre-clean, because containerd owns the container and the nerdctl client does
# not. Ctrl-C or a killed shell leaves it Up, and the NEXT run then dies on
#   name-store error / name "<name>" is already used by ID "<64 hex>"
# while the plain `container remove` below ALSO fails on it
#   ("is in running status. unpause/stop container first or force removal"),
# so the lane stays wedged until someone runs `nerdctl rm -f` by hand.
# `remove --force` exits 0 both on a running leftover and on no container at
# all, which is what makes it safe to run unconditionally.
& $engine 'container' 'remove' '--force' $ContainerName 2>&1 | Out-Null

$laneExitCode = 1
try {
	# Windows source path, never the translated /mnt form — AGENTS.md § 5.
	& $engine @engineArgs
	$laneExitCode = $LASTEXITCODE
}
finally {
	# In a finally so an interrupt cleans up too. -KeepContainer still wins, and
	# nothing here may touch $laneExitCode — the caller's verdict is the lane's,
	# not the cleanup's.
	if (-not $KeepContainer) {
		& $engine 'container' 'remove' '--force' $ContainerName 2>&1 | Out-Null
	}
}

exit $laneExitCode
