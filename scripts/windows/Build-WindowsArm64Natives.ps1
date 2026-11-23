#requires -Version 7.0
# Copyright (c) 2025 Kataglyphis
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    The native half of the Windows arm64 app, cross-built in the family image's arm64 bundle.
.DESCRIPTION
    Under -OutDir: runtime\, everything the exe loads beside it (for CARGOKIT_PREBUILT_DIR).
    Flutter cannot cross-build windows-arm64 (flutter/flutter#62597).
#>
[CmdletBinding()]
param(
    [string]$WorkspaceDir = 'C:\ws',
    [string]$OutDir = 'dist\windows-arm64-natives',
    # The x64 runner's capture subset; unlike there, a missing plugin fails the build.
    [string[]]$GStreamerPlugins = @('gstcoreelements', 'gstapp', 'gsttypefindfunctions', 'gstvideoconvertscale',
        'gstvideofilter', 'gstvideorate', 'gstvideotestsrc', 'gstautodetect', 'gstwinks', 'gstmediafoundation')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsCrossBundle.Common', 'WindowsMsvcRuntimeNotice.Common')
# G6 and its stamp, as the x64 runner gets them; the app job re-proves the stamp on the device.
Import-BuildModule @('WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common', 'WindowsOrtLicense.Common', 'WindowsOrtRunner.Common')

$out = Join-Path $WorkspaceDir $OutDir
$runtime = Join-Path $out 'runtime'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path (Join-Path $runtime 'gstreamer-1.0')
& (Join-Path $PSScriptRoot 'Stage-DetectorModel.ps1') -WorkspaceDir $WorkspaceDir -RunnerDir $runtime

# Target tree off the bind mount (AGENTS.md § 5); the cross opt-in lets pkg-config read arm64 .pc files.
$env:PKG_CONFIG_ALLOW_CROSS = '1'
# As cargokit's patch does: OxidANT's release profile aborts on a panic, and the app must get it as a Dart exception.
$env:CARGO_PROFILE_RELEASE_PANIC = 'unwind'
$cargoTarget = Join-Path $env:TEMP 'omni-arm64-cargo'
& cargo build --manifest-path (Join-Path $WorkspaceDir 'third_party\OxidANT\Cargo.toml') --release --lib `
    --target aarch64-pc-windows-msvc --target-dir $cargoTarget
if ($LASTEXITCODE) { throw "cargo build of oxidant.dll for aarch64-pc-windows-msvc failed (exit $LASTEXITCODE)." }
Copy-Item -LiteralPath (Join-Path $cargoTarget 'aarch64-pc-windows-msvc\release\oxidant.dll') -Destination $runtime

# ORT and the plugins are loaded by name, never imported, so they seed the closure by copy.
$ortDll = Join-Path "$env:ONNX_ROOT" 'bin\onnxruntime.dll'
if (-not (Test-Path -LiteralPath $ortDll)) { throw "No chain ONNX Runtime at $ortDll (ONNX_ROOT='$env:ONNX_ROOT')." }
Copy-Item -LiteralPath $ortDll -Destination $runtime
$pluginDir = if ($env:GSTREAMER_PLUGIN_DIR) { $env:GSTREAMER_PLUGIN_DIR } else { 'C:\runtime\lib\gstreamer-1.0' }
$missing = @($GStreamerPlugins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $pluginDir "$_.dll") -PathType Leaf) })
if ($missing.Count) { throw "GStreamer plugins missing from $pluginDir`: $($missing -join ', ')." }
foreach ($name in $GStreamerPlugins) { Copy-Item -LiteralPath (Join-Path $pluginDir "$name.dll") -Destination (Join-Path $runtime 'gstreamer-1.0') }

$seeds = @(Get-ChildItem -LiteralPath $runtime -Filter '*.dll' -File -Recurse | ForEach-Object FullName)
$added = @(Copy-PeImportClosure -Path $seeds -SearchDirectory @(Get-ProductDllSearchPath -Arch arm64) -Destination $runtime -Arch arm64)
Write-Host "arm64 natives in $out`: $($seeds.Count) seed(s), $($added.Count) closure DLL(s) in runtime\"

# G6 needs a host exe, and the app's is built later on the device: an arm64 stub sits where it will; the app job re-proves with the real one.
$env:WINDOWS_TARGET_ARCH = 'arm64'
$proofDir = Join-Path $env:TEMP "omni-arm64-g6-$([guid]::NewGuid().ToString('N'))"
Copy-Item -LiteralPath $runtime -Destination $proofDir -Recurse
$hostCrate = Join-Path $env:TEMP "omni-arm64-g6-host-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Force -Path (Join-Path $hostCrate 'src')
Set-Content -LiteralPath (Join-Path $hostCrate 'Cargo.toml') -Value "[package]`nname = `"omni_accelerant`"`nversion = `"0.0.0`"`nedition = `"2021`"`n`n[workspace]`n"
Set-Content -LiteralPath (Join-Path $hostCrate 'src\main.rs') -Value 'fn main() {}'
& cargo build --manifest-path (Join-Path $hostCrate 'Cargo.toml') --release --target aarch64-pc-windows-msvc --target-dir (Join-Path $hostCrate 'target')
if ($LASTEXITCODE) { throw "cargo build of the G6 host stub for aarch64-pc-windows-msvc failed (exit $LASTEXITCODE)." }
Copy-Item -LiteralPath (Join-Path $hostCrate 'target\aarch64-pc-windows-msvc\release\omni_accelerant.exe') -Destination $proofDir
$proof = Invoke-RunnerOrtProof -RunnerDir $proofDir
Copy-Item -LiteralPath (Join-Path $proofDir 'ort-chain-stamp.json') -Destination $runtime
Copy-Item -LiteralPath (Join-Path $proofDir 'licenses') -Destination $runtime -Recurse
Remove-Item -LiteralPath $proofDir, $hostCrate -Recurse -Force
Write-Host "G6: the chain ONNX Runtime in runtime\ is proved and stamped: $(@($proof.Stamp.sha256.Keys) -join ', ')"
# After the proof's licenses\ copy, which would otherwise nest into an existing folder; x64 installs the same notice from CMake.
$null = Copy-MsvcRuntimeNotice -Root $runtime
