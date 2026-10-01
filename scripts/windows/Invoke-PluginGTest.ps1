#requires -Version 7.0
<#
.SYNOPSIS
    Builds and/or runs the native plugin's gtest (kataglyphis_native_inference_test) against an app's runtime.
.DESCRIPTION
    The target is EXCLUDE_FROM_ALL, so -Build builds it first. The exe runs directly, not through ctest: x64 builds it
    in the image and runs it on the host, where the tree's CTest files point at container paths.
.PARAMETER BuildDir
    The app's CMake build tree, configured with -Dinclude_kataglyphis_native_inference_tests=ON.
.PARAMETER RuntimeDir
    Folders that hold AccelerANTgine.dll, the chain onnxruntime.dll and their closure (x64: runner and runner\bin).
.PARAMETER Build
    Build the test target first, with the CMake that configured the tree.
.PARAMETER NoRun
    Only build: flutter_windows.dll does not load in the Server Core image (0xC0000135, windows-x64 run 36891844116).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildDir,
    [string[]]$RuntimeDir = @(),
    [switch]$Build,
    [switch]$NoRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = 'kataglyphis_native_inference_test'
$testDir = Join-Path $BuildDir 'plugins\kataglyphis_native_inference'
$exe = Join-Path $testDir "$target.exe"

if ($Build) {
    # The tree's own CMake, which a runner-native step may not have on PATH (windows-11-arm).
    $line = Get-Content -LiteralPath (Join-Path $BuildDir 'CMakeCache.txt') | Where-Object { $_ -like 'CMAKE_COMMAND:INTERNAL=*' } | Select-Object -First 1
    if (-not $line) { throw "$BuildDir\CMakeCache.txt records no CMAKE_COMMAND." }
    $cmake = $line.Substring($line.IndexOf('=') + 1)
    & $cmake --build $BuildDir --target $target
    if ($LASTEXITCODE) { throw "cmake --build --target $target failed (exit $LASTEXITCODE)." }
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "No $exe; build the $target target first (-Build)." }
if ($NoRun) { return "built $exe" }

if ($RuntimeDir.Count -eq 0) { throw '-RuntimeDir is required to run the test.' }
$runtime = @($RuntimeDir | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
# Beside the exe, the one folder searched before System32, which holds Windows ML's own onnxruntime.dll on a client.
foreach ($name in 'AccelerANTgine.dll', 'onnxruntime.dll') {
    $source = $runtime | ForEach-Object { Join-Path $_ $name } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $source) { throw "No $name in $($runtime -join ', ')." }
    Copy-Item -LiteralPath $source -Destination $testDir -Force
}

$env:PATH = (@($runtime) + $env:PATH) -join [IO.Path]::PathSeparator
$report = Join-Path ([IO.Path]::GetTempPath()) "plugin-gtest-$([guid]::NewGuid().ToString('N')).json"
& $exe "--gtest_output=json:$report"
$exit = $LASTEXITCODE
if (-not (Test-Path -LiteralPath $report -PathType Leaf)) { throw ('{0} wrote no report (exit 0x{1:X8}); a missing DLL ends it before main.' -f $target, $exit) }
$result = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
Remove-Item -LiteralPath $report -Force
"GTEST: tests=$($result.tests) failures=$($result.failures) disabled=$($result.disabled)"
if ($exit -or $result.failures) { throw "$target failed (exit $exit, $($result.failures) failure(s))." }
if ($result.tests -lt 1) { throw "$target ran no test; a run with nothing tested is not a test verdict." }
