<#
.SYNOPSIS
  Configurable Windows build script for the Kataglyphis project.

.DESCRIPTION
  Run with defaults or pass parameters to override workspace path and other options.
  Example:
    .\build-windows.ps1 -WorkspaceDir "D:\dev\kataglyphis" -SkipFlutterBuild
#>

[CmdletBinding()]
param(
    [string] $WorkspaceDir = "C:\workspace",
    [string] $BuildDirRelease = "build/windows/x64/runner",    # relative to workspace
    [string] $ClangVersion = "21.1.6",
    [string] $GStreamerVersion = "1.26.6",
    [string] $LLVMBin = 'C:\Program Files\LLVM\bin',
    [string] $RustCrateDir = "ExternalLib\Kataglyphis-RustProjectTemplate",
    [string] $RustDllName = "kataglyphis_rustprojecttemplate.dll",
    [string] $CMakeGenerator = "Ninja",
    [string] $CMakeBuildType = "Debug", #"Release",
    [switch] $SkipTests,           # skip dart/flutter tests & analyze
    [switch] $SkipFlutterBuild,    # skip flutter build windows step
    [switch] $ContinueOnError      # make some non-critical failures continue
)

# Stop on error by default unless ContinueOnError was requested
if ($ContinueOnError) {
    $ErrorActionPreference = "Continue"
} else {
    $ErrorActionPreference = "Stop"
}

# Resolve workspace to absolute path and normalize
try {
    $Workspace = (Resolve-Path -Path $WorkspaceDir -ErrorAction Stop).Path
} catch {
    Write-Host "Workspace path doesn't exist, creating: $WorkspaceDir"
    New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
    $Workspace = (Resolve-Path -Path $WorkspaceDir).Path
}

# Derived absolute paths
$BuildRoot = Join-Path $Workspace "build"
$BuildDirFull = Join-Path $Workspace ($BuildDirRelease -replace '/','\')  # keep relative semantics
$WindowsSrc = Join-Path $Workspace "windows"
$CMakeBuildDir = Join-Path $Workspace "build\windows\x64"
$RustDir = Join-Path $Workspace $RustCrateDir
$DllSource = Join-Path $RustDir "target\release\$RustDllName"
$DllDestDir = Join-Path $Workspace "build\windows\x64\plugins\$($RustDllName -replace '\.dll$','')"
$NativeAssetsDir = Join-Path $Workspace "build\native_assets\windows"

# Export environment variables (keeps existing behavior)
$env:BUILD_DIR_RELEASE = $BuildDirRelease
$env:CLANG_VERSION = $ClangVersion
$env:GSTREAMER_VERSION = $GStreamerVersion
$env:LLVM_BIN = $LLVMBin

Write-Host "=== Configuration ==="
Write-Host "Workspace:       $Workspace"
Write-Host "BuildDirRelease: $BuildDirRelease"
Write-Host "BuildDirFull:    $BuildDirFull"
Write-Host "CMakeBuildDir:   $CMakeBuildDir"
Write-Host "RustDir:         $RustDir"
Write-Host "Rust DLL source: $DllSource"
Write-Host "Rust DLL dest:   $DllDestDir"
Write-Host "SkipTests:       $SkipTests"
Write-Host "SkipFlutterBuild:$SkipFlutterBuild"
Write-Host "ContinueOnError: $ContinueOnError"
Write-Host "====================="

# --- Basic environment checks ---
Write-Host "=== 1. Environment Check ==="
try {
    cmake --version
} catch {
    Write-Warning "cmake not found in PATH (this will fail later)."
}
try {
    clang-cl --version
} catch {
    Write-Warning "clang-cl not found in PATH (this may be fine if using MSVC, but original used clang-cl)."
}
try {
    flutter --version
} catch {
    Write-Warning "flutter not found in PATH."
}
try {
    cargo --version
} catch {
    Write-Warning "cargo not found in PATH."
}

# --- GIT CONFIGURATION ---
Write-Host "=== 2. Enabling Git Long Paths ==="
try {
    git config --global core.longpaths true
} catch {
    Write-Warning "git not available or config failed."
}

# --- FLUTTER & DART SETUP ---
if (-not $SkipFlutterBuild) {
    Write-Host "=== 3. Installing Flutter Dependencies ==="
    try {
        flutter pub get
        flutter config --enable-windows-desktop
    } catch {
        Write-Warning "Flutter setup failed. If you only need CMake build you can pass -SkipFlutterBuild."
        if (-not $ContinueOnError) { throw $_ }
    }
} else {
    Write-Host "Skipping Flutter dependency steps (SkipFlutterBuild set)."
}

# --- CODE QUALITY & TESTS ---
if (-not $SkipTests) {
    Write-Host "=== 4. Verifying Formatting (dart format) ==="
    try {
        dart format --output=none --set-exit-if-changed .
        Write-Host "Formatting verification passed."
    } catch {
        Write-Warning "Formatting verification failed, continuing (matches previous behavior)."
    }

    Write-Host "=== 5. Analyzing Project Source (dart analyze) ==="
    try {
        dart analyze
        Write-Host "Analysis passed."
    } catch {
        Write-Warning "Analysis failed, continuing."
    }

    Write-Host "=== 6. Running Flutter Tests ==="
    try {
        flutter test
        Write-Host "Tests passed."
    } catch {
        Write-Warning "Tests failed, continuing."
    }
} else {
    Write-Host "Skipping format/analyze/tests (SkipTests set)."
}

# --- FLUTTER EPHEMERAL BUILD (Header Generation) ---
if (-not $SkipFlutterBuild) {
    Write-Host "=== 7. Generating C++ Bindings (Ephemeral Build) ==="
    try {
        flutter build windows --release
    } catch {
        Write-Warning "Flutter build threw an error, but proceeding if headers were generated."
    }
}

# --- CLEAN OLD BUILD FOLDER ---
Write-Host "Cleaning build directory for CMake..."

function Remove-BuildRoot {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "Build root existiert nicht: $Path"
        return $true
    }

    # Beende potentiell sperrrende Prozesse
    Write-Host "Beende potentiell sperrrende Prozesse..."
    @("flutter", "dart", "msbuild", "devenv") | ForEach-Object {
        Get-Process $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 5

    # Retry-Schleife
    for ($i = 1; $i -le 3; $i++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-Host "Build-Verzeichnis gelöscht: $Path"
            return $true
        } catch {
            Write-Warning "Versuch $i/3 fehlgeschlagen: $($_.Exception.Message)"
            if ($i -lt 3) { Start-Sleep -Seconds 2 }
        }
    }
    return $false
}

# call the function and act on result
$removed = Remove-BuildRoot -Path $BuildRoot
if (-not $removed) {
    $msg = "Failed to remove build root: $BuildRoot."
    if ($ContinueOnError) {
        Write-Warning "$msg Continuing because -ContinueOnError was specified."
    } else {
        throw $msg
    }
}


# --- CMAKE CONFIGURE ---
Write-Host "=== 8. CMake Configure ==="
$cmakeArgs = @(
    $WindowsSrc
    "-B", $CMakeBuildDir
    "-G", $CMakeGenerator
    "-DCMAKE_BUILD_TYPE=$CMakeBuildType"
    "-DCMAKE_INSTALL_PREFIX=$BuildDirFull"
    "-DFLUTTER_TARGET_PLATFORM=windows-x64"
    "-DCMAKE_CXX_COMPILER=clang-cl"
    "-DCMAKE_C_COMPILER=clang-cl"
    "-DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc"
)

try {
    & cmake @cmakeArgs
} catch {
    Write-Error "CMake configuration failed: $_"
    if (-not $ContinueOnError) { throw $_ }
}

# --- RUST BUILD ---
Write-Host "=== 9. Building Rust Crate ==="
if (Test-Path $RustDir) {
    Push-Location $RustDir
    try {
        cargo install flutter_rust_bridge_codegen
    } catch {
        Write-Warning "Could not install flutter_rust_bridge_codegen. If already installed that's fine."
    }
    try {
        cargo build --release
    } catch {
        Write-Warning "Cargo build failed."
        if (-not $ContinueOnError) { Pop-Location; throw $_ }
    }
    Pop-Location
} else {
    Write-Warning "Rust crate directory not found: $RustDir"
}

# --- MOVE RUST DLL ---
Write-Host "=== 10. Copying Rust DLL ==="
if (-not (Test-Path $DllSource)) {
    Write-Error "Rust DLL not found at $DllSource"
    if (-not $ContinueOnError) { throw "Missing DLL: $DllSource" }
} else {
    New-Item -ItemType Directory -Force -Path $DllDestDir | Out-Null
    try {
        Copy-Item -Path $DllSource -Destination $DllDestDir -Force
        Write-Host "Rust DLL copied successfully to $DllDestDir."
    } catch {
        Write-Warning "Failed to copy Rust DLL: $_"
        if (-not $ContinueOnError) { throw $_ }
    }
}

# --- NATIVE ASSETS FIX ---
Write-Host "=== 11. Applying Native Assets Dir Fix ==="
$p = $NativeAssetsDir
if (Test-Path $p) {
    $it = Get-Item -LiteralPath $p -Force
    if ($it.PSIsContainer) {
        Write-Host "Path is already a directory: $p"
    } else {
        Write-Host "Path exists but is NOT a directory. Replacing with directory: $p"
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $p | Out-Null
    }
} else {
    Write-Host "Creating directory: $p"
    New-Item -ItemType Directory -Path $p | Out-Null
}

# --- CMAKE BUILD & INSTALL ---
Write-Host "=== 12. CMake Build & Install ==="
try {
    cmake --build $CMakeBuildDir --config $CMakeBuildType --target install --verbose
} catch {
    Write-Error "CMake build failed: $_"
    if (-not $ContinueOnError) { throw $_ }
}

Write-Host "=== Build Complete ==="
Write-Host "Build artifacts located at: $(Join-Path $Workspace $env:BUILD_DIR_RELEASE)"
