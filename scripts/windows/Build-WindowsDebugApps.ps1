#requires -Version 7.0
# Copyright (c) 2025 Kataglyphis
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Builds the Debug (ASan) app and its integration-test twin in one container, each with the ASan runtime beside it.
.DESCRIPTION
    Only the Dart entrypoint differs, so the second build reuses the first's CMake tree and cargo target in this
    container and redoes little more than Flutter's assemble; a container of its own rebuilt all 520 targets
    (11:45 of 14.9 min in run 38711050047). The plain app is copied to <runner>-app first, for the launch smoke;
    the integration app ends at <runner>, where Invoke-WindowsIntegrationTest.ps1 drives it.
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'clangcl-debug',
    [string]$RunnerDir = 'build\windows\x64\runner\x64-ClangCL-Windows-Debug',
    [string]$FlutterTarget = 'integration_test/simple_test.dart'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runner = Join-Path $repoRoot $RunnerDir
$app = "$runner-app"
$build = Join-Path $PSScriptRoot 'Build-Windows.ps1'
# Format and docs ran in the Release job; the Dart gates run once here, with the plain app.
$common = @('-Configurations', $Configuration, '-SkipMsixPackaging', '-SkipFormat', '-SkipDocs')

& pwsh -NoProfile -ExecutionPolicy Bypass -File $build @common
if ($LASTEXITCODE) { throw "the Debug build failed (exit $LASTEXITCODE)" }
if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
Copy-Item -LiteralPath $runner -Destination $app -Recurse
Write-Host "kept the Debug app as $app for the launch smoke"

& pwsh -NoProfile -ExecutionPolicy Bypass -File $build @common -SkipTests -FlutterTarget $FlutterTarget
if ($LASTEXITCODE) { throw "the integration build failed (exit $LASTEXITCODE)" }

foreach ($dir in $app, $runner) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Stage-AsanRuntime.ps1') -Destination $dir
    if ($LASTEXITCODE) { throw "staging the ASan runtime into $dir failed (exit $LASTEXITCODE)" }
}
