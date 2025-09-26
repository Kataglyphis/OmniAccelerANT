Param(
    [string]$ClangVersion  = '21.1.1'
)

Write-Host "=== Installing build dependencies on Windows ==="

# Enable verbose logging
$ErrorActionPreference = 'Stop'

# Install LLVM/Clang via Chocolatey
# 
Write-Host "Installing LLVM/Clang $ClangVersion..."
winget install --accept-source-agreements --accept-package-agreements --id=LLVM.LLVM -v $ClangVersion -e

# Install sccache
Write-Host "Installing sccache..."
winget install --accept-source-agreements --accept-package-agreements --id=Ccache.Ccache  -e

# Install CMake, Cppcheck, NSIS via WinGet
Write-Host "Installing CMake, Cppcheck and NSIS via winget..."
winget install --accept-source-agreements --accept-package-agreements cmake cppcheck nsis
# also get wix
winget install --accept-source-agreements --accept-package-agreements WiXToolset.WiXToolset
# get ninja
Write-Host "Installing Ninja via winget..."
winget install --accept-source-agreements --accept-package-agreements --id=Ninja-build.Ninja  -e

# Add NSIS to PATH (in case it's under Program Files (x86))
$nsisPath = 'C:\Program Files (x86)\NSIS'
if (Test-Path $nsisPath) {
    Write-Host "Adding NSIS path to GITHUB_PATH: $nsisPath"
    $nsisPath | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
} else {
    Write-Warning "NSIS installation path not found at $nsisPath"
}

Write-Host "=== Dependency installation completed ==="
