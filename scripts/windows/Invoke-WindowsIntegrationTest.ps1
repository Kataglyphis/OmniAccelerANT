#requires -Version 7.0

<#
.SYNOPSIS
  Drives integration_test/simple_test.dart against the clang-cl app the container built with -FlutterTarget.

.DESCRIPTION
  `flutter test -d windows` would build the app itself with Flutter's MSVC default; every Windows build
  here is clang-cl. The container therefore builds the app with Build-Windows.ps1 -FlutterTarget
  integration_test/simple_test.dart, and this script only drives it through `flutter drive
  --use-application-binary`, which builds nothing. Needs a host with a desktop (never the container)
  and the Flutter SDK at the image's version.

.PARAMETER AppDir
  The runner directory the integration build installed into, e.g.
  build/windows/x64/runner/x64-ClangCL-Windows-Debug, relative to the repository root or absolute.
.PARAMETER FlutterExe
  The Flutter launcher; defaults to `flutter` on PATH (the CI step clones the image's version).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [string]$Target = 'integration_test/simple_test.dart',
    [string]$Driver = 'test_driver/integration_test.dart',
    [string]$FlutterExe = 'flutter'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$appDirFull = (Resolve-Path -LiteralPath (Join-Path $repoRoot $AppDir)).Path
$exe = Join-Path $appDirFull 'omni_accelerant.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Integration app not found: $exe (build it with Build-Windows.ps1 -FlutterTarget $Target)"
}

# bin\ carries AccelerANTgine.dll and friends; the loader needs it on PATH, as Start-Windows.ps1 prepends it.
$env:PATH = "$(Join-Path $appDirFull 'bin');$env:PATH"

Push-Location $repoRoot
try {
    Write-Host "Driving $Target against $exe"
    & $FlutterExe drive --driver $Driver --target $Target -d windows --use-application-binary $exe
    if ($LASTEXITCODE) { throw "flutter drive exited $LASTEXITCODE" }
} finally {
    Pop-Location
}

Write-Host 'Integration test passed.' -ForegroundColor Green
