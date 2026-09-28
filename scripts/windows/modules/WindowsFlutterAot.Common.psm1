#requires -Version 7.0

# PROJECT-SPECIFIC: a guard for one failure of this repo's reused Windows build container
# (fixed 2026-09-28; it was a BACKLOG item). The app died at RustLib.init with
# "oxidant's codegen version (2.12.0) should be the same as runtime version (2.13.0)" while
# lib/src/rust/frb_generated.dart read 2.13.0: the runner's data\app.so was an AOT snapshot
# from before the bindings were regenerated, and flutter assemble reported the AOT target up
# to date although it had just written a fresh app.dill. -FreshContainer was the only remedy.
#
# Flutter's Windows release build keeps three copies of the AOT library:
#   .dart_tool\flutter_build\<hash>\app.so   assemble's output, beside the app.dill it compiles
#   build\windows\app.so                     windows_aot_bundle's copy (CMake's AOT_LIBRARY)
#   <runner>\data\app.so                     what CMake installs and the exe loads
# Fresh means: the assemble output is not older than its kernel, and the other two copies are
# the same bytes. A Debug runner has no data\app.so (JIT) and is not graded.

Set-StrictMode -Version Latest

function Get-FlutterAotBuildDir {
    # The assemble directory that holds the newest kernel: the one the build that just ran wrote.
    param([Parameter(Mandatory)][string] $DartToolDir)

    $root = Join-Path $DartToolDir 'flutter_build'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    $newest = Get-ChildItem -LiteralPath $root -Directory |
        ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'app.dill') -ErrorAction SilentlyContinue } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($newest) { return $newest.Directory.FullName }
    return $null
}

function Get-FlutterAotStaleness {
    # Every reason the installed AOT snapshot cannot be trusted; empty when it is fresh or
    # when the runner carries none (Debug).
    param(
        [Parameter(Mandatory)][string] $DartToolDir,
        [Parameter(Mandatory)][string] $RunnerDataDir,
        [string] $AotLibrary = ''
    )

    $installed = Join-Path $RunnerDataDir 'app.so'
    if (-not (Test-Path -LiteralPath $installed -PathType Leaf)) { return @() }

    $reasons = [System.Collections.Generic.List[string]]::new()
    $buildDir = Get-FlutterAotBuildDir -DartToolDir $DartToolDir
    if (-not $buildDir) {
        $reasons.Add("no app.dill under $DartToolDir\flutter_build, so the installed $installed has no kernel to be checked against")
        return @($reasons)
    }

    $dill = Get-Item -LiteralPath (Join-Path $buildDir 'app.dill')
    $assembled = Join-Path $buildDir 'app.so'
    if (-not (Test-Path -LiteralPath $assembled -PathType Leaf)) {
        $reasons.Add("assemble wrote $($dill.FullName) but no app.so beside it")
        return @($reasons)
    }
    $so = Get-Item -LiteralPath $assembled
    if ($so.LastWriteTimeUtc -lt $dill.LastWriteTimeUtc) {
        $reasons.Add("$assembled ($($so.LastWriteTimeUtc.ToString('o'))) is older than its kernel $($dill.FullName) ($($dill.LastWriteTimeUtc.ToString('o')))")
    }

    $want = (Get-FileHash -LiteralPath $assembled -Algorithm SHA256).Hash
    $copies = @($installed)
    if ($AotLibrary -and (Test-Path -LiteralPath $AotLibrary -PathType Leaf)) { $copies = @($AotLibrary) + $copies }
    foreach ($copy in $copies) {
        if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $want) {
            $reasons.Add("$copy is not the bytes of $assembled")
        }
    }
    return @($reasons)
}

function Reset-FlutterAotOutput {
    # Removes the AOT outputs and the stamps that let assemble skip the AOT targets, so the
    # next build recompiles app.so from the current kernel. Returns what it removed.
    param(
        [Parameter(Mandatory)][string] $DartToolDir,
        [string] $AotLibrary = ''
    )

    # Only the directory the grade read: another preset's assemble tree is not touched.
    $removed = [System.Collections.Generic.List[string]]::new()
    $buildDir = Get-FlutterAotBuildDir -DartToolDir $DartToolDir
    if ($buildDir) {
        Get-ChildItem -LiteralPath $buildDir -File |
            Where-Object { $_.Name -eq 'app.so' -or $_.Name -like 'aot_*.stamp' -or $_.Name -like '*_aot_bundle.stamp' } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force
                $removed.Add($_.FullName)
            }
    }
    if ($AotLibrary -and (Test-Path -LiteralPath $AotLibrary -PathType Leaf)) {
        Remove-Item -LiteralPath $AotLibrary -Force
        $removed.Add($AotLibrary)
    }
    return @($removed)
}

Export-ModuleMember -Function Get-FlutterAotBuildDir, Get-FlutterAotStaleness, Reset-FlutterAotOutput
