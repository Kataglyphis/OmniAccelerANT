param(
	[string] $WorkspaceDir = (Join-Path $PSScriptRoot "..\.."),
	[string] $BuildRootDir = "",
	[string] $Configuration = "Release"
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
	$candidateLayout = Resolve-KataglyphisWindowsLayout -BuildRootFull $candidateRoot -WindowsBuildConfig $windowsBuildConfig -Configuration $Configuration
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
	$pluginPathEntries = @($pluginDir, (Split-Path $pluginDll -Parent), (Join-Path $buildDirReleaseFull "bin"))
	
	# Add GStreamer bin path if it exists to fix missing DLLs at runtime
	$gstreamerBin = "C:\Program Files\gstreamer\1.0\msvc_x86_64\bin"
	if (Test-Path -LiteralPath $gstreamerBin -PathType Container) {
		$pluginPathEntries += $gstreamerBin
	}

	# Add ONNX Runtime bin/lib paths if they exist
	$onnxBin = "C:\onnxruntime\lib"
	if (Test-Path -LiteralPath $onnxBin -PathType Container) {
		$pluginPathEntries += $onnxBin
	}

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

	# AddressSanitizer (clang-cl Debug preset): the instrumented plugin imports
	# clang_rt.asan_dynamic-x86_64.dll. It MUST be Microsoft's runtime (shipped
	# with VS BuildTools), not LLVM's -- LLVM's aborts the full Flutter app with
	# an unsuppressible bad-free on allocations that COM/the CRT make before the
	# ASan runtime is initialized. Stage Microsoft's DLL next to the exe (and in
	# bin\) and relax the two mixed-instrumentation interceptor checks.
	$asanDllName = "clang_rt.asan_dynamic-x86_64.dll"
	$needsAsan = ($Configuration -match "Debug") -or `
		(Test-Path -LiteralPath (Join-Path $buildDirReleaseFull $asanDllName) -PathType Leaf)
	if ($needsAsan) {
		$msAsan = Get-ChildItem "C:\Program Files*\Microsoft Visual Studio\*\BuildTools\VC\Tools\MSVC\*\bin\Hostx64\x64\$asanDllName" -ErrorAction SilentlyContinue |
			Sort-Object FullName -Descending | Select-Object -First 1
		if ($null -ne $msAsan) {
			foreach ($dest in @($buildDirReleaseFull, (Join-Path $buildDirReleaseFull "bin"))) {
				if (Test-Path -LiteralPath $dest -PathType Container) {
					Copy-Item -LiteralPath $msAsan.FullName -Destination (Join-Path $dest $asanDllName) -Force
				}
			}
			Write-Host "[Start-Windows] Staged Microsoft ASan runtime: $($msAsan.FullName)"
			if ([string]::IsNullOrWhiteSpace($env:ASAN_OPTIONS)) {
				$env:ASAN_OPTIONS = "alloc_dealloc_mismatch=0:check_malloc_usable_size=0"
			}
		} else {
			Write-Warning "[Start-Windows] Microsoft ASan runtime not found under VS BuildTools; an ASan-instrumented app may abort on startup."
		}
	}

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
		$originalLoc = Get-Location
		Set-Location -LiteralPath (Split-Path $exePath -Parent)
		try {
			& $exePath 2>&1 | Tee-Object -FilePath $logPath
			$processExitCode = $LASTEXITCODE
		} finally {
			Set-Location -LiteralPath $originalLoc.Path
		}
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