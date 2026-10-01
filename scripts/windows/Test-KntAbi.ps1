#requires -Version 7.0
<#
.SYNOPSIS
    The Windows twin of scripts/linux/check-knt-abi.sh: loads the plugin DLL in-process and calls its C ABI.
.DESCRIPTION
    OxidANT resolves knt_api_version and knt_push_frame by name, so a renamed export fails nowhere else.
    The calling pwsh must match the DLL's architecture: windows-x64.yml and windows-arm64.yml run it on the device.
.PARAMETER PluginDll
    kataglyphis_native_inference_plugin.dll inside an app tree, beside the exe.
.PARAMETER SearchPath
    Directories the app finds on PATH (x64: runner\bin, which holds AccelerANTgine.dll); searched after the plugin's own.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PluginDll,
    [string[]]$SearchPath = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dll = (Resolve-Path -LiteralPath $PluginDll).Path
foreach ($dir in $SearchPath) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "SearchPath entry is not a directory: $dir" }
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KntAbi {
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] public static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] public static extern IntPtr AddDllDirectory(string dir);
    [DllImport("kernel32", CharSet = CharSet.Ansi)] public static extern IntPtr GetProcAddress(IntPtr module, string name);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int ApiVersion();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int PushFrame(long id, IntPtr rgba, uint width, uint height);
}
'@

# PATH does not reach a load inside pwsh (measured: error 126), so the app's folders are added explicitly.
foreach ($dir in @(Split-Path -Parent $dll) + @($SearchPath)) {
    if ([KntAbi]::AddDllDirectory((Resolve-Path -LiteralPath $dir).Path) -eq [IntPtr]::Zero) {
        throw "AddDllDirectory($dir) failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
}
# LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS: the plugin's folder first, then those and System32.
$module = [KntAbi]::LoadLibraryExW($dll, [IntPtr]::Zero, 0x1100)
if ($module -eq [IntPtr]::Zero) {
    throw "LoadLibraryExW($dll) failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
$fn = @{}
foreach ($name in 'knt_api_version', 'knt_push_frame') {
    $fn[$name] = [KntAbi]::GetProcAddress($module, $name)
    if ($fn[$name] -eq [IntPtr]::Zero) { throw "$name is not exported by $dll" }
}

# Mirrors windows/kataglyphis_texture.h: knt_api_version() is 1; knt_push_frame returns 0, -1, -2 or -3.
$version = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($fn['knt_api_version'], [KntAbi+ApiVersion]).Invoke()
if ($version -ne 1) { throw "knt_api_version returned $version, expected 1" }
"ok   knt_api_version   = $version"

$push = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($fn['knt_push_frame'], [KntAbi+PushFrame])
$pixel = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
try {
    if ($push.Invoke(0, [IntPtr]::Zero, 1, 1) -ne -1) { throw 'knt_push_frame(null buffer) should be -1' }
    if ($push.Invoke(0, $pixel, 0, 1) -ne -1) { throw 'knt_push_frame(width 0) should be -1' }
    'ok   knt_push_frame    bad args -> -1'
    # No texture exists in this process, so every id is unknown: -2 proves the registry lookup is guarded.
    if ($push.Invoke(424242, $pixel, 1, 1) -ne -2) { throw 'knt_push_frame(unknown id) should be -2' }
    'ok   knt_push_frame    unknown texture -> -2'
} finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($pixel)
}
"knt ABI OK ($dll, $([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture))"
