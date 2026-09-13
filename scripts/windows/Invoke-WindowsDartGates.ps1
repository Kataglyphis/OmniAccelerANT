#requires -Version 7.0

<#
.SYNOPSIS
  Runs this repo's Dart gates inside the Windows build container, for
  scripts/windows/Build-Windows-Container.ps1 -TestsOnly.

.DESCRIPTION
  `flutter pub get`, `flutter analyze` and `flutter test` - the same pair
  Build-Windows.ps1 runs when -SkipTests is omitted. It is a separate script
  because the agentic loop's build invocation always passes -SkipTests (the
  test phase is its own command), and `Build-Windows.ps1
  -SkipBootstrapFlutterBuild` is not an alternative: its Delivery Check still
  requires a runner exe, which a container with no prior build does not have.

  Runs in the tar-pipe workspace C:\ws (matching the driver's -WorkspacePath).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\ws'

# Share the build phase's pub cache so package_config.json paths stay valid.
$env:PUB_CACHE = 'C:\kataglyphis_fast_build\.cache\pub-cache'
if (-not (Test-Path -LiteralPath $env:PUB_CACHE -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $env:PUB_CACHE | Out-Null
}

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter test
exit $LASTEXITCODE
