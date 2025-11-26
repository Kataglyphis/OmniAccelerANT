$ErrorActionPreference = "Stop"

# Environment variables matching the workflow
$env:BUILD_DIR_RELEASE = "build/windows/x64/runner"
$env:CLANG_VERSION = "21.1.6"
$env:GSTREAMER_VERSION = "1.26.6"
$env:LLVM_BIN = 'C:\Program Files\LLVM\bin'

Write-Host "=== 1. Environment Check ==="
cmake --version
clang-cl --version
flutter --version
cargo --version

# --- GIT CONFIGURATION ---
Write-Host "=== 2. Enabling Git Long Paths ==="
git config --global core.longpaths true

# --- FLUTTER & DART SETUP ---
Write-Host "=== 3. Installing Flutter Dependencies ==="
flutter pub get
flutter config --enable-windows-desktop

# --- CODE QUALITY & TESTS (matching workflow's continue-on-error behavior) ---
Write-Host "=== 4. Verifying Formatting (dart format) ==="
try {
    dart format --output=none --set-exit-if-changed .
    Write-Host "Formatting verification passed."
} catch {
    Write-Warning "Formatting verification failed, but continuing (continue-on-error: true)."
}

Write-Host "=== 5. Analyzing Project Source (dart analyze) ==="
try {
    dart analyze
    Write-Host "Analysis passed."
} catch {
    Write-Warning "Analysis failed, but continuing (continue-on-error: true)."
}

Write-Host "=== 6. Running Flutter Tests ==="
try {
    flutter test
    Write-Host "Tests passed."
} catch {
    Write-Warning "Tests failed, but continuing (continue-on-error: true)."
}

# --- FLUTTER EPHEMERAL BUILD (Header Generation) ---
Write-Host "=== 7. Generating C++ Bindings (Ephemeral Build) ==="
try {
    flutter build windows --release
} catch {
    Write-Warning "Flutter build threw an error, but proceeding if headers were generated."
}

Write-Host "Cleaning build directory for CMake..."
if (Test-Path "C:\workspace\build") {
    Remove-Item -Recurse -Force "C:\workspace\build"
}

# --- CMAKE CONFIGURE ---
Write-Host "=== 8. CMake Configure ==="
cmake `
    "C:\workspace\windows" `
    -B "C:\workspace\build\windows\x64" `
    -G "Ninja" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_INSTALL_PREFIX="C:\workspace\build\windows\x64\runner" `
    -DFLUTTER_TARGET_PLATFORM=windows-x64 `
    -DCMAKE_CXX_COMPILER='clang-cl' `
    -DCMAKE_C_COMPILER='clang-cl' `
    -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc

# --- RUST BUILD ---
Write-Host "=== 9. Building Rust Crate ==="
Set-Location "C:\workspace\rust"
cargo install flutter_rust_bridge_codegen
cargo build --release
Set-Location "C:\workspace"

# --- MOVE RUST DLL ---
Write-Host "=== 10. Copying Rust DLL ==="
$dllSource = "C:\workspace\rust\target\release\rust_lib_kataglyphis_inference_engine.dll"
$dllDestDir = "C:\workspace\build\windows\x64\plugins\rust_lib_kataglyphis_inference_engine"

# --- NATIVE ASSETS FIX ---
Write-Host "=== 11. Applying Native Assets Dir Fix ==="
$p = "C:\workspace\build\native_assets\windows"
if (Test-Path $p) {
    $it = Get-Item -LiteralPath $p -Force
    if ($it.PSIsContainer) {
        Write-Host "Path is already a directory: $p"
    } else {
        Write-Host "Path exists but is NOT a directory. Removing and creating directory: $p"
        Remove-Item -LiteralPath $p -Force
        New-Item -ItemType Directory -Path $p | Out-Null
    }
} else {
    Write-Host "Creating directory: $p"
    New-Item -ItemType Directory -Path $p | Out-Null
}

if (-not (Test-Path $dllSource)) {
    Write-Error "Rust DLL not found at $dllSource"
}

New-Item -ItemType Directory -Force -Path $dllDestDir | Out-Null
Copy-Item -Path $dllSource -Destination $dllDestDir -Force
Write-Host "Rust DLL copied successfully."

# --- CMAKE BUILD & INSTALL ---
Write-Host "=== 12. CMake Build & Install ==="
cmake --build "C:\workspace\build\windows\x64" --config Release --target install --verbose

Write-Host "=== Build Complete ==="
Write-Host "Build artifacts located at: C:\workspace\$env:BUILD_DIR_RELEASE"
