#requires -Version 7.0

# Launch with pwsh: under 5.1 the hub modules' #requires fails as an opaque Import-Module error.

[CmdletBinding()]
param(
    [string] $WorkspaceDir = $PWD.Path,
    [string] $BuildRootDir = "",
    [string] $RustCrateDir = "third_party\OxidANT",
    [string] $RustDllName = "oxidant.dll",
    [string] $Configurations = "",
    [string] $CMakeGenerator = "Ninja",
    [string] $CMakeBuildType = "Release",
    [string] $LogDir = "logs",
    [switch] $CleanBuild,
    [switch] $SkipTests,
    [switch] $SkipFormat,
    [switch] $SkipDocs,
    [switch] $SkipBootstrapFlutterBuild,
    [switch] $SkipMsixPackaging,
    [switch] $ContinueOnError,
    [switch] $StopOnError,
    [switch] $CodeQL,
    [switch] $CleanCodeQLDb,
    [switch] $CodeQLDownload,
    [string[]] $RequiredTools = @('cmake', 'clang-cl', 'flutter', 'cargo', 'ninja'),
    [switch] $FailOnMissingRequiredTools
)

Set-StrictMode -Version Latest

$buildConfigPath = Join-Path $PSScriptRoot "Get-WindowsBuildConfig.ps1"
if (-not (Test-Path -LiteralPath $buildConfigPath -PathType Leaf)) {
    throw "Required Windows build config not found: $buildConfigPath"
}

. $buildConfigPath
$windowsBuildConfig = Get-KataglyphisWindowsBuildConfig

# Resolve-BuildModule prefers third_party/ANTfrastructure over scripts/windows/modules/.
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')

# Dependency order matters: Shared, then Build, then everything built on them.
Import-BuildModule @(
    'WindowsScripts.Shared'     # Resolve-WorkspacePath/-NormalizedPath, sccache + log-retention helpers
    'WindowsBuild.Common'       # build context/log/step primitives, cache env, plugin assertions
    'WindowsToolchain.Common'   # Invoke-ToolchainChecks
    'WindowsFlutter.Common'     # plugin symlink + permission_handler patches, host artifact sync
    'WindowsCMake.Common'       # Remove-BuildRootSafe
    'WindowsGstPlugins.Common'  # Assert-PkgConfigModule
    'WindowsUv.Common'          # Initialize-UvVenv + Install-UvRequirements (before its dependents)
    'WindowsFormatting.Common'  # Get-ProjectDartFiles
    'WindowsPaths.Common'       # project-local: this repo's Flutter windows/x64 layout
    'WindowsOrtRunner.Common'   # project-local: stamp the G6 proof of the runner's chain ONNX Runtime
    'WindowsFlutterAot.Common'  # project-local: the installed AOT snapshot matches the current kernel
)
# G6 and the hub's chain-ORT staging beside the exe; an older hub pin lacks them.
try { Import-BuildModule @('WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common') } catch {
    throw "This build needs ANTfrastructure's WindowsOrtProvenance.Common (G6) and WindowsOrtPayload.Common (hub commit ad08bc30 of 2026-09-25, third_party/ANTfrastructure/docs/onnxruntime-single-source.md § The shared Windows glue); move third_party/ANTfrastructure to it or later. ($($_.Exception.Message))"
}

if ($CodeQL) {
    Import-BuildModule 'WindowsCodeQL.Common'
}

if (-not $PSBoundParameters.ContainsKey('RustDllName')) {
    $RustDllName = $windowsBuildConfig.RustDllName
}

if ([string]::IsNullOrWhiteSpace($BuildRootDir)) {
    if ($windowsBuildConfig.ContainsKey('BuildRootDir') -and -not [string]::IsNullOrWhiteSpace($windowsBuildConfig.BuildRootDir)) {
        $BuildRootDir = $windowsBuildConfig.BuildRootDir
    } else {
        throw "Build root directory is not configured. Set BuildRootDir in Get-WindowsBuildConfig.ps1 or pass -BuildRootDir."
    }
}

$workspace = Resolve-WorkspacePath -Path $WorkspaceDir

if ($ContinueOnError -and $StopOnError) {
    throw "-ContinueOnError and -StopOnError cannot be used together."
}

if ($ContinueOnError) {
    $ErrorActionPreference = "Continue"
} else {
    $ErrorActionPreference = "Stop"
}

$context = New-BuildContext -Workspace $workspace -LogDir $LogDir -StopOnError:$StopOnError
Open-BuildLog -Context $context

$buildRootCandidates = @(Resolve-KataglyphisWindowsBuildRootCandidates `
    -RepoRoot $workspace `
    -BuildRootDir $BuildRootDir `
    -WindowsBuildConfig $windowsBuildConfig)

if ($buildRootCandidates.Count -eq 0) {
    throw "Build root directory is not configured. Set BuildRootDir in Get-WindowsBuildConfig.ps1 or pass -BuildRootDir."
}

# Caches live in container-local storage: bind mounts cost heavy I/O and break SQLite locking.
$fastLocalCache = Initialize-BuildCacheEnvironment -Context $context

$originalBuildRoot = $buildRootCandidates[0]
$buildRoot = Join-Path $fastLocalCache "build"
$env:CARGO_TARGET_DIR = Join-Path $fastLocalCache "rust_target"
$env:FLUTTER_BUILD_DIR = $buildRoot

$layout = Resolve-KataglyphisWindowsLayout -BuildRootFull $buildRoot -WindowsBuildConfig $windowsBuildConfig
$cmakeBuildDir = $layout.CMakeBuildDir
$buildDirFull = $layout.RunnerDir
$windowsSrc = Resolve-NormalizedPath -Path (Join-Path $workspace "windows")
$rustDir = Resolve-NormalizedPath -Path (Join-Path $workspace $RustCrateDir)
$cargoTargetBase = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $rustDir "target" }
$dllSource = Resolve-NormalizedPath -Path (Join-Path $cargoTargetBase "release/$RustDllName")
$dllDestPath = $layout.RustPluginDllPath
$dllDestDir = [System.IO.Path]::GetDirectoryName($dllDestPath)
$installedPluginsDir = Resolve-NormalizedPath -Path (Join-Path $buildDirFull "plugins")
$nativeAssetsDir = Resolve-NormalizedPath -Path (Join-Path $buildRoot "native_assets/windows")
$generatedPluginsCMake = Resolve-NormalizedPath -Path (Join-Path $workspace "windows/flutter/generated_plugins.cmake")

$buildDirRelease = Join-Path (Join-Path (Join-Path $BuildRootDir "windows") "x64") "runner"

$env:BUILD_DIR_RELEASE = $buildDirRelease

$rawPresets = if (-not [string]::IsNullOrEmpty($Configurations)) { $Configurations -split ',' | ForEach-Object { $_.Trim() } } else { @("") }

$presetMapping = @{
    "clangcl-debug" = "x64-ClangCL-Windows-Debug"
    "clangcl-profile" = "x64-ClangCL-Windows-Profile"
    "clangcl-release" = "x64-ClangCL-Windows-Release"
    "msvc-debug" = "x64-MSVC-Windows-Debug"
    "msvc-release" = "x64-MSVC-Windows-Release"
    "clang-debug" = "x64-Clang-Windows-Debug"
    "clang-profile" = "x64-Clang-Windows-Profile"
    "clang-release" = "x64-Clang-Windows-Release"
}

$presetsToRun = @()
foreach ($p in $rawPresets) {
    if ($presetMapping.ContainsKey($p)) {
        $presetsToRun += $presetMapping[$p]
    } elseif ([string]::IsNullOrEmpty($p)) {
        $presetsToRun += ""
    } else {
        $presetsToRun += $p
    }
}

$hadUnhandledError = $false

try {
    Write-BuildLog -Context $context -Message "=== Kataglyphis Windows Build Script ==="
    Write-BuildLog -Context $context -Message "Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-BuildLog -Context $context -Message "Logging to: $($context.LogPath)"
    Write-BuildLog -Context $context -Message ""
    Write-BuildLog -Context $context -Message "=== Configuration ==="
    Write-BuildLog -Context $context -Message "Workspace:        $workspace"
    Write-BuildLog -Context $context -Message "BuildRootDir:     $BuildRootDir"
    Write-BuildLog -Context $context -Message "BuildDirRelease:  $buildDirRelease"
    Write-BuildLog -Context $context -Message "BuildRoot:        $buildRoot"
    Write-BuildLog -Context $context -Message "BuildDirFull:     $buildDirFull"
    Write-BuildLog -Context $context -Message "InstalledPlugins: $installedPluginsDir"
    Write-BuildLog -Context $context -Message "BuildPluginsDir:  $dllDestDir"
    Write-BuildLog -Context $context -Message "CMakeBuildDir:    $cmakeBuildDir"
    if (-not [string]::IsNullOrEmpty($Configurations)) {
        Write-BuildLog -Context $context -Message "CMakePresets:     $rawPresets (mapped to: $($presetsToRun -join ', '))"
    }
    Write-BuildLog -Context $context -Message "CMakeGenerator:   $CMakeGenerator"
    Write-BuildLog -Context $context -Message "CMakeBuildType:   $CMakeBuildType"
    Write-BuildLog -Context $context -Message "RustDir:          $rustDir"
    Write-BuildLog -Context $context -Message "Rust DLL source:  $dllSource"
    Write-BuildLog -Context $context -Message "Rust DLL dest:    $dllDestDir"
    Write-BuildLog -Context $context -Message "SkipTests:        $SkipTests"
    Write-BuildLog -Context $context -Message "SkipDocs:         $SkipDocs"
    Write-BuildLog -Context $context -Message "SkipFlutterBuild: $SkipBootstrapFlutterBuild"
    Write-BuildLog -Context $context -Message "SkipMsixPackaging: $SkipMsixPackaging"
    Write-BuildLog -Context $context -Message "ContinueOnError:  $ContinueOnError"
    Write-BuildLog -Context $context -Message "StopOnError:      $StopOnError"
    Write-BuildLog -Context $context -Message "CleanCodeQLDb:    $CleanCodeQLDb"
    Write-BuildLog -Context $context -Message "CodeQLDownload:   $CodeQLDownload"
    Write-BuildLog -Context $context -Message "RequiredTools:    $($RequiredTools -join ', ')"
    Write-BuildLog -Context $context -Message "FailOnMissingRequiredTools: $FailOnMissingRequiredTools"
    Write-BuildLog -Context $context -Message ("=" * 60)

    if ($CodeQL) {
        $codeQLForwardParameters = @{}
        foreach ($pair in $PSBoundParameters.GetEnumerator()) {
            $codeQLForwardParameters[$pair.Key] = $pair.Value
        }
        $codeQLForwardParameters['SkipBootstrapFlutterBuild'] = $true

        Write-BuildLog -Context $context -Message "CodeQL mode: forcing SkipBootstrapFlutterBuild to analyze only non-bootstrap steps."
        # Scoped like the android scan (AGENTS.md § 5); an older hub pin lacks the parameter.
        $codeQLConfig = Join-Path $workspace '.github\codeql\codeql-config.yml'
        if (-not (Get-Command Invoke-BuildCodeQL).Parameters.ContainsKey('CodeScanningConfig')) {
            throw "Invoke-BuildCodeQL has no -CodeScanningConfig in this ANTfrastructure pin; move third_party/ANTfrastructure to hub commit 4dbf68b9 or later rather than scan unscoped."
        }
        Invoke-BuildCodeQL -Context $context -Workspace $workspace -ForwardParameters $codeQLForwardParameters -BuildScriptPath $MyInvocation.MyCommand.Path -CodeScanningConfig $codeQLConfig
        exit 0
    }

    Invoke-BuildStep -Context $context -StepName "Environment Check" -Script {
        Invoke-ToolchainChecks -Context $context -RequiredTools $RequiredTools -FailOnMissingRequiredTools:$FailOnMissingRequiredTools
    }

    Invoke-BuildStep -Context $context -StepName "Media Runtime Preflight" -Script {
        # Read at configure time by rust_builder/windows/CMakeLists.txt; "" builds featureless.
        if ($null -eq (Get-Item -Path "Env:KATAGLYPHIS_RUST_FEATURES" -ErrorAction SilentlyContinue)) {
            $env:KATAGLYPHIS_RUST_FEATURES = "gstreamer,onnxruntime_dynamic,onnxruntime_directml"
        }
        Write-BuildLog -Context $context -Message "Rust features: '$($env:KATAGLYPHIS_RUST_FEATURES)'"

        if ($env:KATAGLYPHIS_RUST_FEATURES -match "gstreamer") {
            # All three modules the crate binds, now rather than minutes later inside cargo.
            Assert-PkgConfigModule `
                -Module @('gstreamer-1.0', 'gstreamer-app-1.0', 'gstreamer-video-1.0') `
                -Context "the Rust 'gstreamer' feature (webcam capture). Set KATAGLYPHIS_RUST_FEATURES='' to build without it"
        }
    }

    Invoke-BuildStep -Context $context -StepName "Git Configuration" -Script {
        Invoke-BuildExternal -Context $context -File "git" -Parameters @("config", "--global", "core.longpaths", "true") -IgnoreExitCode
    }

    if (-not $SkipBootstrapFlutterBuild) {
        Invoke-BuildStep -Context $context -StepName "Flutter Dependencies" -Critical -Script {
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("pub", "get") -IgnoreExitCode
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("config", "--enable-windows-desktop") -IgnoreExitCode
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping Flutter dependency steps (SkipFlutterBuild set)."
    }

    # Flutter-specific gates stay here; Invoke-BuildExternal fails the step on a non-zero exit.
    if (-not $SkipFormat) {
        Invoke-BuildStep -Context $context -StepName "Dart Format Verification" -Script {
            Push-Location $workspace
            try {
                $dartFiles = @(Get-ProjectDartFiles -WorkspacePath $workspace)
                if ($dartFiles.Count -eq 0) { throw "Get-ProjectDartFiles found no tracked .dart files." }
                Invoke-BuildExternal -Context $context -File "dart" -Parameters (@("format", "--output=none", "--set-exit-if-changed") + $dartFiles)
            } finally {
                Pop-Location
            }
        }

        # Same set as run_cmake_format_check; upstream Get-ProjectCmakeFiles would reach generated files.
        Invoke-BuildStep -Context $context -StepName "CMake Format Verification" -Script {
            Push-Location $workspace
            try {
                $cmakeFiles = @(& git -C $workspace ls-files -- 'CMakeLists.txt' '**/CMakeLists.txt' '*.cmake' '**/*.cmake' |
                    Where-Object {
                        $_ -notmatch '^(third_party|build)/' -and
                        $_ -notmatch '(^|/)(ephemeral|\.cxx|\.plugin_symlinks)/' -and
                        $_ -notmatch '(^|/)flutter/CMakeLists\.txt$' -and
                        $_ -notmatch '(^|/)generated_plugins\.cmake$' -and
                        $_ -notmatch '^rust_builder/cargokit/'
                    } | Sort-Object -Unique)
                if ($LASTEXITCODE -ne 0) { throw "git ls-files failed while listing CMake files." }
                if ($cmakeFiles.Count -eq 0) { throw "The CMake format gate matched no files; the exclusion regexes are over-broad." }

                $formatConfig = Join-Path $workspace '.cmake-format.yaml'
                if (-not (Test-Path -LiteralPath $formatConfig -PathType Leaf)) {
                    throw ".cmake-format.yaml is missing at the repo root; without it cmake-format silently uses built-in defaults. Restore the consumer copy with ANTfrastructure shared/config/Sync-SharedConfig.ps1 -Write (AGENTS.md paragraph 5)."
                }

                # Not Initialize-UvVenvPython: without a root requirements.txt it returns an empty venv.
                if (-not (Get-Command 'uv' -ErrorAction SilentlyContinue)) {
                    throw 'uv not found on PATH. Install Astral uv before running formatting steps.'
                }

                $cmakeFormatRequirements = Join-Path $workspace 'third_party/ANTfrastructure/linux/scripts/cmake-format.requirements.txt'
                if (-not (Test-Path -LiteralPath $cmakeFormatRequirements -PathType Leaf)) {
                    throw "cmake-format bootstrap pins not found: $cmakeFormatRequirements. If the whole directory is missing the submodule is not checked out: git submodule update --init --recursive third_party/ANTfrastructure."
                }

                $uvLogInfo = { param([string]$Message) Write-BuildLog -Context $context -Message $Message }
                $uvLogWarning = { param([string]$Message) Write-BuildLogWarning -Context $context -Message $Message }
                $uvRunner = { param([string]$File, [string[]]$Parameters) Invoke-BuildExternal -Context $context -File $File -Parameters $Parameters | Out-Null }

                $venvPython = Initialize-UvVenv -Workspace $workspace -EnvName '.venv' `
                    -CommandRunner $uvRunner -LogInfo $uvLogInfo -LogWarning $uvLogWarning
                Install-UvRequirements -VenvPython $venvPython -RequirementsPath $cmakeFormatRequirements `
                    -CommandRunner $uvRunner -LogInfo $uvLogInfo

                $cmakeFormatExe = Join-Path (Split-Path $venvPython -Parent) 'cmake-format.exe'
                if (-not (Test-Path -LiteralPath $cmakeFormatExe -PathType Leaf)) {
                    throw "cmake-format not found in venv: $cmakeFormatExe (expected from $cmakeFormatRequirements)."
                }
                Invoke-BuildExternal -Context $context -File $cmakeFormatExe -Parameters (@('-c', $formatConfig, '--check') + $cmakeFiles)
            } finally {
                Pop-Location
            }
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping Dart and CMake format verification (SkipFormat set)."
    }

    if (-not $SkipTests) {
        Invoke-BuildStep -Context $context -StepName "Dart Analysis" -Script {
            Push-Location $workspace
            try {
                Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("analyze")
            } finally {
                Pop-Location
            }
        }

        Invoke-BuildStep -Context $context -StepName "Flutter Tests" -Script {
            Push-Location $workspace
            try {
                Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("test")
            } finally {
                Pop-Location
            }
        }

        # Its own package with its own lock: the root's `flutter test` never reaches these.
        Invoke-BuildStep -Context $context -StepName "Plugin Flutter Tests" -Script {
            Push-Location (Join-Path $workspace 'packages\kataglyphis_native_inference')
            try {
                Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("pub", "get")
                Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("test")
            } finally {
                Pop-Location
            }
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping Dart analysis/tests (SkipTests set)."
    }

    if (-not $SkipDocs) {
        Invoke-BuildStep -Context $context -StepName "Generate API Docs" -Script {
            Invoke-FlutterApiDocs -WorkspacePath $workspace -OutputPath 'doc/api'
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping API docs generation (SkipDocs set)."
    }


    if (-not $SkipBootstrapFlutterBuild) {

        if ($CleanBuild) {
            Invoke-BuildStep -Context $context -StepName "Clean Build Directory" -Script {
                $removed = Remove-BuildRoot -Context $context -Path $buildRoot
                $removedOriginal = Remove-BuildRoot -Context $context -Path $originalBuildRoot
                if (-not $removed -and -not $ContinueOnError) {
                    throw "Failed to remove build root: $buildRoot"
                }
            }
        } else {
            Write-BuildLog -Context $context -Message "Skipping Clean Build Directory (CleanBuild not set)."
        }

        Clear-FlutterPluginSymlink -Context $context -WorkspaceDir $workspace

        Invoke-BuildStep -Context $context -StepName "Flutter Pub Get" -Script {
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("pub", "get") -IgnoreExitCode
        }

        Invoke-BuildStep -Context $context -StepName "Flutter Ephemeral Build (C++ Headers)" -Script {
            $env:CC = "clang-cl"
            $env:CXX = "clang-cl"
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("build", "windows", "--config-only")
        }

        Invoke-BuildStep -Context $context -StepName "Fix Plugin Symlinks (Junctions)" -Script {
            Repair-FlutterPluginSymlink -Context $context -WorkspaceDir $workspace
        }

        Invoke-BuildStep -Context $context -StepName "Reset CMake Build Directory" -Script {
            # Not Remove-Item: wcifs refuses deletes at random, and this degrades to an in-place configure.
            Remove-BuildRootSafe -Context $context -Path $cmakeBuildDir -Label "CMake build directory"
            New-Item -ItemType Directory -Force -Path $cmakeBuildDir | Out-Null
        }
    }

    Update-PermissionHandlerWindows -Context $context -WorkspaceDir $workspace

    if (Get-Command "sccache" -ErrorAction SilentlyContinue) {
        Write-BuildLog -Context $context -Message "sccache found. Enabling for Rust."
        $env:RUSTC_WRAPPER = "sccache"
    }

    foreach ($currentPreset in $presetsToRun) {
        $stepSuffix = if ($currentPreset) { " ($currentPreset)" } else { "" }
        $currentCMakeBuildDir = if ($currentPreset) { "${cmakeBuildDir}_${currentPreset}" } else { $cmakeBuildDir }

        $layout = Resolve-KataglyphisWindowsLayout -BuildRootFull $buildRoot -WindowsBuildConfig $windowsBuildConfig -Configuration $currentPreset
        $currentBuildDirFull = $layout.RunnerDir
        $currentDllDestPath = $layout.RustPluginDllPath
        $currentInstalledPluginsDir = Resolve-NormalizedPath -Path (Join-Path $currentBuildDirFull "plugins")
        $currentNativeAssetsDir = Resolve-NormalizedPath -Path (Join-Path $buildRoot "native_assets/windows")

        $isReleasePreset = $true
        if ($currentPreset) {
            if ($currentPreset -match "Debug") {
                $isReleasePreset = $false
            }
        } elseif ($CMakeBuildType -match "Debug") {
            $isReleasePreset = $false
        }

        Invoke-BuildStep -Context $context -StepName "CMake Configure$stepSuffix" -Critical -Script {
            if (-not (Test-Path $currentCMakeBuildDir)) {
                New-Item -ItemType Directory -Force -Path $currentCMakeBuildDir | Out-Null
            }

            if ($currentPreset) {
                $sourcePreset = Join-Path $workspace "third_party\AccelerANTgine\CMakePresets.json"
                $destPreset = Join-Path $windowsSrc "CMakePresets.json"
                if ((Test-Path $sourcePreset) -and -not (Test-Path $destPreset)) {
                    Write-BuildLog -Context $context -Message "Copying CMakePresets.json to windows directory..."
                    Copy-Item -Path $sourcePreset -Destination $destPreset -Force
                }

                $cmakeArgs = @(
                    "-S", $windowsSrc,
                    "--preset", $currentPreset,
                    "-B", $currentCMakeBuildDir,
                    "-DCMAKE_INSTALL_PREFIX=$currentBuildDirFull",
                    "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL"
                )
            } else {
                $cmakeArgs = @(
                    $windowsSrc,
                    "-B", $currentCMakeBuildDir,
                    "-G", $CMakeGenerator,
                    "-DCMAKE_BUILD_TYPE=$CMakeBuildType",
                    "-DCMAKE_INSTALL_PREFIX=$currentBuildDirFull",
                    "-DFLUTTER_TARGET_PLATFORM=windows-x64",
                    "-DCMAKE_CXX_COMPILER=clang-cl",
                    "-DCMAKE_C_COMPILER=clang-cl",
                    "-DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc",
                    "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL"
                )
            }
            # Only declares the plugin's gtest target (EXCLUDE_FROM_ALL); Build Native Plugin Tests builds it by name.
            $cmakeArgs += "-Dinclude_kataglyphis_native_inference_tests=ON"
            if (Get-Command "sccache" -ErrorAction SilentlyContinue) {
                $cmakeArgs += "-DCMAKE_C_COMPILER_LAUNCHER=sccache"
                $cmakeArgs += "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache"
            }

            if (-not $isReleasePreset) {
                # Flutter needs /MD, but clang-cl's STL under _DEBUG wants /MDd (_CrtDbgReport missing).
                $cmakeArgs += "-DCMAKE_CXX_FLAGS_DEBUG=/MD /Zi /Ob0 /Od /RTC1 /U_DEBUG /DNDEBUG /D_ITERATOR_DEBUG_LEVEL=0"
                $cmakeArgs += "-DCMAKE_C_FLAGS_DEBUG=/MD /Zi /Ob0 /Od /RTC1 /U_DEBUG /DNDEBUG /D_ITERATOR_DEBUG_LEVEL=0"
            }

            Write-BuildLog -Context $context -Message "Enabling CMake Configuration Profiling and Clang -ftime-trace..."
            $cmakeArgs += "--profiling-output=$currentCMakeBuildDir\cmake_configure_profile.json"
            $cmakeArgs += "--profiling-format=google-trace"
            $cmakeArgs += "-DKATAGLYPHIS_ENABLE_TIME_TRACE=ON"

            Invoke-BuildExternal -Context $context -File "cmake" -Parameters $cmakeArgs
        }

        # Cargokit builds the Rust crate once, inside the CMake build; its DLL is taken from the installed bundle.

        Invoke-BuildStep -Context $context -StepName "Native Assets Directory Fix$stepSuffix" -Script {
            if (Test-Path $currentNativeAssetsDir) {
                $item = Get-Item -LiteralPath $currentNativeAssetsDir -Force
                if (-not $item.PSIsContainer) {
                    Write-BuildLog -Context $context -Message "Path exists but is NOT a directory. Replacing: $currentNativeAssetsDir"
                    Remove-Item -LiteralPath $currentNativeAssetsDir -Force
                    New-Item -ItemType Directory -Path $currentNativeAssetsDir | Out-Null
                } else {
                    Write-BuildLog -Context $context -Message "Path is already a directory: $currentNativeAssetsDir"
                }
            } else {
                Write-BuildLog -Context $context -Message "Creating directory: $currentNativeAssetsDir"
                New-Item -ItemType Directory -Path $currentNativeAssetsDir | Out-Null
            }
        }

        $cmakeBuildArgs = @(
            "--build", $currentCMakeBuildDir,
            "--target", "install",
            "--parallel", ([Environment]::ProcessorCount).ToString(),
            "--verbose",
            # Ninja debug flags: track down overhead and why targets are rebuilding.
            "--", "-d", "explain", "-d", "stats"
        )

        Invoke-BuildStep -Context $context -StepName "CMake Build & Install$stepSuffix" -Critical -Script {
            Invoke-BuildExternal -Context $context -File "cmake" -Parameters $cmakeBuildArgs
        }

        # assemble can call a stale AOT snapshot up to date (WindowsFlutterAot.Common): rebuild once, then fail.
        Invoke-BuildStep -Context $context -StepName "Flutter AOT Freshness$stepSuffix" -Critical -Script {
            $aot = @{
                DartToolDir = Join-Path $workspace '.dart_tool'
                AotLibrary  = Join-Path $workspace 'build\windows\app.so'
            }
            $runnerData = Join-Path $currentBuildDirFull 'data'
            $stale = @(Get-FlutterAotStaleness @aot -RunnerDataDir $runnerData)
            if ($stale.Count -eq 0) {
                Write-BuildLog -Context $context -Message "AOT snapshot in $runnerData is fresh (or this is a JIT build)."
                return
            }
            $stale | ForEach-Object { Write-BuildLogWarning -Context $context -Message "Stale AOT: $_" }
            $removed = @(Reset-FlutterAotOutput @aot)
            Write-BuildLog -Context $context -Message "Removed $($removed.Count) AOT output(s)/stamp(s); rebuilding: $($removed -join ', ')"
            Invoke-BuildExternal -Context $context -File "cmake" -Parameters $cmakeBuildArgs
            $still = @(Get-FlutterAotStaleness @aot -RunnerDataDir $runnerData)
            if ($still.Count -gt 0) {
                throw "The AOT snapshot is still stale after a forced rebuild: $($still -join '; '). Rerun with -FreshContainer."
            }
            Write-BuildLog -Context $context -Message "AOT snapshot rebuilt from the current kernel."
        }

        Invoke-BuildStep -Context $context -StepName "Copy Rust DLL$stepSuffix" -Script {
            # Mirrored into the plugins layout Start-Windows.ps1 expects.
            $bundleDll = Join-Path $currentBuildDirFull $RustDllName
            if (-not (Test-Path $bundleDll)) {
                throw "Rust DLL not found in installed bundle: $bundleDll"
            }

            $currentDllDestDir = [System.IO.Path]::GetDirectoryName($currentDllDestPath)
            New-Item -ItemType Directory -Force -Path $currentDllDestDir | Out-Null
            Copy-Item -Path $bundleDll -Destination $currentDllDestPath -Force
            Write-BuildLog -Context $context -Message "Rust DLL copied from bundle to $currentDllDestPath"
        }

        Invoke-BuildStep -Context $context -StepName "Bundle Media Runtime DLLs$stepSuffix" -Script {
            # Plugins go to gstreamer-1.0\, the Rust side's GST_PLUGIN_PATH; ONNX Runtime is the next step's.
            if ($env:KATAGLYPHIS_RUST_FEATURES -notmatch "gstreamer") {
                Write-BuildLog -Context $context -Message "Rust media features disabled; skipping DLL bundling."
                return
            }

            $gstBin = if ($env:GSTREAMER_BIN) { $env:GSTREAMER_BIN } else { "C:\runtime\bin" }
            $gstPlugins = Join-Path (Split-Path $gstBin -Parent) "lib\gstreamer-1.0"
            if (Test-Path $gstBin) {
                # No ORT-family DLL (only the next step may stage one), nor gstopencv: nothing imports it, and its OpenCV is not shipped.
                Copy-Item -Path (Join-Path $gstBin "*.dll") -Exclude @('onnxruntime*.dll', 'DirectML.dll', 'gstopencv-*.dll') -Destination $currentBuildDirFull -Force
                Write-BuildLog -Context $context -Message "GStreamer core DLLs bundled from $gstBin"
            } else {
                Write-BuildLog -Context $context -Message "WARNING: GStreamer bin not found ($gstBin); skipping core DLL bundling."
            }
            if (Test-Path $gstPlugins) {
                $pluginDest = Join-Path $currentBuildDirFull "gstreamer-1.0"
                New-Item -ItemType Directory -Force -Path $pluginDest | Out-Null
                # The capture pipeline's plugins plus the device providers for enumeration.
                $wanted = @(
                    "gstcoreelements.dll", "gstapp.dll", "gsttypefindfunctions.dll",
                    "gstvideoconvertscale.dll", "gstvideofilter.dll", "gstvideorate.dll",
                    "gstvideotestsrc.dll", "gstautodetect.dll", "gstwinks.dll",
                    "gstmediafoundation.dll"
                )
                foreach ($dll in $wanted) {
                    $src = Join-Path $gstPlugins $dll
                    if (Test-Path $src) {
                        Copy-Item -Path $src -Destination $pluginDest -Force
                    }
                }
                Write-BuildLog -Context $context -Message "GStreamer plugins bundled to $pluginDest"
            } else {
                Write-BuildLog -Context $context -Message "WARNING: GStreamer plugin dir not found ($gstPlugins)."
            }
        }

        # Unconditional and last: AccelerANTgine.dll imports onnxruntime.dll whatever the features; G6 then proves it.
        Invoke-BuildStep -Context $context -StepName "Stage Chain ONNX Runtime$stepSuffix" -Critical -Script {
            $null = Copy-ChainOrtBeside -OnnxRoot "$env:ONNX_ROOT" -Destination $currentBuildDirFull
            $proof = Invoke-RunnerOrtProof -RunnerDir $currentBuildDirFull
            Write-BuildLog -Context $context -Message "Chain ONNX Runtime staged from $env:ONNX_ROOT\bin and proved by G6: $(@($proof.Stamp.sha256.Keys) -join ', ')"
        }

        if (-not $SkipTests) {
            # Built here, run on the host by windows-x64.yml: flutter_windows.dll does not load in Server Core.
            Invoke-BuildStep -Context $context -StepName "Build Native Plugin Tests (gtest)$stepSuffix" -Script {
                & (Join-Path $PSScriptRoot 'Invoke-PluginGTest.ps1') -BuildDir $currentCMakeBuildDir -Build -NoRun *>&1 |
                    ForEach-Object { Write-BuildLog -Context $context -Message "$_" }
            }
        }
    }

    Invoke-BuildStep -Context $context -StepName "MSIX Compatibility Layout" -Script {
        # msix wants runner\Release itself, not runner\<preset>\; with several presets the first built wins.
        $msixReleaseDir = Resolve-NormalizedPath -Path (Join-Path $buildRoot "windows/x64/runner/Release")
        $hostReleaseDir = Resolve-NormalizedPath -Path (Join-Path $originalBuildRoot "windows/x64/runner/Release")
        foreach ($currentPreset in $presetsToRun) {
            # CI names no preset; fall back to the default — see AGENTS.md § 5.
            $currentPreset = if ([string]::IsNullOrEmpty($currentPreset)) {
                $windowsBuildConfig.CMakeConfiguration
            } else {
                $currentPreset
            }

            $msixSourceDir = Resolve-NormalizedPath -Path (Join-Path $buildRoot "windows/x64/runner/$currentPreset")
            if ($msixSourceDir -eq $msixReleaseDir -or -not (Test-Path -LiteralPath $msixSourceDir -PathType Container)) { continue }

            # Rebuilt every run, host copy too (the host sync only adds): a kept copy holds an unproved ORT.
            Write-BuildLog -Context $context -Message "Preparing MSIX compatibility for $currentPreset..."
            foreach ($staleDir in @($msixReleaseDir, $hostReleaseDir)) {
                if (Test-Path -LiteralPath $staleDir) { Remove-Item -LiteralPath $staleDir -Recurse -Force }
            }
            New-Item -ItemType Directory -Force -Path $msixReleaseDir | Out-Null

            Get-ChildItem -LiteralPath $msixSourceDir -Force |
                Where-Object { $_.Name -ne "Release" } |
                ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination $msixReleaseDir -Recurse -Force
                }

            Write-BuildLog -Context $context -Message "MSIX compatibility folder prepared: $msixReleaseDir"
            break
        }
    }

    Invoke-BuildStep -Context $context -StepName "Plugin Build Summary" -Script {
        $allPluginDirs = @($installedPluginsDir)
        foreach ($currentPreset in $presetsToRun) {
            if (-not [string]::IsNullOrEmpty($currentPreset)) {
                $presetLayout = Resolve-KataglyphisWindowsLayout -BuildRootFull $buildRoot -WindowsBuildConfig $windowsBuildConfig -Configuration $currentPreset
                $allPluginDirs += Resolve-NormalizedPath -Path (Join-Path $presetLayout.RunnerDir "plugins")
            }
        }
        Assert-FlutterPluginsBuilt -Context $context -CMakeFile $generatedPluginsCMake -SearchDirectories $allPluginDirs
    }

    Show-SccacheStats -Context $context
    # Again on stderr: BuildKit clips a step's stdout at 2 MiB, which would drop the hit rate from CI logs.
    Write-SccacheStatsToStderr

    Invoke-BuildStep -Context $context -StepName "Sync Artifacts to Host Workspace" -Script {
        $hostRustTarget = Join-Path $rustDir "target"
        Sync-FastLocalArtifactsToHost -Context $context -BuildRoot $buildRoot -OriginalBuildRoot $originalBuildRoot -CargoTargetDir $env:CARGO_TARGET_DIR -HostRustTargetDir $hostRustTarget
    }

    if (-not $SkipMsixPackaging) {
        Invoke-BuildStep -Context $context -StepName "MSIX Packaging" -Script {
            # msix packs build\windows\x64\runner\Release: G6 proves that directory, as packed, first.
            $null = Invoke-RunnerOrtProof -RunnerDir (Resolve-NormalizedPath -Path (Join-Path $workspace "build/windows/x64/runner/Release"))
            Clear-FlutterPluginSymlink -Context $context -WorkspaceDir $workspace
            Push-Location $workspace
            try {
                Invoke-BuildExternal -Context $context -File "dart" -Parameters @("run", "msix:create", "--install-certificate", "false")
            } finally {
                Pop-Location
            }
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping MSIX packaging (SkipMsixPackaging set)."
    }

    Invoke-BuildStep -Context $context -StepName "Delivery Check" -Script {
        # A green build is not delivery: each preset's runner exe must exist in both trees (AGENTS.md § 5).
        $missingArtifacts = @()
        foreach ($currentPreset in $presetsToRun) {
            $effectivePreset = if ([string]::IsNullOrEmpty($currentPreset)) {
                $windowsBuildConfig.CMakeConfiguration
            } else {
                $currentPreset
            }
            foreach ($deliveryRoot in @($buildRoot, $originalBuildRoot)) {
                $presetLayout = Resolve-KataglyphisWindowsLayout -BuildRootFull $deliveryRoot -WindowsBuildConfig $windowsBuildConfig -Configuration $effectivePreset
                $exePath = Join-Path $presetLayout.RunnerDir $windowsBuildConfig.RunnerExeName
                if (Test-Path -LiteralPath $exePath) {
                    Write-BuildLog -Context $context -Message "Delivered: $exePath"
                } else {
                    $missingArtifacts += $exePath
                }
            }
        }
        if ($missingArtifacts.Count -gt 0) {
            throw "Build reported success but the runner exe is missing: $($missingArtifacts -join ', ')"
        }
    }

    Write-BuildLog -Context $context -Message ""
    Write-BuildLogSuccess -Context $context -Message "=== Build Complete ==="
    Write-BuildLog -Context $context -Message "Build artifacts located at: $(Join-Path $workspace $env:BUILD_DIR_RELEASE)"
} catch {
    $hadUnhandledError = $true
    Write-BuildLogError -Context $context -Message "Unhandled critical error: $($_.Exception.Message)"
    if ($_.ScriptStackTrace) {
        Write-BuildLogError -Context $context -Message "Stack trace: $($_.ScriptStackTrace)"
    }
} finally {
    Write-BuildSummary -Context $context

    try {
        $logDirPath = if ([System.IO.Path]::IsPathRooted($LogDir)) {
            $LogDir
        } else {
            Join-Path $workspace $LogDir
        }

        New-Item -ItemType Directory -Force -Path $logDirPath | Out-Null

        $summaryFileName = [System.IO.Path]::GetFileName($context.SummaryPath)
        $summaryPathInLogDir = Join-Path $logDirPath $summaryFileName

        $sourceSummaryPath = [System.IO.Path]::GetFullPath($context.SummaryPath)
        $targetSummaryPath = [System.IO.Path]::GetFullPath($summaryPathInLogDir)

        if ($sourceSummaryPath -ne $targetSummaryPath) {
            Copy-Item -Path $sourceSummaryPath -Destination $targetSummaryPath -Force
            Write-BuildLog -Context $context -Message "Additional JSON summary copy available at: $targetSummaryPath"
        } else {
            Write-BuildLog -Context $context -Message "JSON summary already saved under LogDir: $targetSummaryPath"
        }
        
        $flutterLogs = Get-ChildItem -LiteralPath $workspace -Filter "flutter_*.log" -ErrorAction SilentlyContinue
        if ($flutterLogs) {
            Write-BuildLog -Context $context -Message "Moving flutter crash logs to $logDirPath"
            $flutterLogs | Move-Item -Destination $logDirPath -Force
        }

        # The hub's retention policy; last, so this build's own log is among those kept.
        Limit-DiagnosticLogs -Directory $logDirPath -Keep 60
    } catch {
        Write-BuildLogWarning -Context $context -Message "Failed to copy JSON summary to LogDir: $($_.Exception.Message)"
    }

    Close-BuildLog -Context $context

    if ($hadUnhandledError -or $context.Results.Failed.Count -gt 0) {
        exit 1
    }
}
