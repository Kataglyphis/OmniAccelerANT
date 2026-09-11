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

if (-not $Image) {
	. (Join-Path $PSScriptRoot '..\windows\Resolve-BuildModule.ps1')
	Import-BuildModule 'WindowsContainerImage.Common'
	if (-not (Get-Command -Name 'Get-CiImageReference' -ErrorAction SilentlyContinue)) {
		throw "WindowsContainerImage.Common exports no Get-CiImageReference; bump third_party/ContainerHub or pass -Image explicitly."
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

& $engine 'volume' 'create' $CacheVolume 2>&1 | Out-Null
& $engine 'run' '--rm' '--user' 'root' `
	'--mount' "type=volume,source=${CacheVolume},target=/vol" `
	'--platform' 'linux/amd64' 'alpine' 'chown' '1001:1001' '/vol' 2>&1 | Out-Null

$renovateArgs = @()
if ($Apply) { $renovateArgs += '--apply' }
if ($DryRun) { $renovateArgs += '--dry-run' }
if ($Refresh) { $renovateArgs += '--refresh' }
if ($PrintBin) { $renovateArgs += '--print-bin' }
if ($Managers) { $renovateArgs += @('--managers', $Managers) }

$entry = if ($Recurse) { 'scripts/linux/renovate-submodules.sh' } else { 'scripts/linux/renovate-local.sh' }

$inner = @'
git config --global --add safe.directory '/workspace'
git config --global --add safe.directory '/workspace/*'
git config --global url."https://github.com/".insteadOf "git@github.com:"
__AUTOCRLF__
export RENOVATE_LOCAL_CACHE=/cache/kataglyphis
bash __ENTRY__ "$@"
'@
$inner = $inner.Replace('__ENTRY__', $entry)

$autocrlf = ''
$gitCmd = Get-Command 'git' -ErrorAction SilentlyContinue
if ($gitCmd) {
	$value = (& $gitCmd.Source -C $repoRoot config --get core.autocrlf 2>$null | Select-Object -First 1)
	if ($value) { $autocrlf = "git config --global core.autocrlf $value" }
}
$inner = $inner.Replace('__AUTOCRLF__', $autocrlf)

$engineArgs = @(
	'run', '--name', $ContainerName,
	'--platform', 'linux/amd64',
	'-v', "${repoRoot}:/workspace",
	'--mount', "type=volume,source=${CacheVolume},target=/cache",
	'-w', '/workspace',
	$Image,
	'bash', '-c', $inner, '--'
) + $renovateArgs

Write-Host "engine : $engine"
Write-Host "cache  : $CacheVolume -> /cache"
Write-Host "command: $($engineArgs -join ' ')"
Write-Host ''

& $engine @engineArgs
$exitCode = $LASTEXITCODE

if (-not $KeepContainer) {
	& $engine 'container' 'remove' $ContainerName 2>&1 | Out-Null
}

exit $exitCode
