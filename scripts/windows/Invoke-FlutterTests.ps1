#requires -Version 7.0
<#
.SYNOPSIS
    `flutter test` in each package, counted from the JSON reporter's testDone events rather than the exit code alone.
.DESCRIPTION
    Prints one TESTS: line and, under GitHub Actions, a job summary; fails on any failure or when nothing passed.
.PARAMETER Package
    Package directories, relative to the repo root: the app and the native plugin by default.
#>
[CmdletBinding()]
param(
    [string[]]$Package = @('.', 'packages\kataglyphis_native_inference')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$total = @{ passed = 0; failed = 0; skipped = 0 }
$exits = @()
$empty = @()
foreach ($pkg in $Package) {
    $dir = Join-Path $repoRoot $pkg
    $json = Join-Path ([IO.Path]::GetTempPath()) "flutter-test-$([guid]::NewGuid().ToString('N')).json"
    Push-Location -LiteralPath $dir
    try {
        # The plugin is a path dependency the root resolves, not a resolved package of its own.
        & flutter pub get
        if ($LASTEXITCODE) { throw "flutter pub get failed in $pkg (exit $LASTEXITCODE)." }
        & flutter test --file-reporter "json:$json"
        $exits += $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $json -PathType Leaf)) { throw "flutter test in $pkg wrote no JSON report (exit $($exits[-1]))." }
    $done = @(Get-Content -LiteralPath $json | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.type -eq 'testDone' -and -not $_.hidden })
    Remove-Item -LiteralPath $json -Force
    $skipped = @($done | Where-Object skipped).Count
    $passed = @($done | Where-Object { $_.result -eq 'success' -and -not $_.skipped }).Count
    $failed = @($done | Where-Object { $_.result -ne 'success' }).Count
    "TESTS ($pkg): passed=$passed failed=$failed skipped=$skipped"
    $total.passed += $passed; $total.failed += $failed; $total.skipped += $skipped
    if ($passed -lt 1) { $empty += $pkg }
}

"TESTS: passed=$($total.passed) failed=$($total.failed) skipped=$($total.skipped)"
if ($env:GITHUB_STEP_SUMMARY) {
    "### flutter test ($($Package -join ', '))`n`npassed $($total.passed), failed $($total.failed), skipped $($total.skipped)" |
        Out-File -Append -Encoding utf8 -FilePath $env:GITHUB_STEP_SUMMARY
}
$nonZero = @($exits | Where-Object { $_ })
if ($nonZero.Count -or $total.failed) { throw "flutter test failed (exits $($exits -join ', '), $($total.failed) failed)." }
if ($empty.Count) { throw "No Dart test passed in $($empty -join ', '); a package with nothing tested is not a test verdict." }
