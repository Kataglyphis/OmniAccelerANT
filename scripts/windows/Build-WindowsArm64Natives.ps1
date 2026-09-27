#requires -Version 7.0
# Copyright (c) 2025 Kataglyphis
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    The native half of the Windows arm64 app, cross-built in the family image's arm64 bundle.
.DESCRIPTION
    Flutter cannot cross-build windows-arm64 from an x64 host (flutter/flutter#62597), so
    windows-arm64.yml splits the app (BACKLOG § Windows arm64): this script builds everything
    that is not Flutter's, here, and the app job on windows-11-arm builds the Flutter part
    natively against it. The product, under -OutDir:

      accelerantgine\  AccelerANTgine's own arm64 install tree: bin\ (its DLL and closure) and
                       lib\AccelerANTgine.lib. KATAGLYPHIS_ACCELERANTGINE_PREBUILT points here.
      runtime\         what the app loads beside its exe: oxidant.dll (CARGOKIT_PREBUILT_DIR
                       points here), AccelerANTgine.dll, the chain ONNX Runtime, the GStreamer
                       plugins in gstreamer-1.0\ (the x64 runner's layout) and the transitive DLL
                       closure of all of them, the VC++ runtime included.

    The hub's arch gate grades the whole product, and the app job runs it on a real device.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceDir = 'C:\ws',
    [string]$OutDir = 'dist\windows-arm64-natives',
    # The x64 lane's features without onnxruntime_directml: the arm64 ONNX Runtime has no
    # DirectML EP.
    [string]$RustFeatures = 'gstreamer,onnxruntime_dynamic',
    # The x64 runner's capture subset (Build-Windows.ps1, Bundle Media Runtime DLLs). Unlike
    # there, a plugin this image lacks fails the build instead of shrinking the set.
    [string[]]$GStreamerPlugins = @('gstcoreelements', 'gstapp', 'gsttypefindfunctions', 'gstvideoconvertscale',
        'gstvideofilter', 'gstvideorate', 'gstvideotestsrc', 'gstautodetect', 'gstwinks', 'gstmediafoundation')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule 'WindowsCrossBundle.Common'

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

# oxidant.dll, the Flutter bridge. The target tree stays off the bind mount (AGENTS.md § 5), and
# the pkg-config crate needs the cross opt-in to read the bundle's arm64 .pc files.
$env:PKG_CONFIG_ALLOW_CROSS = '1'
$cargoTarget = Join-Path $env:TEMP 'omni-arm64-cargo'
& cargo build --manifest-path (Join-Path $WorkspaceDir 'third_party\OxidANT\Cargo.toml') --release --lib `
    --target aarch64-pc-windows-msvc --features $RustFeatures --target-dir $cargoTarget
if ($LASTEXITCODE) { throw "cargo build of oxidant.dll for aarch64-pc-windows-msvc failed (exit $LASTEXITCODE)." }
Copy-Item -LiteralPath (Join-Path $cargoTarget 'aarch64-pc-windows-msvc\release\oxidant.dll') -Destination $runtime

# The seeds of the runtime closure. ORT is loaded by name (ort's load-dynamic) and the plugins
# by the webcam engine, so neither is in an import table: they are copied, not found.
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
