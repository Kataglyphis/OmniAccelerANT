#requires -Version 7.0

# Byte fixtures in flutter assemble's layout; Pester 3.4.0 dialect, as OrtRunner.Tests.ps1.

Describe 'WindowsFlutterAot.Common' {

    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule 'WindowsFlutterAot.Common'

    function Set-Fixture([string] $Path, [string] $Text, [datetime] $When) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
        [System.IO.File]::WriteAllText($Path, $Text)
        (Get-Item -LiteralPath $Path).LastWriteTimeUtc = $When
    }

    # A release build as assemble leaves it: kernel, then its AOT, then the two copies.
    function New-Case([string] $Name) {
        $root = Join-Path $TestDrive $Name
        $t0 = [datetime]::new(2026, 9, 28, 12, 0, 0, [DateTimeKind]::Utc)
        $hash = Join-Path $root '.dart_tool\flutter_build\1142b07edff49bef8d41ef14b1204cb5'
        Set-Fixture (Join-Path $hash 'app.dill') 'kernel v2' $t0
        Set-Fixture (Join-Path $hash 'app.so') 'aot v2' $t0.AddSeconds(14)
        Set-Fixture (Join-Path $hash 'aot_elf_release.stamp') '{}' $t0.AddSeconds(14)
        Set-Fixture (Join-Path $hash 'windows_aot_bundle.stamp') '{}' $t0.AddSeconds(15)
        Set-Fixture (Join-Path $hash 'kernel_snapshot_program.stamp') '{}' $t0
        Set-Fixture (Join-Path $root 'build\windows\app.so') 'aot v2' $t0.AddSeconds(15)
        Set-Fixture (Join-Path $root 'runner\data\app.so') 'aot v2' $t0.AddSeconds(20)
        return [pscustomobject]@{
            DartTool = Join-Path $root '.dart_tool'
            Hash     = $hash
            Lib      = Join-Path $root 'build\windows\app.so'
            Data     = Join-Path $root 'runner\data'
            T0       = $t0
        }
    }

    It 'passes a fresh release build' {
        $c = New-Case 'fresh'
        @(Get-FlutterAotStaleness -DartToolDir $c.DartTool -RunnerDataDir $c.Data -AotLibrary $c.Lib).Count | Should Be 0
    }

    It 'does not grade a JIT (Debug) runner, which has no data\app.so' {
        $c = New-Case 'debug'
        Remove-Item -LiteralPath (Join-Path $c.Data 'app.so')
        @(Get-FlutterAotStaleness -DartToolDir $c.DartTool -RunnerDataDir $c.Data -AotLibrary $c.Lib).Count | Should Be 0
    }

    It 'catches the incident: a fresh kernel beside an AOT snapshot from before it' {
        $c = New-Case 'incident'
        Set-Fixture (Join-Path $c.Hash 'app.dill') 'kernel v3' $c.T0.AddMinutes(10)
        $r = @(Get-FlutterAotStaleness -DartToolDir $c.DartTool -RunnerDataDir $c.Data -AotLibrary $c.Lib)
        $r.Count | Should Be 1
        ($r[0] -match 'older than its kernel') | Should Be $true
    }

    It 'catches an installed copy that is not the assembled bytes' {
        $c = New-Case 'installed'
        Set-Fixture (Join-Path $c.Data 'app.so') 'aot v1' $c.T0.AddSeconds(20)
        $r = @(Get-FlutterAotStaleness -DartToolDir $c.DartTool -RunnerDataDir $c.Data -AotLibrary $c.Lib)
        $r.Count | Should Be 1
        ($r[0] -match 'runner\\data\\app\.so is not the bytes') | Should Be $true
    }

    It 'catches a stale CMake AOT_LIBRARY copy' {
        $c = New-Case 'aotlib'
        Set-Fixture $c.Lib 'aot v1' $c.T0.AddSeconds(15)
        $r = @(Get-FlutterAotStaleness -DartToolDir $c.DartTool -RunnerDataDir $c.Data -AotLibrary $c.Lib)
        ($r -join ' ') -match 'build\\windows\\app\.so is not the bytes' | Should Be $true
    }

    It 'grades against the newest kernel when several presets left assemble trees' {
        $c = New-Case 'presets'
        $other = Join-Path $c.DartTool 'flutter_build\0000000000000000000000000000beef'
        Set-Fixture (Join-Path $other 'app.dill') 'profile kernel' $c.T0.AddMinutes(-30)
        Set-Fixture (Join-Path $other 'app.so') 'profile aot' $c.T0.AddMinutes(-29)
        Get-FlutterAotBuildDir -DartToolDir $c.DartTool | Should Be $c.Hash
        @(Get-FlutterAotStaleness -DartToolDir $c.DartTool -RunnerDataDir $c.Data -AotLibrary $c.Lib).Count | Should Be 0
    }

    It 'reports an AOT runner with no kernel to check against' {
        $c = New-Case 'nokernel'
        Remove-Item -LiteralPath (Join-Path $c.DartTool 'flutter_build') -Recurse
        $r = @(Get-FlutterAotStaleness -DartToolDir $c.DartTool -RunnerDataDir $c.Data -AotLibrary $c.Lib)
        ($r[0] -match 'no app.dill') | Should Be $true
    }

    It 'reset removes the AOT outputs and their stamps, and leaves the kernel and other presets' {
        $c = New-Case 'reset'
        $other = Join-Path $c.DartTool 'flutter_build\0000000000000000000000000000beef'
        Set-Fixture (Join-Path $other 'app.dill') 'profile kernel' $c.T0.AddMinutes(-30)
        Set-Fixture (Join-Path $other 'app.so') 'profile aot' $c.T0.AddMinutes(-29)
        $removed = @(Reset-FlutterAotOutput -DartToolDir $c.DartTool -AotLibrary $c.Lib)
        $removed.Count | Should Be 4
        Test-Path -LiteralPath (Join-Path $c.Hash 'app.so') | Should Be $false
        Test-Path -LiteralPath (Join-Path $c.Hash 'aot_elf_release.stamp') | Should Be $false
        Test-Path -LiteralPath (Join-Path $c.Hash 'windows_aot_bundle.stamp') | Should Be $false
        Test-Path -LiteralPath $c.Lib | Should Be $false
        Test-Path -LiteralPath (Join-Path $c.Hash 'app.dill') | Should Be $true
        Test-Path -LiteralPath (Join-Path $c.Hash 'kernel_snapshot_program.stamp') | Should Be $true
        Test-Path -LiteralPath (Join-Path $other 'app.so') | Should Be $true
    }
}
