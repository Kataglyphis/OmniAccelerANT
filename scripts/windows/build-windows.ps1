$ErrorActionPreference = "Stop"

Write-Host "=== 1. Environment Check ==="
cmake --version
clang-cl --version
flutter --version
cargo --version

# --- FLUTTER & DART SETUP ---
Write-Host "=== 2. Installing Flutter Dependencies ==="
# Note: This requires Flutter to be installed in the Docker image
flutter config --enable-windows-desktop
flutter pub get

# --- NEW: CODE QUALITY & TESTS ---
Write-Host "=== 1. Verifying Formatting (dart format) ==="
# Use dart format to ensure code styling is consistent
dart format --output=none --set-exit-if-changed .
Write-Host "=== 2. Analyzing Project Source (dart analyze) ==="
# Runs code analysis to check for issues and warnings
dart analyze --fatal-warnings
Write-Host "=== 3. Running Flutter Tests ==="
# Runs all tests in the project
flutter test

# --- RUST BUILD ---
Write-Host "=== 3. Building Rust Crate ==="
Set-Location "C:\workspace\rust"
# Installing codegen might be skipped if already in image, but keeping for safety
cargo install flutter_rust_bridge_codegen
cargo build --release
Set-Location "C:\workspace"

# --- FLUTTER EPHEMERAL BUILD (Header Generation) ---
Write-Host "=== 4. Generating C++ Bindings (Ephemeral Build) ==="
# We run a build to generate headers, then delete the build output 
# so CMake starts with a clean slate, but headers in windows/runner remain.
try {
    flutter build windows --release
} catch {
    Write-Warning "Flutter build threw an error, but proceeding if headers were generated."
}
if (Test-Path "C:\workspace\build") {
    Write-Host "Cleaning build directory for CMake..."
    Remove-Item -Recurse -Force "C:\workspace\build"
}

# --- CMAKE CONFIGURE ---
Write-Host "=== 5. CMake Configure ==="
cmake -S "C:\workspace\windows" `
      -B "C:\workspace\build\windows\x64" `
      -G "Ninja" `
      -DCMAKE_BUILD_TYPE=Release `
      -DCMAKE_INSTALL_PREFIX="C:\workspace\build\windows\x64\runner" `
      -DFLUTTER_TARGET_PLATFORM=windows-x64 `
      -DCMAKE_CXX_COMPILER=clang-cl `
      -DCMAKE_C_COMPILER=clang-cl `
      -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc

# --- MOVE RUST DLL ---
Write-Host "=== 6. Copying Rust DLL ==="
$dllSource = "C:\workspace\rust\target\release\rust_lib_kataglyphis_inference_engine.dll"
$dllDestDir = "C:\workspace\build\windows\x64\plugins\rust_lib_kataglyphis_inference_engine"
if (-not (Test-Path $dllSource)) {
   Write-Error "Rust DLL not found at $dllSource"
}
New-Item -ItemType Directory -Force -Path $dllDestDir | Out-Null
Copy-Item -Path $dllSource -Destination $dllDestDir -Force
Write-Host "Rust DLL copied successfully."

# --- NATIVE ASSETS FIX ---
Write-Host "=== 7. Applying Native Assets Dir Fix ==="
$p = "C:\workspace\build\native_assets\windows"
if (Test-Path $p) {
    $it = Get-Item -LiteralPath $p -Force
    if (-not $it.PSIsContainer) {
        Remove-Item -LiteralPath $p -Force
        New-Item -ItemType Directory -Path $p | Out-Null
    }
} else {
    New-Item -ItemType Directory -Path $p | Out-Null
}

# --- CMAKE BUILD & INSTALL ---
Write-Host "=== 8. CMake Build & Install ==="
cmake --build "C:\workspace\build\windows\x64" --config Release --target install --verbose

Write-Host "=== Build Complete ==="
