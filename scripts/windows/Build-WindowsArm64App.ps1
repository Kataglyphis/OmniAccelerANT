#requires -Version 7.0
# Copyright (c) 2025 Kataglyphis
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    The Flutter half of the Windows arm64 app, built natively on windows-11-arm with clang-cl.
.DESCRIPTION
    Builds like Build-Windows.ps1, never like `flutter build windows`, whose VS generator compiles with MSVC's cl.
    Fails when CMake picked any other compiler in either build tree (AGENTS.md § 5, the arm64 lane).
#>
[CmdletBinding()]
param(
    [string]$WorkspaceDir = $PWD.Path,
    # Beside Flutter's own build\windows\arm64, which --config-only configures for the VS generator.
    [string]$BuildDir = 'build\windows\arm64-clangcl',
    # What windows-arm64.yml stages, gates and uploads (APP_DIR). Empty = derived from -Configuration below.
    [string]$InstallDir = '',
    # Release, or Debug with ASan on (the aarch64 runtime ships since 2026-10-03); /MD stays, the x64 lane's Debug flags strip _DEBUG.
    [ValidateSet('Release', 'Debug')][string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsScripts.Shared', 'WindowsBuild.Common', 'WindowsFlutter.Common', 'WindowsSourceBuild.Common')

# The Debug app installs beside the Release one; a single fixed default sent both to runner\Release.
if (-not $InstallDir) { $InstallDir = "build\windows\arm64\runner\$Configuration" }

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @())
    & $File @Arguments
    if ($LASTEXITCODE) { throw "$File $($Arguments -join ' ') failed (exit $LASTEXITCODE)." }
}

# Only clang-cl (Clang with the MSVC front end) passes, as recorded under CMakeFiles\<version>\.
function Assert-ClangClOnly {
    param([Parameter(Mandatory)][string]$BuildDir)
    $files = @(Get-ChildItem -Path (Join-Path $BuildDir 'CMakeFiles\*\*') -File -ErrorAction SilentlyContinue |
        Where-Object Name -in 'CMakeCCompiler.cmake', 'CMakeCXXCompiler.cmake')
    if ($files.Count -eq 0) { throw "CMake recorded no C or C++ compiler under $BuildDir\CMakeFiles." }
    foreach ($file in $files) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $id = if ($text -match 'set\(CMAKE_(?:C|CXX)_COMPILER_ID "([^"]*)"\)') { $Matches[1] } else { '' }
        $frontEnd = if ($text -match 'set\(CMAKE_(?:C|CXX)_COMPILER_FRONTEND_VARIANT "([^"]*)"\)') { $Matches[1] } else { '' }
        $path = if ($text -match 'set\(CMAKE_(?:C|CXX)_COMPILER "([^"]*)"\)') { $Matches[1] } else { '' }
        if ($id -ne 'Clang' -or $frontEnd -ne 'MSVC') {
            throw "$($file.Name): CMake picked '$path' (id '$id', front end '$frontEnd'); this build is clang-cl only."
        }
        Write-Host "$($file.Name): $path (Clang, MSVC front end)"
    }
}

$workspace = (Resolve-Path -LiteralPath $WorkspaceDir).Path
Push-Location -LiteralPath $workspace
try {
    Invoke-Checked flutter @('config', '--no-analytics', '--enable-windows-desktop')
    Invoke-Checked flutter @('pub', 'get')
    # --config-only also configures a VS-generator tree; this toolchain file keeps even its probe off cl.
    $toolsetFile = Join-Path $workspace 'build\windows\clangcl-vs-toolset.cmake'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $toolsetFile)
    Set-Content -LiteralPath $toolsetFile -Value 'set(CMAKE_GENERATOR_TOOLSET "ClangCL")'
    $env:CMAKE_TOOLCHAIN_FILE = $toolsetFile
    try {
        Invoke-Checked flutter @('build', 'windows', "--$($Configuration.ToLowerInvariant())", '--config-only')
    } finally {
        Remove-Item Env:CMAKE_TOOLCHAIN_FILE
    }
    Assert-ClangClOnly -BuildDir 'build\windows\arm64'

    # The x64 lane's clang-cl patches to permission_handler_windows (Build-Windows.ps1).
    $context = New-BuildContext -Workspace $workspace -LogDir 'logs'
    Update-PermissionHandlerWindows -Context $context -WorkspaceDir $workspace

    Enter-VsDevCmdEnvironment -Arch arm64 -HostArch arm64
    # Visual Studio's own LLVM first: it is the clang the STL of that same installation expects.
    $candidates = @()
    if ($env:VCINSTALLDIR) { $candidates += Join-Path $env:VCINSTALLDIR 'Tools\Llvm\ARM64\bin\clang-cl.exe' }
    $candidates += Join-Path $env:ProgramFiles 'LLVM\bin\clang-cl.exe'
    $clangCl = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $clangCl) { throw "No clang-cl at any of: $($candidates -join ', ')." }
    Invoke-Checked $clangCl @('--version')

    # install() copies it, and only `flutter build windows` would create it.
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $workspace 'build\native_assets\windows')

    # Forward slashes: cmake_install.cmake quotes the prefix, where a backslash is an escape.
    $clangClCMake = $clangCl -replace '\\', '/'
    $installPrefix = (Join-Path $workspace $InstallDir) -replace '\\', '/'
    # ASan's sanitizer block picks Microsoft's aarch64 runtime by CMAKE_SYSTEM_PROCESSOR (hub Sanitizers.cmake).
    $cmakeArgs = @('-S', 'windows', '-B', $BuildDir, '-G', 'Ninja', "-DCMAKE_BUILD_TYPE=$Configuration")
    if ($Configuration -eq 'Debug') {
        $cmakeArgs += '-Dmyproject_ENABLE_SANITIZER_ADDRESS=ON'
        # The x64 lane's recipe: Flutter needs /MD, and clang-cl's STL under _DEBUG wants /MDd (_CrtDbgReport missing).
        $cmakeArgs += '-DCMAKE_CXX_FLAGS_DEBUG=/MD /Zi /Ob0 /Od /RTC1 /U_DEBUG /DNDEBUG /D_ITERATOR_DEBUG_LEVEL=0'
        $cmakeArgs += '-DCMAKE_C_FLAGS_DEBUG=/MD /Zi /Ob0 /Od /RTC1 /U_DEBUG /DNDEBUG /D_ITERATOR_DEBUG_LEVEL=0'
    }
    $cmakeArgs += @('-DFLUTTER_TARGET_PLATFORM=windows-arm64',
        "-DCMAKE_C_COMPILER=$clangClCMake", "-DCMAKE_CXX_COMPILER=$clangClCMake",
        '-DCMAKE_C_COMPILER_TARGET=aarch64-pc-windows-msvc', '-DCMAKE_CXX_COMPILER_TARGET=aarch64-pc-windows-msvc',
        "-DCMAKE_INSTALL_PREFIX=$installPrefix",
        '-Dinclude_kataglyphis_native_inference_tests=ON')
    # The app's CMakeLists pins /MD; the Debug flags above strip _DEBUG, the pairing a release CRT requires.
    Invoke-Checked cmake $cmakeArgs
    Assert-ClangClOnly -BuildDir $BuildDir
    Invoke-Checked cmake @('--build', $BuildDir, '--target', 'install', '--parallel', "$([Environment]::ProcessorCount)")
    # Built here, in the VS environment; windows-arm64.yml runs it once the natives sit beside the exe.
    Invoke-Checked cmake @('--build', $BuildDir, '--target', 'kataglyphis_native_inference_test', '--parallel', "$([Environment]::ProcessorCount)")
} finally {
    Pop-Location
}
