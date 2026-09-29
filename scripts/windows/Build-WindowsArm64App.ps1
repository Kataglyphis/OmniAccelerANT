#requires -Version 7.0
# Copyright (c) 2025 Kataglyphis
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    The Flutter half of the Windows arm64 app, built natively on windows-11-arm with clang-cl.
.DESCRIPTION
    windows-arm64.yml's app job runs this against the natives Build-WindowsArm64Natives.ps1
    cross-built (CARGOKIT_PREBUILT_DIR, KATAGLYPHIS_ACCELERANTGINE_PREBUILT). It builds the way
    the x64 lane's Build-Windows.ps1 does, not the way `flutter build windows` does: that hands
    CMake the Visual Studio generator without a toolset, so MSVC's cl compiled the whole app, and
    cl 14.51 stops at permission_handler_windows' /await with STL1011. Here Flutter only writes
    its generated files (--config-only, under the ClangCL toolset), and Ninja builds with
    clang-cl. The script fails when CMake picked any other compiler, in either build tree.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceDir = $PWD.Path,
    # Beside Flutter's own build\windows\arm64, which --config-only configures for the VS generator.
    [string]$BuildDir = 'build\windows\arm64-clangcl',
    # What windows-arm64.yml stages, gates and uploads (APP_DIR).
    [string]$InstallDir = 'build\windows\arm64\runner\Release'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsScripts.Shared', 'WindowsBuild.Common', 'WindowsFlutter.Common', 'WindowsSourceBuild.Common')

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @())
    & $File @Arguments
    if ($LASTEXITCODE) { throw "$File $($Arguments -join ' ') failed (exit $LASTEXITCODE)." }
}

# CMake records each language's compiler under CMakeFiles\<version>\. Only clang-cl, Clang with
# the MSVC front end, passes.
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
    # Writes windows\flutter\ephemeral, which the CMake build reads. It also configures Flutter's
    # own build\windows\arm64 for the Visual Studio generator, which compiles nothing but CMake's
    # compiler probe. A toolchain file gives that generator the ClangCL toolset, so not even the
    # probe runs cl (CMake reads CMAKE_TOOLCHAIN_FILE from the environment, and Flutter passes no -T).
    $toolsetFile = Join-Path $workspace 'build\windows\clangcl-vs-toolset.cmake'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $toolsetFile)
    Set-Content -LiteralPath $toolsetFile -Value 'set(CMAKE_GENERATOR_TOOLSET "ClangCL")'
    $env:CMAKE_TOOLCHAIN_FILE = $toolsetFile
    try {
        Invoke-Checked flutter @('build', 'windows', '--release', '--config-only')
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

    # install() copies it; `flutter build windows` creates it, a bare CMake build does not
    # (Build-Windows.ps1's Native Assets Directory Fix).
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $workspace 'build\native_assets\windows')

    # Forward slashes: cmake_install.cmake quotes the prefix, and a backslash there is an escape
    # (`Syntax error in cmake code` at install time, run 36620857491).
    $clangClCMake = $clangCl -replace '\\', '/'
    $installPrefix = (Join-Path $workspace $InstallDir) -replace '\\', '/'
    Invoke-Checked cmake @('-S', 'windows', '-B', $BuildDir, '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', '-DFLUTTER_TARGET_PLATFORM=windows-arm64',
        "-DCMAKE_C_COMPILER=$clangClCMake", "-DCMAKE_CXX_COMPILER=$clangClCMake",
        '-DCMAKE_C_COMPILER_TARGET=aarch64-pc-windows-msvc', '-DCMAKE_CXX_COMPILER_TARGET=aarch64-pc-windows-msvc',
        "-DCMAKE_INSTALL_PREFIX=$installPrefix", '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL')
    Assert-ClangClOnly -BuildDir $BuildDir
    Invoke-Checked cmake @('--build', $BuildDir, '--target', 'install', '--parallel', "$([Environment]::ProcessorCount)")
} finally {
    Pop-Location
}
