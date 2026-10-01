#requires -Version 7.0
<#
.SYNOPSIS
    Runs the native plugin's gtest (kataglyphis_native_inference_test) through ctest against an app's runtime.
.DESCRIPTION
    The target is EXCLUDE_FROM_ALL, so -Build builds it first; Build-Windows.ps1 and windows-arm64.yml call this.
.PARAMETER BuildDir
    The app's CMake build tree, configured with -Dinclude_kataglyphis_native_inference_tests=ON.
.PARAMETER RuntimeDir
    Folders that hold AccelerANTgine.dll, the chain onnxruntime.dll and their closure (x64: runner and runner\bin).
.PARAMETER Build
    Build the test target first, in the environment the app was built in.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildDir,
    [Parameter(Mandatory)][string[]]$RuntimeDir,
    [switch]$Build
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = 'kataglyphis_native_inference_test'
$testDir = Join-Path $BuildDir 'plugins\kataglyphis_native_inference'
$runtime = @($RuntimeDir | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })

# The tools that configured the tree, which a runner-native step may not have on PATH (windows-11-arm).
$cache = Get-Content -LiteralPath (Join-Path $BuildDir 'CMakeCache.txt')
function Get-CacheTool([string]$Name) {
    $line = $cache | Where-Object { $_ -like "${Name}:INTERNAL=*" } | Select-Object -First 1
    if (-not $line) { throw "$BuildDir\CMakeCache.txt records no $Name." }
    return $line.Substring($line.IndexOf('=') + 1)
}
$cmake = Get-CacheTool 'CMAKE_COMMAND'
$ctest = Get-CacheTool 'CMAKE_CTEST_COMMAND'

if ($Build) {
    & $cmake --build $BuildDir --target $target
    if ($LASTEXITCODE) { throw "cmake --build --target $target failed (exit $LASTEXITCODE)." }
}
$exe = Join-Path $testDir "$target.exe"
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "No $exe; build the $target target first (-Build)." }

# Beside the exe, the one folder searched before System32, which holds Windows ML's own onnxruntime.dll on a client.
foreach ($name in 'AccelerANTgine.dll', 'onnxruntime.dll') {
    $source = $runtime | ForEach-Object { Join-Path $_ $name } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $source) { throw "No $name in $($runtime -join ', ')." }
    Copy-Item -LiteralPath $source -Destination $testDir -Force
}

$env:PATH = (@($runtime) + $env:PATH) -join [IO.Path]::PathSeparator
& $ctest --test-dir $testDir --output-on-failure --no-tests=error
if ($LASTEXITCODE) { throw "ctest in $testDir failed (exit $LASTEXITCODE)." }
