param(
	[string] $WorkspaceDir = (Join-Path $PSScriptRoot "..\.."),
	[string] $BuildRootDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$buildConfigPath = Join-Path $PSScriptRoot "Windows.BuildConfig.ps1"
if (-not (Test-Path -LiteralPath $buildConfigPath -PathType Leaf)) {
	throw "Required Windows build config not found: $buildConfigPath"
}

. $buildConfigPath
$windowsBuildConfig = Get-KataglyphisWindowsBuildConfig

$pathsModulePath = Join-Path $PSScriptRoot "Windows.Paths.psm1"
if (-not (Test-Path -LiteralPath $pathsModulePath -PathType Leaf)) {
	throw "Required Windows paths module not found: $pathsModulePath"
}

Import-Module $pathsModulePath -Force

$repoRoot = (Resolve-Path $WorkspaceDir).Path

if ([string]::IsNullOrWhiteSpace($BuildRootDir)) {
	if ($windowsBuildConfig.ContainsKey('BuildRootDir') -and -not [string]::IsNullOrWhiteSpace($windowsBuildConfig.BuildRootDir)) {
		$BuildRootDir = $windowsBuildConfig.BuildRootDir
	}
}

$resolvedBuildRoots = Resolve-KataglyphisWindowsBuildRootCandidates `
	-RepoRoot $repoRoot `
	-BuildRootDir $BuildRootDir `
	-WindowsBuildConfig $windowsBuildConfig `
	-IncludeDefaultFallbacks

if ($resolvedBuildRoots.Count -eq 0) {
	throw "Build root directory could not be resolved. Set BuildRootDir in Windows.BuildConfig.ps1 or pass -BuildRootDir."
}

$selectedBuildRoot = $null
$cmakeBuildDir = $null
$buildDirReleaseFull = $null
$pluginDir = $null
$pluginDll = $null
$exePath = $null
$searchResults = [System.Collections.Generic.List[string]]::new()

foreach ($candidateRoot in $resolvedBuildRoots) {
	$candidateLayout = Resolve-KataglyphisWindowsLayout -BuildRootFull $candidateRoot -WindowsBuildConfig $windowsBuildConfig
	$candidateCmakeBuildDir = $candidateLayout.CMakeBuildDir
	$candidateBuildDirRelease = $candidateLayout.RunnerDir
	$candidatePluginDir = $candidateLayout.PluginDir
	$candidatePluginDll = $candidateLayout.RustPluginDllPath
	$candidateExePath = $candidateLayout.RunnerExePath

	$hasPlugin = Test-Path -LiteralPath $candidatePluginDll -PathType Leaf
	$hasExe = Test-Path -LiteralPath $candidateExePath -PathType Leaf

	$searchResults.Add("$candidateRoot => plugin=$hasPlugin exe=$hasExe")

	if ($hasPlugin -and $hasExe) {
		$selectedBuildRoot = $candidateRoot
		$cmakeBuildDir = $candidateCmakeBuildDir
		$buildDirReleaseFull = $candidateBuildDirRelease
		$pluginDir = $candidatePluginDir
		$pluginDll = $candidatePluginDll
		$exePath = $candidateExePath
		break
	}
}

if ($null -eq $selectedBuildRoot) {
	$diagnostics = $searchResults -join "; "
	throw "Kein lauffähiger Build gefunden. Geprüfte BuildRoots: $diagnostics. Starte zuerst scripts/windows/Build-Windows.ps1 mit passendem -BuildRootDir (z. B. out)."
}

$runnerDataDir = Join-Path $buildDirReleaseFull "data"
$runnerAotPath = Join-Path $runnerDataDir "app.so"

if (-not (Test-Path -LiteralPath $runnerAotPath -PathType Leaf)) {
	$aotCandidates = @(
		(Join-Path $selectedBuildRoot "windows/app.so"),
		(Join-Path $repoRoot "out/windows/app.so"),
		(Join-Path $repoRoot "build/windows/app.so")
	)

	$resolvedAotSource = $aotCandidates |
		Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
		Select-Object -First 1

	if ($null -ne $resolvedAotSource) {
		New-Item -ItemType Directory -Force -Path $runnerDataDir | Out-Null
		Copy-Item -LiteralPath $resolvedAotSource -Destination $runnerAotPath -Force
	}
}

$logFileName = [System.IO.Path]::GetFileName($windowsBuildConfig.RunLogRelativePath)
$logDirPath = Join-Path $repoRoot "logs"
$logPath = Join-Path $logDirPath $logFileName

$originalPath = $env:PATH
$psNativePreferenceAvailable = $null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue)
$originalPsNativePreference = $null
try {
	$pluginPathEntries = @($pluginDir)
	if (Test-Path -LiteralPath $pluginDir -PathType Container) {
		$pluginSubDirs = Get-ChildItem -LiteralPath $pluginDir -Directory -Recurse -ErrorAction SilentlyContinue |
			ForEach-Object { $_.FullName }
		$pluginPathEntries += $pluginSubDirs
	}

	$pluginPathEntries = @(
		$pluginPathEntries |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
			Sort-Object -Unique
	)

	New-Item -ItemType Directory -Force -Path $logDirPath | Out-Null

	$env:PATH = (($pluginPathEntries -join ";") + ";" + $env:PATH)
	if ($psNativePreferenceAvailable) {
		$originalPsNativePreference = $global:PSNativeCommandUseErrorActionPreference
		$global:PSNativeCommandUseErrorActionPreference = $false
	}
	$originalErrorActionPreference = $ErrorActionPreference
	$processExitCode = 1
	try {
		$ErrorActionPreference = "Continue"
		& $exePath 2>&1 | Tee-Object -FilePath $logPath
		$processExitCode = $LASTEXITCODE
	}
	finally {
		$ErrorActionPreference = $originalErrorActionPreference
	}

	exit $processExitCode
}
finally {
	if ($psNativePreferenceAvailable) {
		$global:PSNativeCommandUseErrorActionPreference = $originalPsNativePreference
	}
	$env:PATH = $originalPath
}