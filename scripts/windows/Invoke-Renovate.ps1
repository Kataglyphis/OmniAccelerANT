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

# Dot-sourced unconditionally: one of the two imports below sits outside the -Image guard.
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

# -Recurse runs the hub's fleet driver with --vendored: this one-superproject mount makes every repo vendored.
if ($Recurse) {
	$entry = 'third_party/ANTfrastructure/linux/scripts/renovate-fleet.sh'
	$renovateArgs += '--vendored'
} else {
	$entry = 'scripts/linux/renovate-local.sh'
}

# Embedded, as the driver forwards no trailing argv; POSIX-quoted so a --managers value never parses as syntax.
$quotedArgs = ($renovateArgs | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' '

# No url.insteadOf rewrite: every .gitmodules this recursion reaches uses https, and the container has no ssh key.
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

# The hub's Invoke-InLinuxContainerBuild owns the run and the cache volume's chown; -DockerExe wins over -Engine.
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
