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
    [switch] $SkipFlutterBuild,
    [switch] $ContinueOnError,
    [switch] $StopOnError,
    [switch] $CodeQL
)

Set-StrictMode -Version Latest

$sharedModulePath = Join-Path $PSScriptRoot "..\..\ExternalLib\Kataglyphis-ContainerHub\windows\scripts\modules\WindowsBuild.Common.psm1"
$sharedModulePath = [System.IO.Path]::GetFullPath($sharedModulePath)
if (-not (Test-Path $sharedModulePath)) {
    throw "Required build module not found: $sharedModulePath"
}

Import-Module $sharedModulePath -Force

function Resolve-WorkspacePath {
    param([string]$Path)

    try {
        return (Resolve-Path -Path $Path -ErrorAction Stop).Path
    } catch {
        Write-Host "Workspace path doesn't exist, creating: $Path"
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        return (Resolve-Path -Path $Path -ErrorAction Stop).Path
    }
}

function Invoke-CodeQLBuild {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,
        [Parameter(Mandatory)]
        [string]$Workspace,
        [Parameter(Mandatory)]
        [hashtable]$ForwardParameters
    )

    Write-BuildLog -Context $Context -Message "=== CodeQL Mode Active ==="

    $codeQLUrl = "https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-win64.zip"
    $codeQLDir = Join-Path $Workspace "codeql-cli"
    $codeQLExe = Join-Path $codeQLDir "codeql\codeql.exe"

    if (-not (Test-Path $codeQLExe)) {
        Write-BuildLog -Context $Context -Message "Downloading CodeQL CLI..."
        New-Item -ItemType Directory -Force -Path $codeQLDir | Out-Null
        $zipPath = Join-Path $codeQLDir "codeql.zip"
        Invoke-WebRequest -Uri $codeQLUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $codeQLDir -Force
    }

    $languages = @("cpp", "rust")
    Write-BuildLog -Context $Context -Message "Downloading query packs for all languages..."
    foreach ($lang in $languages) {
        $queryPack = "codeql/$lang-queries"
        Write-BuildLog -Context $Context -Message "Downloading Query Pack: $queryPack..."
        & $codeQLExe pack download $queryPack
        if ($LASTEXITCODE -ne 0) {
            Write-BuildLogWarning -Context $Context -Message "Failed to download $queryPack, continuing..."
        }
    }

    $innerArgs = @{}
    foreach ($pair in $ForwardParameters.GetEnumerator()) {
        if ($pair.Key -eq 'CodeQL') {
            continue
        }
        $innerArgs[$pair.Key] = $pair.Value
    }

    $innerParameterString = ($innerArgs.GetEnumerator() | ForEach-Object {
            if ($_.Value -is [switch]) {
                if ($_.Value.IsPresent) { "-$($_.Key)" }
            } elseif ($_.Value -is [bool]) {
                if ($_.Value) { "-$($_.Key)" }
            } else {
                "-$($_.Key) `"$($_.Value)`""
            }
        }) -join ' '

    $selfScript = $MyInvocation.MyCommand.Path
    $innerCommand = "cmd /c powershell -NoProfile -ExecutionPolicy Bypass -File `"$selfScript`" $innerParameterString"

    $dbClusterDir = Join-Path $Workspace "codeql-db-cluster"
    if (Test-Path $dbClusterDir) {
        Remove-Item -Recurse -Force $dbClusterDir
    }

    $languageArgs = @()
    foreach ($lang in $languages) {
        $languageArgs += "--language=$lang"
    }

    $createArgs = @(
        "database", "create", $dbClusterDir,
        "--db-cluster"
    ) + $languageArgs + @(
        "--command=$innerCommand",
        "--no-run-unnecessary-builds",
        "--source-root=$Workspace",
        "--overwrite"
    )

    Write-BuildLog -Context $Context -Message "Creating database cluster with languages: $($languages -join ', ')"
    & $codeQLExe @createArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CodeQL Database Cluster creation failed"
    }

    $resultsDir = Join-Path $Workspace "codeql-results"
    New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

    foreach ($lang in $languages) {
        Write-BuildLog -Context $Context -Message ""
        Write-BuildLog -Context $Context -Message "------------------------------------------------"
        Write-BuildLog -Context $Context -Message ">>> Analyzing Language: $lang"
        Write-BuildLog -Context $Context -Message "------------------------------------------------"

        $langDbDir = Join-Path $dbClusterDir $lang
        $sarifOutput = Join-Path $resultsDir "$lang.sarif"
        $querySuite = "codeql/$lang-queries:codeql-suites/$lang-security-and-quality.qls"

        $analyzeArgs = @(
            "database", "analyze", $langDbDir,
            $querySuite,
            "--format=sarif-latest",
            "--output=$sarifOutput",
            "--download"
        )

        & $codeQLExe @analyzeArgs
        if ($LASTEXITCODE -ne 0) {
            Write-BuildLogWarning -Context $Context -Message "Analysis with query suite failed for $lang, trying with query pack..."
            $fallbackQueryPack = "codeql/$lang-queries"
            $fallbackArgs = @(
                "database", "analyze", $langDbDir,
                $fallbackQueryPack,
                "--format=sarif-latest",
                "--output=$sarifOutput",
                "--download"
            )

            & $codeQLExe @fallbackArgs
            if ($LASTEXITCODE -ne 0) {
                Write-BuildLogError -Context $Context -Message "Analysis failed for $lang even with basic query pack"
                continue
            }
        }

        Write-BuildLogSuccess -Context $Context -Message "Analysis completed for $lang. Results saved to: $sarifOutput"
    }

    Write-BuildLog -Context $Context -Message ""
    Write-BuildLogSuccess -Context $Context -Message "=== CodeQL Analysis Complete ==="
    Write-BuildLog -Context $Context -Message "All results available in: $resultsDir"
}

$workspace = Resolve-WorkspacePath -Path $WorkspaceDir

if ($ContinueOnError) {
    $ErrorActionPreference = "Continue"
} else {
    $ErrorActionPreference = "Stop"
}

$context = New-BuildContext -Workspace $workspace -LogDir $LogDir -StopOnError:$StopOnError
Open-BuildLog -Context $context

$buildRoot = Join-Path $workspace "build"
$buildDirFull = Join-Path $workspace ($BuildDirRelease -replace '/', '\\')
$windowsSrc = Join-Path $workspace "windows"
$cmakeBuildDir = Join-Path $workspace "build\windows\x64"
$rustDir = Join-Path $workspace $RustCrateDir
$dllSource = Join-Path $rustDir "target\release\$RustDllName"
$dllDestDir = Join-Path $workspace "build\windows\x64\plugins\$($RustDllName -replace '\\.dll$','')"
$nativeAssetsDir = Join-Path $workspace "build\native_assets\windows"

$env:BUILD_DIR_RELEASE = $BuildDirRelease

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
    Write-BuildLog -Context $context -Message "SkipFlutterBuild: $SkipFlutterBuild"
    Write-BuildLog -Context $context -Message "ContinueOnError:  $ContinueOnError"
    Write-BuildLog -Context $context -Message "StopOnError:      $StopOnError"
    Write-BuildLog -Context $context -Message ("=" * 60)

    if ($CodeQL) {
        Invoke-CodeQLBuild -Context $context -Workspace $workspace -ForwardParameters $PSBoundParameters
        exit 0
    }

    Invoke-BuildStep -Context $context -StepName "Environment Check" -Script {
        Invoke-BuildOptional -Context $context -Name "cmake" -Script { Invoke-BuildExternal -Context $context -File "cmake" -Parameters @("--version") }
        Invoke-BuildOptional -Context $context -Name "clang-cl" -Script { Invoke-BuildExternal -Context $context -File "clang-cl" -Parameters @("--version") }
        Invoke-BuildOptional -Context $context -Name "flutter" -Script { Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("--version") }
        Invoke-BuildOptional -Context $context -Name "cargo" -Script { Invoke-BuildExternal -Context $context -File "cargo" -Parameters @("--version") }
        Invoke-BuildOptional -Context $context -Name "ninja" -Script { Invoke-BuildExternal -Context $context -File "ninja" -Parameters @("--version") }
    }

    Invoke-BuildStep -Context $context -StepName "Git Configuration" -Script {
        Invoke-BuildExternal -Context $context -File "git" -Parameters @("config", "--global", "core.longpaths", "true") -IgnoreExitCode
    }

    if (-not $SkipFlutterBuild) {
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

    Invoke-BuildStep -Context $context -StepName "Clean Build Directory" -Script {
        $removed = Remove-BuildRoot -Context $context -Path $buildRoot
        if (-not $removed -and -not $ContinueOnError) {
            throw "Failed to remove build root: $buildRoot"
        }
    }

    if (-not $SkipFlutterBuild) {
        Invoke-BuildStep -Context $context -StepName "Flutter Ephemeral Build (C++ Headers)" -Script {
            Invoke-BuildExternal -Context $context -File "flutter" -Parameters @("build", "windows", "--release") -IgnoreExitCode
        }
    }

    $pluginFile = "windows\flutter\ephemeral\.plugin_symlinks\permission_handler_windows\windows\permission_handler_windows_plugin.cpp"
    if (Test-Path $pluginFile) {
        Write-BuildLog -Context $context -Message "Patching permission_handler_windows..."
        (Get-Content $pluginFile) -replace 'result->Success\(requestResults\);', 'result->Success(flutter::EncodableValue(requestResults));' | Set-Content $pluginFile
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
    Write-BuildLogError -Context $context -Message "Unhandled critical error: $($_.Exception.Message)"
    if ($_.ScriptStackTrace) {
        Write-BuildLogError -Context $context -Message "Stack trace: $($_.ScriptStackTrace)"
    }
} finally {
    Write-BuildSummary -Context $context
    Close-BuildLog -Context $context

    if ($context.Results.Failed.Count -gt 0) {
        exit 1
    }
}
