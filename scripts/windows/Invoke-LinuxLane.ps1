#requires -Version 7.0

<#
.SYNOPSIS
Runs a Linux CI lane locally with the workflow's image, script and arguments (AGENTS.md § 5).
#>

param(
	[ValidateSet('native', 'android', 'web')]
	[string] $Lane = 'native',
	[ValidateSet('x64', 'arm64')]
	[string] $Arch = 'x64',
	# Empty resolves from the hub's versions.env, the image ref's one owner.
	[string] $Image = '',
	[string] $BuildMode = 'release',
	# Empty resolves from pubspec.yaml below — AGENTS.md § 5.
	[string] $AppName = '',
	[string] $PackageFormats = 'tar,deb,flatpak,appimage',
	[string] $InstallPackagingDeps = 'true',
	# 'true', as both Linux workflows pass: the local lane must not grade less than CI.
	[string] $StrictChecks = 'true',
	# Local opt-in for a manual android scan; CI sends --run-codeql false, so -CheckParity then differs.
	[switch] $RunCodeQL,
	[switch] $SkipDocs,
	[switch] $KeepContainer,
	# Compare argument VALUES with the lane's workflow, then exit before any container work.
	[switch] $CheckParity,
	# Run although another lane's container is up; two lanes on one tree overwrite each other (AGENTS.md § 5).
	[switch] $Force,
	[string] $ContainerName = "kataglyphis-linux-lane-$Lane-$Arch",
	# Named volumes where a Windows bind mount refuses the container uid's renames and removes (AGENTS.md § 5).
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

# Reads the folded script:, the one-line extra-args: and every env: block, unresolved; deliberately no YAML parser.
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

# The local reusable workflow a per-arch caller runs and its with: inputs, or $null; flat key: value lines only.
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

# Resolves ${{ }}; anything unknown throws rather than comparing as an empty string.
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
		# CI-only: the sccache mount changes where the cache lives, not what builds.
		if ($expr -eq 'steps.cc.outputs.docker-args') { return '' }
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
	# Composed upstream by Get-CiImageReference, never a local read of versions.env.
	. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
	Import-BuildModule 'WindowsContainerImage.Common'
	if (-not (Get-Command -Name 'Get-CiImageReference' -ErrorAction SilentlyContinue)) {
		throw ("WindowsContainerImage.Common was imported but exports no Get-CiImageReference. " +
			"The pinned ANTfrastructure predates it - bump third_party/ANTfrastructure, or pass -Image explicitly.")
	}
	# It reads the pinned hub's versions.env and throws on a missing key, never returning an empty ref.
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

# Named apart from the switch: PowerShell variable names are case-insensitive.
$runCodeQLArg = if ($RunCodeQL) { 'true' } else { 'false' }
$runDocs = if ($SkipDocs) { 'false' } else { ($Arch -eq 'x64').ToString().ToLower() }

# Mirrors each lane's workflow (native: linux-<arch>.yml -> reusable-linux.yml); change both together.
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
		# -apk, as in the workflow: the name is a path, and this lane would overwrite the native out/.
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-android.sh',
			'--arch', $Arch,
			'--build-mode', $BuildMode,
			'--flutter-dir', '/opt/flutter',
			'--app-name', "$AppName-apk",
			'--run-codeql', $runCodeQLArg)
	}
	'web' {
		# $Arch, not a literal: the container --platform follows -Arch too.
		@('bash', '/workspace/scripts/linux/ci/ci-container-run-web-linux.sh',
			'--arch', $Arch,
			'--flutter-dir', '/opt/flutter',
			'--strict-checks', $StrictChecks,
			'--run-codeql', 'false')
	}
}

# The android workflow does not pass --privileged; the other two do.
$privilegedArgs = if ($Lane -eq 'android') { @() } else { @('--privileged') }

# Only reusable-linux.yml passes -e CI=true, which lets generate-docs.sh chown doc/api/ back.
$ciEnvArgs = if ($Lane -eq 'native') { @('-e', 'CI=true') } else { @() }

# Compares VALUES, not flag names, and needs no engine: no nerdctl, volume or container.
if ($CheckParity) {
	# -Arch picks linux-<arch>.yml, whose with: block supplies reusable-linux.yml's inputs.
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
	# The android lane's one-row matrix, from this run's parameters.
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

	# extra-args token by token, in order; -Env stays out, having no CI twin.
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

. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule 'WindowsLaneGuard.Common'

$engine = Resolve-NerdctlExe
if (-not $engine) {
	throw "nerdctl not found. Install Rancher Desktop, or put nerdctl on PATH."
}

# One lane at a time per checkout (AGENTS.md § 5); nerdctl cannot see the Windows build's Stevedore container.
$busy = @(Get-RunningLinuxLane -Self $ContainerName -Nerdctl $engine)
if (Test-WindowsBuildActive) { $busy += 'omniaccelerant-agentic-build (a Windows build)' }
if ($busy.Count -gt 0 -and -not $Force) {
	throw (Get-LaneConflictMessage -Busy $busy)
}

# A named volume per write-heavy path, always via the long --mount form (AGENTS.md § 5).
$volumeArgs = @()
foreach ($nativePath in $ContainerNativePaths) {
	$volumeName = "kataglyphis-lane-$Lane-$Arch" + ($nativePath -replace '[^A-Za-z0-9]+', '-')
	& $engine 'volume' 'create' $volumeName 2>&1 | Out-Null
	# Volumes start root-owned; the image runs as uid 1001. The chown uses that image too: no stock image (owner rule 2026-10-05).
	& $engine 'run' '--rm' '--user' 'root' `
		'--mount' "type=volume,source=${volumeName},target=/vol" `
		'--platform' $platform '--entrypoint' 'chown' $Image '1001:1001' '/vol' 2>&1 | Out-Null
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

# An interrupted run leaves the container Up and wedges the next; remove --force is safe with none too.
& $engine 'container' 'remove' '--force' $ContainerName 2>&1 | Out-Null

$laneExitCode = 1
try {
	# Windows source path, never the translated /mnt form — AGENTS.md § 5.
	& $engine @engineArgs
	$laneExitCode = $LASTEXITCODE
}
finally {
	# In finally so an interrupt cleans up too; never touch $laneExitCode here.
	if (-not $KeepContainer) {
		& $engine 'container' 'remove' '--force' $ContainerName 2>&1 | Out-Null
	}
}

exit $laneExitCode
