[CmdletBinding()]
param(
    [string] $WorkspaceDir = $PWD.Path,
    [string] $BuildDirRelease = "build/windows/x64/runner",
    [string] $RustCrateDir = "ExternalLib\Kataglyphis-RustProjectTemplate",
    [string] $RustDllName = "kataglyphis_rustprojecttemplate.dll",
    [string] $CMakeGenerator = "Ninja",
    [string] $CMakeBuildType = "Release",
    [string] $LogDir = "logs",
    [switch] $SkipTests,
    [switch] $SkipBootstrapFlutterBuild,
    [switch] $ContinueOnError,
    [switch] $StopOnError,
    [switch] $CodeQL,
    [switch] $CleanCodeQLDb,
    [switch] $CodeQLDownload,
    [string[]] $RequiredTools = @('cmake', 'clang-cl', 'flutter', 'cargo', 'ninja'),
    [switch] $FailOnMissingRequiredTools
)

Set-StrictMode -Version Latest

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

$buildRoot = Resolve-NormalizedPath -BasePath $workspace -RelativePath "build"
$buildDirFull = Resolve-NormalizedPath -BasePath $workspace -RelativePath $BuildDirRelease
$windowsSrc = Resolve-NormalizedPath -BasePath $workspace -RelativePath "windows"
$cmakeBuildDir = Resolve-NormalizedPath -BasePath $workspace -RelativePath "build/windows/x64"
$rustDir = Resolve-NormalizedPath -BasePath $workspace -RelativePath $RustCrateDir
$dllSource = Resolve-NormalizedPath -BasePath $rustDir -RelativePath "target/release/$RustDllName"
$dllDestDir = Resolve-NormalizedPath -BasePath $workspace -RelativePath "build/windows/x64/plugins/$($RustDllName -replace '\\.dll$','')"
$nativeAssetsDir = Resolve-NormalizedPath -BasePath $workspace -RelativePath "build/native_assets/windows"

$env:BUILD_DIR_RELEASE = $BuildDirRelease

$hadUnhandledError = $false

try {
    Write-BuildLog -Context $context -Message "=== Kataglyphis Windows Build Script ==="
    Write-BuildLog -Context $context -Message "Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-BuildLog -Context $context -Message "Logging to: $($context.LogPath)"
    Write-BuildLog -Context $context -Message ""
    Write-BuildLog -Context $context -Message "=== Configuration ==="
    Write-BuildLog -Context $context -Message "Workspace:        $workspace"
    Write-BuildLog -Context $context -Message "BuildDirRelease:  $BuildDirRelease"
    Write-BuildLog -Context $context -Message "BuildDirFull:     $buildDirFull"
    Write-BuildLog -Context $context -Message "CMakeBuildDir:    $cmakeBuildDir"
    Write-BuildLog -Context $context -Message "CMakeGenerator:   $CMakeGenerator"
    Write-BuildLog -Context $context -Message "CMakeBuildType:   $CMakeBuildType"
    Write-BuildLog -Context $context -Message "RustDir:          $rustDir"
    Write-BuildLog -Context $context -Message "Rust DLL source:  $dllSource"
    Write-BuildLog -Context $context -Message "Rust DLL dest:    $dllDestDir"
    Write-BuildLog -Context $context -Message "SkipTests:        $SkipTests"
    Write-BuildLog -Context $context -Message "SkipFlutterBuild: $SkipBootstrapFlutterBuild"
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
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("pub", "get")
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("config", "--enable-windows-desktop")
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping Flutter dependency steps (SkipFlutterBuild set)."
    }

    if (-not $SkipTests) {
        Invoke-BuildStep -Context $context -StepName "Dart Format Verification" -Script {
            $dartDirs = @("lib", "test", "bin", "integration_test") | Where-Object { Test-Path (Join-Path $workspace $_) }
            if ($dartDirs.Count -eq 0) {
                Write-BuildLog -Context $context -Message "No Dart directories found to format."
                return
            }

            Write-BuildLog -Context $context -Message "Formatting directories: $($dartDirs -join ', ')"
            foreach ($dir in $dartDirs) {
                Invoke-BuildOptional -Context $context -Name "Format $dir" -Script {
                    Invoke-BuildExternal -Context $context -File "dart" -Parameters @("format", "--output=none", "--set-exit-if-changed", $dir)
                }
            }
        }

        Invoke-BuildStep -Context $context -StepName "Dart Analysis" -Script {
            Invoke-BuildOptional -Context $context -Name "Dart Analysis" -Script {
                Invoke-BuildExternal -Context $context -File "dart" -Parameters @("analyze")
            }
        }

        Invoke-BuildStep -Context $context -StepName "Flutter Tests" -Script {
            Invoke-BuildOptional -Context $context -Name "Flutter Tests" -Script {
                Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("test")
            }
        }
    } else {
        Write-BuildLog -Context $context -Message "Skipping format/analyze/tests (SkipTests set)."
    }

    
    if (-not $SkipBootstrapFlutterBuild) {

        Invoke-BuildStep -Context $context -StepName "Clean Build Directory" -Script {
            $removed = Remove-BuildRoot -Context $context -Path $buildRoot
            if (-not $removed -and -not $ContinueOnError) {
                throw "Failed to remove build root: $buildRoot"
            }
        }
        
        Invoke-BuildStep -Context $context -StepName "Flutter Ephemeral Build (C++ Headers)" -Script {
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("build", "windows", "--release") -IgnoreExitCode
        }

        Invoke-BuildStep -Context $context -StepName "Reset CMake Build Directory" -Script {
            if (Test-Path $cmakeBuildDir) {
                Remove-Item -LiteralPath $cmakeBuildDir -Recurse -Force -ErrorAction Stop
            }
            New-Item -ItemType Directory -Force -Path $cmakeBuildDir | Out-Null
        }
    }

    $pluginFile = Resolve-NormalizedPath -BasePath $workspace -RelativePath "windows/flutter/ephemeral/.plugin_symlinks/permission_handler_windows/windows/permission_handler_windows_plugin.cpp"
    if (Test-Path $pluginFile) {
        $pluginContent = Get-Content -LiteralPath $pluginFile -Raw
        $targetLine = 'result->Success(requestResults);'
        $patchedLine = 'result->Success(flutter::EncodableValue(requestResults));'

        if ($pluginContent -match [regex]::Escape($patchedLine)) {
            Write-BuildLog -Context $context -Message "permission_handler_windows already patched."
        } elseif ($pluginContent -match [regex]::Escape($targetLine)) {
            Write-BuildLog -Context $context -Message "Patching permission_handler_windows..."
            $updatedPluginContent = $pluginContent -replace [regex]::Escape($targetLine), $patchedLine
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($pluginFile, $updatedPluginContent, $utf8NoBom)
        } else {
            Write-BuildLogWarning -Context $context -Message "Patch target line not found in permission_handler_windows plugin file."
        }
    }

    Invoke-BuildStep -Context $context -StepName "CMake Configure" -Critical -Script {
        $cmakeArgs = @(
            $windowsSrc
            "-B", $cmakeBuildDir
            "-G", $CMakeGenerator
            "-DCMAKE_BUILD_TYPE=$CMakeBuildType"
            "-DCMAKE_INSTALL_PREFIX=$buildDirFull"
            "-DFLUTTER_TARGET_PLATFORM=windows-x64"
            "-DCMAKE_CXX_COMPILER=clang-cl"
            "-DCMAKE_C_COMPILER=clang-cl"
            "-DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc"
        )
        Invoke-BuildExternal -Context $context -File "cmake" -Parameters $cmakeArgs
    }

    Invoke-BuildStep -Context $context -StepName "Rust Crate Build" -Script {
        if (-not (Test-Path $rustDir)) {
            throw "Rust crate directory not found: $rustDir"
        }

        Push-Location $rustDir
        try {
            Invoke-BuildOptional -Context $context -Name "flutter_rust_bridge_codegen install" -Script {
                Invoke-BuildExternal -Context $context -File "cargo" -Parameters @("install", "flutter_rust_bridge_codegen")
            }
            Invoke-BuildExternal -Context $context -File "cargo" -Parameters @("build", "--release")
        } finally {
            Pop-Location
        }
    }

    Invoke-BuildStep -Context $context -StepName "Copy Rust DLL" -Script {
        if (-not (Test-Path $dllSource)) {
            throw "Rust DLL not found at $dllSource"
        }

        New-Item -ItemType Directory -Force -Path $dllDestDir | Out-Null
        Copy-Item -Path $dllSource -Destination $dllDestDir -Force
        Write-BuildLog -Context $context -Message "Rust DLL copied to $dllDestDir"
    }

    Invoke-BuildStep -Context $context -StepName "Native Assets Directory Fix" -Script {
        if (Test-Path $nativeAssetsDir) {
            $item = Get-Item -LiteralPath $nativeAssetsDir -Force
            if (-not $item.PSIsContainer) {
                Write-BuildLog -Context $context -Message "Path exists but is NOT a directory. Replacing: $nativeAssetsDir"
                Remove-Item -LiteralPath $nativeAssetsDir -Force
                New-Item -ItemType Directory -Path $nativeAssetsDir | Out-Null
            } else {
                Write-BuildLog -Context $context -Message "Path is already a directory: $nativeAssetsDir"
            }
        } else {
            Write-BuildLog -Context $context -Message "Creating directory: $nativeAssetsDir"
            New-Item -ItemType Directory -Path $nativeAssetsDir | Out-Null
        }
    }

    Invoke-BuildStep -Context $context -StepName "CMake Build & Install" -Critical -Script {
        Invoke-BuildExternal -Context $context -File "cmake" -Parameters @(
            "--build", $cmakeBuildDir,
            "--config", $CMakeBuildType,
            "--target", "install",
            "--verbose"
        )
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
    } catch {
        Write-BuildLogWarning -Context $context -Message "Failed to copy JSON summary to LogDir: $($_.Exception.Message)"
    }

    Close-BuildLog -Context $context

    if ($hadUnhandledError -or $context.Results.Failed.Count -gt 0) {
        exit 1
    }
}
