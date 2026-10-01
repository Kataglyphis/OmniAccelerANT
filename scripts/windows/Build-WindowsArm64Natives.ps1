#requires -Version 7.0
# Copyright (c) 2025 Kataglyphis
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    The native half of the Windows arm64 app, cross-built in the family image's arm64 bundle.
.DESCRIPTION
    Under -OutDir: accelerantgine\ (for KATAGLYPHIS_ACCELERANTGINE_PREBUILT) and runtime\, everything the exe
    loads beside it (for CARGOKIT_PREBUILT_DIR). Flutter cannot cross-build windows-arm64 (flutter/flutter#62597).
#>
[CmdletBinding()]
param(
    [string]$WorkspaceDir = 'C:\ws',
    [string]$OutDir = 'dist\windows-arm64-natives',
    # The x64 features minus onnxruntime_directml: the arm64 ONNX Runtime has no DirectML EP.
    [string]$RustFeatures = 'gstreamer,onnxruntime_dynamic',
    # The x64 runner's capture subset; unlike there, a missing plugin fails the build.
    [string[]]$GStreamerPlugins = @('gstcoreelements', 'gstapp', 'gsttypefindfunctions', 'gstvideoconvertscale',
        'gstvideofilter', 'gstvideorate', 'gstvideotestsrc', 'gstautodetect', 'gstwinks', 'gstmediafoundation')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule 'WindowsCrossBundle.Common'
# G6 and its stamp, as the x64 runner gets them; the app job re-proves the stamp on the device.
Import-BuildModule @('WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common', 'WindowsOrtRunner.Common')

$out = Join-Path $WorkspaceDir $OutDir
$runtime = Join-Path $out 'runtime'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path (Join-Path $runtime 'gstreamer-1.0')

# AccelerANTgine: its own arm64 lane, so this is exactly what its windows-arm64-cross.yml ships.
$kci = Join-Path $WorkspaceDir 'third_party\AccelerANTgine'
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kci 'scripts\windows\Build-Windows.ps1') `
    -WorkspaceDir $kci -TargetArch arm64 -BuildTargets clangcl-release -SkipFormat
if ($LASTEXITCODE) { throw "AccelerANTgine's arm64 build failed (exit $LASTEXITCODE)." }
$kciBundle = Join-Path $kci 'dist\windows-arm64\bundle'
foreach ($file in 'bin\AccelerANTgine.dll', 'lib\AccelerANTgine.lib') {
    if (-not (Test-Path -LiteralPath (Join-Path $kciBundle $file))) { throw "AccelerANTgine's arm64 bundle lacks $file ($kciBundle)." }
}
Copy-Item -LiteralPath $kciBundle -Destination (Join-Path $out 'accelerantgine') -Recurse
# The C API headers travel with the DLL: on windows-11-arm REALPATH leaves the plugin junction unresolved.
$kciInclude = Join-Path $out 'accelerantgine\include'
$null = New-Item -ItemType Directory -Force -Path $kciInclude
foreach ($header in 'kataglyphis_c_api.h', 'kataglyphis_export.h') { Copy-Item -LiteralPath (Join-Path $kci "Src\$header") -Destination $kciInclude }

# Target tree off the bind mount (AGENTS.md § 5); the cross opt-in lets pkg-config read arm64 .pc files.
$env:PKG_CONFIG_ALLOW_CROSS = '1'
$cargoTarget = Join-Path $env:TEMP 'omni-arm64-cargo'
& cargo build --manifest-path (Join-Path $WorkspaceDir 'third_party\OxidANT\Cargo.toml') --release --lib `
    --target aarch64-pc-windows-msvc --features $RustFeatures --target-dir $cargoTarget
if ($LASTEXITCODE) { throw "cargo build of oxidant.dll for aarch64-pc-windows-msvc failed (exit $LASTEXITCODE)." }
Copy-Item -LiteralPath (Join-Path $cargoTarget 'aarch64-pc-windows-msvc\release\oxidant.dll') -Destination $runtime

# ORT and the plugins are loaded by name, never imported, so they seed the closure by copy.
Copy-Item -LiteralPath (Join-Path $kciBundle 'bin\AccelerANTgine.dll') -Destination $runtime
$ortDll = Join-Path "$env:ONNX_ROOT" 'bin\onnxruntime.dll'
if (-not (Test-Path -LiteralPath $ortDll)) { throw "No chain ONNX Runtime at $ortDll (ONNX_ROOT='$env:ONNX_ROOT')." }
Copy-Item -LiteralPath $ortDll -Destination $runtime
$pluginDir = if ($env:GSTREAMER_PLUGIN_DIR) { $env:GSTREAMER_PLUGIN_DIR } else { 'C:\runtime\lib\gstreamer-1.0' }
$missing = @($GStreamerPlugins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $pluginDir "$_.dll") -PathType Leaf) })
if ($missing.Count) { throw "GStreamer plugins missing from $pluginDir`: $($missing -join ', ')." }
foreach ($name in $GStreamerPlugins) { Copy-Item -LiteralPath (Join-Path $pluginDir "$name.dll") -Destination (Join-Path $runtime 'gstreamer-1.0') }

$seeds = @(Get-ChildItem -LiteralPath $runtime -Filter '*.dll' -File -Recurse | ForEach-Object FullName)
$added = @(Copy-PeImportClosure -Path $seeds -SearchDirectory @(Get-ProductDllSearchPath -Arch arm64) -Destination $runtime -Arch arm64)
Write-Host "arm64 natives in $out`: $($seeds.Count) seed(s), $($added.Count) closure DLL(s) in runtime\, features $RustFeatures"

# runtime\ is what the app job stages beside the exe, so G6 proves it here, where ONNX_ROOT names the reference.
$env:WINDOWS_TARGET_ARCH = 'arm64'
$proof = Invoke-RunnerOrtProof -RunnerDir $runtime
Write-Host "G6: the chain ONNX Runtime in runtime\ is proved and stamped: $(@($proof.Stamp.sha256.Keys) -join ', ')"
