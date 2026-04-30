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

if (-not $PSBoundParameters.ContainsKey('RustDllName')) {
    $RustDllName = $windowsBuildConfig.RustDllName
}

if ([string]::IsNullOrWhiteSpace($BuildRootDir)) {
    if ($windowsBuildConfig.ContainsKey('BuildRootDir') -and -not [string]::IsNullOrWhiteSpace($windowsBuildConfig.BuildRootDir)) {
        $BuildRootDir = $windowsBuildConfig.BuildRootDir
    } else {
        throw "Build root directory is not configured. Set BuildRootDir in Windows.BuildConfig.ps1 or pass -BuildRootDir."
    }
}

$sharedModulePath = Join-Path $PSScriptRoot "..\..\ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules\WindowsBuild.Common.psm1"
$sharedModulePath = [System.IO.Path]::GetFullPath($sharedModulePath)
if (-not (Test-Path $sharedModulePath)) {
    throw "Required build module not found: $sharedModulePath"
}

Import-Module $sharedModulePath -Force

if ($CodeQL) {
    $codeQLModulePath = Join-Path $PSScriptRoot "..\..\ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules\WindowsCodeQL.Common.psm1"
    $codeQLModulePath = [System.IO.Path]::GetFullPath($codeQLModulePath)
    if (-not (Test-Path $codeQLModulePath)) {
        throw "Required CodeQL module not found: $codeQLModulePath"
    }

    Import-Module $codeQLModulePath -Force
}

$toolchainModulePath = Join-Path $PSScriptRoot "..\..\ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules\WindowsToolchain.Common.psm1"
$toolchainModulePath = [System.IO.Path]::GetFullPath($toolchainModulePath)
if (-not (Test-Path $toolchainModulePath)) {
    throw "Required toolchain module not found: $toolchainModulePath"
}

Import-Module $toolchainModulePath -Force

$sharedUtilitiesModulePath = Join-Path $PSScriptRoot "..\..\ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules\WindowsScripts.Shared.psm1"
$sharedUtilitiesModulePath = [System.IO.Path]::GetFullPath($sharedUtilitiesModulePath)
if (-not (Test-Path $sharedUtilitiesModulePath)) {
    throw "Required shared utilities module not found: $sharedUtilitiesModulePath"
}

Import-Module $sharedUtilitiesModulePath -Force

$flutterSharedModulePath = Join-Path $PSScriptRoot "..\..\ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules\WindowsFlutter.Common.psm1"
$flutterSharedModulePath = [System.IO.Path]::GetFullPath($flutterSharedModulePath)
if (-not (Test-Path $flutterSharedModulePath)) {
    throw "Required flutter shared module not found: $flutterSharedModulePath"
}

Import-Module $flutterSharedModulePath -Force

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
    throw "Build root directory is not configured. Set BuildRootDir in Windows.BuildConfig.ps1 or pass -BuildRootDir."
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

    if (-not $SkipFormat) {
        Invoke-BuildStep -Context $context -StepName "Dart Format Verification" -Script {
            Invoke-DartFormatVerification -Context $context -WorkspaceDir $workspace
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping Dart format verification (SkipFormat set)."
    }

    if (-not $SkipTests) {
        Invoke-BuildStep -Context $context -StepName "Dart Analysis" -Script {
            Invoke-DartAnalysis -Context $context
        }

        Invoke-BuildStep -Context $context -StepName "Flutter Tests" -Script {
            Invoke-FlutterTests -Context $context
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping Dart analysis/tests (SkipTests set)."
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

        Clean-FlutterPluginSymlinks -Context $context -WorkspaceDir $workspace

        Invoke-BuildStep -Context $context -StepName "Flutter Pub Get" -Script {
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("pub", "get") -IgnoreExitCode
        }

        Invoke-BuildStep -Context $context -StepName "Flutter Ephemeral Build (C++ Headers)" -Script {
            $env:CC = "clang-cl"
            $env:CXX = "clang-cl"
            try { Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("build", "windows", "--config-only") -IgnoreExitCode } catch { Write-BuildLog -Context $context -Message "Flutter config failed as expected, continuing to patch..." }
        }

        Invoke-BuildStep -Context $context -StepName "Fix Plugin Symlinks (Junctions)" -Script {
            Fix-FlutterPluginSymlinks -Context $context -WorkspaceDir $workspace
        }

        Invoke-BuildStep -Context $context -StepName "Reset CMake Build Directory" -Script {
            if (Test-Path $cmakeBuildDir) {
                Remove-Item -LiteralPath $cmakeBuildDir -Recurse -Force -ErrorAction Stop
            }
            New-Item -ItemType Directory -Force -Path $cmakeBuildDir | Out-Null
        }
    }

    Patch-PermissionHandlerWindows -Context $context -WorkspaceDir $workspace

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

        $cargoProfilePath = if ($isReleasePreset) { "release" } else { "debug" }
        $cargoTargetRoot = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $rustDir "target" }
        $currentDllSource = Resolve-NormalizedPath -Path (Join-Path $cargoTargetRoot "$cargoProfilePath/$RustDllName")

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

        Invoke-BuildStep -Context $context -StepName "Rust Crate Build$stepSuffix" -Script {
            if (-not (Test-Path $rustDir)) {
                throw "Rust crate directory not found: $rustDir"
            }

            Push-Location $rustDir
            try {
                $processorCount = [Environment]::ProcessorCount
                Invoke-BuildOptional -Context $context -Name "flutter_rust_bridge_codegen install" -Script {
                    $cargoBin = Join-Path $env:CARGO_HOME "bin"
                    if (-not (Test-Path (Join-Path $cargoBin "flutter_rust_bridge_codegen.exe"))) {
                        Write-BuildLog -Context $context -Message "Installing flutter_rust_bridge_codegen to $env:CARGO_HOME..."
                        Invoke-BuildExternal -Context $context -File "cargo" -Parameters @("install", "flutter_rust_bridge_codegen")
                    } else {
                        Write-BuildLog -Context $context -Message "flutter_rust_bridge_codegen is already installed at $cargoBin."
                    }
                }
                $cargoArgs = @("build", "--timings", "-j", $processorCount.ToString())
                if ($isReleasePreset) {
                    $cargoArgs += "--release"
                }
                Invoke-BuildExternal -Context $context -File "cargo" -Parameters $cargoArgs
            } finally {
                Pop-Location
            }
        }

        Invoke-BuildStep -Context $context -StepName "Copy Rust DLL$stepSuffix" -Script {
            if (-not (Test-Path $currentDllSource)) {
                throw "Rust DLL not found at $currentDllSource"
            }

            $currentDllDestDir = [System.IO.Path]::GetDirectoryName($currentDllDestPath)
            New-Item -ItemType Directory -Force -Path $currentDllDestDir | Out-Null
            Copy-Item -Path $currentDllSource -Destination $currentDllDestPath -Force
            Write-BuildLog -Context $context -Message "Rust DLL copied to $currentDllDestPath"
        }

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
    }

    Invoke-BuildStep -Context $context -StepName "MSIX Compatibility Layout" -Script {
        foreach ($currentPreset in $presetsToRun) {
            if ([string]::IsNullOrEmpty($currentPreset)) { continue }

            $msixSourceDir = Resolve-NormalizedPath -Path (Join-Path $buildRoot "windows/x64/runner/$currentPreset")
            $msixReleaseDir = Resolve-NormalizedPath -Path (Join-Path $msixSourceDir "Release")

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

    Invoke-BuildStep -Context $context -StepName "Sync Artifacts to Host Workspace" -Script {
        $hostRustTarget = Join-Path $rustDir "target"
        Sync-FastLocalArtifactsToHost -Context $context -BuildRoot $buildRoot -OriginalBuildRoot $originalBuildRoot -CargoTargetDir $env:CARGO_TARGET_DIR -HostRustTargetDir $hostRustTarget
    }

    if (-not $SkipMsixPackaging) {
        Invoke-BuildStep -Context $context -StepName "MSIX Packaging" -Script {
            $pluginSymlinksDir = Join-Path $workspace "windows\flutter\ephemeral\.plugin_symlinks"
            if (Test-Path $pluginSymlinksDir) {
                Remove-Item -LiteralPath $pluginSymlinksDir -Force -Recurse -ErrorAction SilentlyContinue
                & cmd.exe /c "rmdir /q /s `"$pluginSymlinksDir`" 2>nul"
            }
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
    } catch {
        Write-BuildLogWarning -Context $context -Message "Failed to copy JSON summary to LogDir: $($_.Exception.Message)"
    }

    Close-BuildLog -Context $context

    if ($hadUnhandledError -or $context.Results.Failed.Count -gt 0) {
        exit 1
    }
}
