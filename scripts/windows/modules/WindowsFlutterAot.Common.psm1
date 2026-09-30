#requires -Version 7.0

# assemble can call a stale AOT target up to date: fresh means its app.so is not older than app.dill and both copies match.

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
    # Every reason the installed snapshot cannot be trusted; empty when fresh or absent (Debug).
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
    # Removes the AOT outputs and the stamps that let assemble skip them; returns what it removed.
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
