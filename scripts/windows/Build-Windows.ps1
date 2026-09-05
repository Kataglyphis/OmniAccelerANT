#requires -Version 7.0

# Every ContainerHub build module declares `#requires -Version 7.0`, so this
# script must be launched with `pwsh`, never Windows PowerShell 5.1's
# `powershell` — otherwise the failure surfaces as an opaque Import-Module
# error deep in the preamble instead of here.

[CmdletBinding()]
param(
    [string] $WorkspaceDir = $PWD.Path,
    [string] $BuildRootDir = "",
    [string] $RustCrateDir = "ExternalLib\Kataglyphis-RustProjectTemplate",
    [string] $RustDllName = "kataglyphis_rustprojecttemplate.dll",
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

# One bootstrap, one import list. Resolve-BuildModule looks every name up in
# ExternalLib/Kataglyphis-ContainerHub first and only then in
# scripts/windows/modules/, so a module that moves upstream is picked up here
# without touching this script.
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')

# Dependency order matters (see Import-BuildModule): Shared, then Build, then
# everything that builds on them.
Import-BuildModule @(
    'WindowsScripts.Shared'     # Resolve-WorkspacePath/-NormalizedPath, sccache + log-retention helpers
    'WindowsBuild.Common'       # build context/log/step primitives, cache env, plugin assertions
    'WindowsToolchain.Common'   # Invoke-ToolchainChecks
    'WindowsFlutter.Common'     # plugin symlink + permission_handler patches, host artifact sync
    'WindowsCMake.Common'       # Remove-BuildRootSafe
    'WindowsGstPlugins.Common'  # Assert-PkgConfigModule
    'WindowsFormatting.Common'  # Get-ProjectDartFiles
    'WindowsPaths.Common'       # project-local: this repo's Flutter windows/x64 layout
)

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

# Persistent caching configurations for Docker volume mount
# To avoid massive I/O penalties and SQLite locking issues in Docker bind mounts,
# we place all cache directories in the container's fast local storage.
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
        Invoke-BuildCodeQL -Context $context -Workspace $workspace -ForwardParameters $codeQLForwardParameters -BuildScriptPath $MyInvocation.MyCommand.Path
        exit 0
    }

    Invoke-BuildStep -Context $context -StepName "Environment Check" -Script {
        Invoke-ToolchainChecks -Context $context -RequiredTools $RequiredTools -FailOnMissingRequiredTools:$FailOnMissingRequiredTools
    }

    Invoke-BuildStep -Context $context -StepName "Media Runtime Preflight" -Script {
        # Windows-only Rust features (webcam capture via GStreamer + runtime-
        # loaded ONNX Runtime). rust_builder/windows/CMakeLists.txt reads this
        # at configure time and forwards it to cargo via Cargokit. Set the env
        # var to "" explicitly to build feature-less.
        if ($null -eq (Get-Item -Path "Env:KATAGLYPHIS_RUST_FEATURES" -ErrorAction SilentlyContinue)) {
            $env:KATAGLYPHIS_RUST_FEATURES = "gstreamer,onnxruntime_dynamic,onnxruntime_directml"
        }
        Write-BuildLog -Context $context -Message "Rust features: '$($env:KATAGLYPHIS_RUST_FEATURES)'"

        if ($env:KATAGLYPHIS_RUST_FEATURES -match "gstreamer") {
            # gstreamer-sys and friends resolve the GStreamer dev files through
            # pkg-config at cargo build time — fail fast here instead of deep
            # inside Ninja. ContainerHub's gate checks ALL THREE modules the
            # crate binds (gstreamer / gstreamer-app / gstreamer-video, see
            # crates/media/Cargo.toml), reports the resolved versions and prints
            # PKG_CONFIG_PATH on failure; the old probe only tried
            # gstreamer-1.0, so a missing gstreamer-app-1.0 .pc got through and
            # surfaced minutes later as a cargo build error.
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

    # The three quality gates AGENTS.md documents, driven straight through
    # ContainerHub's Invoke-BuildExternal (which logs the command line and fails
    # the step on a non-zero exit).
    #
    # These used to call Invoke-DartFormatVerification / Invoke-DartAnalysis /
    # Invoke-FlutterTests, which exist in NO module on either side — every build
    # since recorded all three steps as "The term ... is not recognized"
    # (logs/build-summary-*.json), so format, analyze and test have not actually
    # gated anything. They are Flutter-specific, so they belong here rather than
    # upstream in ContainerHub.
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
    } else {
        Write-BuildLog -Context $context -Message "Skipping Dart format verification (SkipFormat set)."
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
            try { Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("build", "windows", "--config-only") -IgnoreExitCode } catch { Write-BuildLog -Context $context -Message "Flutter config failed as expected, continuing to patch..." }
        }

        Invoke-BuildStep -Context $context -StepName "Fix Plugin Symlinks (Junctions)" -Script {
            Repair-FlutterPluginSymlink -Context $context -WorkspaceDir $workspace
        }

        Invoke-BuildStep -Context $context -StepName "Reset CMake Build Directory" -Script {
            # Remove-BuildRootSafe (WindowsCMake.Common) instead of a bare
            # Remove-Item: inside a Windows container the wcifs filter
            # intermittently refuses a delete, and upstream's helper degrades to
            # an in-place configure with a warning rather than aborting a build
            # that would have succeeded.
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
                $sourcePreset = Join-Path $workspace "ExternalLib\Kataglyphis_NativeInferencePlugin\native\KataglyphisCppInference\CMakePresets.json"
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
            if (Get-Command "sccache" -ErrorAction SilentlyContinue) {
                $cmakeArgs += "-DCMAKE_C_COMPILER_LAUNCHER=sccache"
                $cmakeArgs += "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache"
            }

            if (-not $isReleasePreset) {
                # Fix CRT Linker Errors (_CrtDbgReport missing) when building Flutter plugins in Debug with clang-cl
                # Flutter requires MultiThreadedDLL (/MD) but clang-cl + STL + _DEBUG expects Debug CRT (/MDd).
                $cmakeArgs += "-DCMAKE_CXX_FLAGS_DEBUG=/MD /Zi /Ob0 /Od /RTC1 /U_DEBUG /DNDEBUG /D_ITERATOR_DEBUG_LEVEL=0"
                $cmakeArgs += "-DCMAKE_C_FLAGS_DEBUG=/MD /Zi /Ob0 /Od /RTC1 /U_DEBUG /DNDEBUG /D_ITERATOR_DEBUG_LEVEL=0"
            }

            # --- ADDED CMAKE PROFILING LOGGING ---
            Write-BuildLog -Context $context -Message "Enabling CMake Configuration Profiling and Clang -ftime-trace..."
            $cmakeArgs += "--profiling-output=$currentCMakeBuildDir\cmake_configure_profile.json"
            $cmakeArgs += "--profiling-format=google-trace"
            $cmakeArgs += "-DKATAGLYPHIS_ENABLE_TIME_TRACE=ON"
            # -------------------------------------

            Invoke-BuildExternal -Context $context -File "cmake" -Parameters $cmakeArgs
        }

        # NOTE: the Rust crate is built exactly once — by Cargokit inside the
        # CMake build below (rust_builder plugin). The former standalone
        # "Rust Crate Build" cargo step duplicated that work; the DLL is now
        # harvested from the installed runner bundle after the CMake step.

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

        Invoke-BuildStep -Context $context -StepName "CMake Build & Install$stepSuffix" -Critical -Script {
            $processorCount = [Environment]::ProcessorCount
            
            $cmakeBuildArgs = @(
                "--build", $currentCMakeBuildDir,
                "--target", "install",
                "--parallel", $processorCount.ToString(),
                "--verbose"
            )
            
            # --- ADDED NINJA BUILD LOGGING ---
            # Append Ninja debug flags to track down overhead and why targets are rebuilding
            $cmakeBuildArgs += "--"
            $cmakeBuildArgs += "-d"
            $cmakeBuildArgs += "explain"
            $cmakeBuildArgs += "-d"
            $cmakeBuildArgs += "stats"
            # ---------------------------------
            
            Invoke-BuildExternal -Context $context -File "cmake" -Parameters $cmakeBuildArgs
        }

        Invoke-BuildStep -Context $context -StepName "Copy Rust DLL$stepSuffix" -Script {
            # Cargokit installed the crate's DLL into the runner bundle; mirror it
            # into the plugins layout that Start-Windows.ps1 expects.
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
            # Stage the runtime DLL closure for the Rust webcam/inference path
            # next to the runner exe so the packaged app runs outside the
            # container: ONNX Runtime (+DirectML) and GStreamer core DLLs into
            # the bundle root, GStreamer plugins into exe-relative
            # gstreamer-1.0\ (the Rust side sets GST_PLUGIN_PATH to that dir).
            if ($env:KATAGLYPHIS_RUST_FEATURES -notmatch "gstreamer") {
                Write-BuildLog -Context $context -Message "Rust media features disabled; skipping DLL bundling."
                return
            }

            $ortBin = if ($env:ONNX_ROOT) { Join-Path $env:ONNX_ROOT "bin" } else { "C:\runtime\lib\onnxruntime-source\bin" }
            if (Test-Path $ortBin) {
                foreach ($dll in @("onnxruntime.dll", "DirectML.dll", "onnxruntime_providers_shared.dll")) {
                    $src = Join-Path $ortBin $dll
                    if (Test-Path $src) {
                        Copy-Item -Path $src -Destination $currentBuildDirFull -Force
                    }
                }
                Write-BuildLog -Context $context -Message "ONNX Runtime DLLs bundled from $ortBin"
            } else {
                Write-BuildLog -Context $context -Message "WARNING: ONNX Runtime bin not found ($ortBin); app will rely on ORT_DYLIB_PATH at runtime."
            }

            $gstBin = if ($env:GSTREAMER_BIN) { $env:GSTREAMER_BIN } else { "C:\runtime\bin" }
            $gstPlugins = Join-Path (Split-Path $gstBin -Parent) "lib\gstreamer-1.0"
            if (Test-Path $gstBin) {
                # Core + dependency DLLs (glib, gobject, gstreamer-1.0, ...).
                Copy-Item -Path (Join-Path $gstBin "*.dll") -Destination $currentBuildDirFull -Force
                Write-BuildLog -Context $context -Message "GStreamer core DLLs bundled from $gstBin"
            } else {
                Write-BuildLog -Context $context -Message "WARNING: GStreamer bin not found ($gstBin); skipping core DLL bundling."
            }
            if (Test-Path $gstPlugins) {
                $pluginDest = Join-Path $currentBuildDirFull "gstreamer-1.0"
                New-Item -ItemType Directory -Force -Path $pluginDest | Out-Null
                # Subset needed by the capture pipeline (webcam/test source,
                # convert/scale, appsink) plus device providers for enumeration.
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
    }

    Invoke-BuildStep -Context $context -StepName "MSIX Compatibility Layout" -Script {
        foreach ($currentPreset in $presetsToRun) {
            # CI names no preset; fall back to the default — see AGENTS.md § 4.
            $currentPreset = if ([string]::IsNullOrEmpty($currentPreset)) {
                $windowsBuildConfig.CMakeConfiguration
            } else {
                $currentPreset
            }

            $msixSourceDir = Resolve-NormalizedPath -Path (Join-Path $buildRoot "windows/x64/runner/$currentPreset")
            # msix looks for build\windows\x64\runner\Release — directly under
            # runner\, not under runner\<preset>\. Nesting it inside the preset
            # directory is why packaging reported "Build files not found at
            # ...\runner\Release". With several presets the first one built wins
            # here; msix packages a single configuration either way.
            $msixReleaseDir = Resolve-NormalizedPath -Path (Join-Path $buildRoot "windows/x64/runner/Release")

            if (Test-Path -LiteralPath $msixReleaseDir -PathType Container) {
                Write-BuildLog -Context $context -Message "MSIX compatibility for $currentPreset already at: $msixReleaseDir"
            } elseif (Test-Path -LiteralPath $msixSourceDir -PathType Container) {
                Write-BuildLog -Context $context -Message "Preparing MSIX compatibility for $currentPreset..."
                New-Item -ItemType Directory -Force -Path $msixReleaseDir | Out-Null

                Get-ChildItem -LiteralPath $msixSourceDir -Force |
                    Where-Object { $_.Name -ne "Release" } |
                    ForEach-Object {
                        Copy-Item -Path $_.FullName -Destination $msixReleaseDir -Recurse -Force
                    }

                Write-BuildLog -Context $context -Message "MSIX compatibility folder prepared: $msixReleaseDir"
            }
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
    # Same numbers again on STDERR: BuildKit clips a step's stdout at 2 MiB, and
    # this build produces far more than that, so the hit-rate would otherwise be
    # gone from exactly the CI logs where caching needs to be measured.
    Write-SccacheStatsToStderr

    Invoke-BuildStep -Context $context -StepName "Sync Artifacts to Host Workspace" -Script {
        $hostRustTarget = Join-Path $rustDir "target"
        Sync-FastLocalArtifactsToHost -Context $context -BuildRoot $buildRoot -OriginalBuildRoot $originalBuildRoot -CargoTargetDir $env:CARGO_TARGET_DIR -HostRustTargetDir $hostRustTarget
    }

    if (-not $SkipMsixPackaging) {
        Invoke-BuildStep -Context $context -StepName "MSIX Packaging" -Script {
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
        # A green build is not proof of delivery. Assert the runner exe that each
        # built preset was supposed to produce actually exists, so an empty or
        # silently-failed build cannot exit 0 (adopting-in-a-new-project.md § 2;
        # the RustProjectTemplate Build-Windows.ps1 keeps the same gate on its MSIX).
        # Asserts both the scratch and the host-synced tree — see AGENTS.md § 4.
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

        # Bounded log growth, ContainerHub's retention policy: keep plenty (the
        # incident is always in the newest ones) and only trim the tail. Runs
        # last so this build's own log is among the newest kept.
        Limit-DiagnosticLogs -Directory $logDirPath -Keep 60
    } catch {
        Write-BuildLogWarning -Context $context -Message "Failed to copy JSON summary to LogDir: $($_.Exception.Message)"
    }

    Close-BuildLog -Context $context

    if ($hadUnhandledError -or $context.Results.Failed.Count -gt 0) {
        exit 1
    }
}
