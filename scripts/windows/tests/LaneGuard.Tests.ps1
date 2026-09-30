#requires -Version 7.0

# Tests the pure halves; the engine calls only wrap them. Pester 3.4.0 dialect, as OrtRunner.Tests.ps1.

Describe 'WindowsLaneGuard.Common' {

    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule 'WindowsLaneGuard.Common'

    It 'reports every other Linux lane and never the caller itself' {
        $r = @(Select-LinuxLaneConflict -Self 'kataglyphis-linux-lane-native-x64' -RunningNames @(
                'kataglyphis-linux-lane-native-x64',
                'kataglyphis-linux-lane-android-x64',
                'kataglyphis-linux-lane-web-x64'))
        $r.Count | Should Be 2
        ($r -contains 'kataglyphis-linux-lane-native-x64') | Should Be $false
    }

    It 'ignores containers that are not lanes' {
        @(Select-LinuxLaneConflict -RunningNames @('buildkitd', 'renovate', 'omniaccelerant-agentic-build')).Count | Should Be 0
    }

    It 'reports every Linux lane when the caller is not one (the Windows build)' {
        @(Select-LinuxLaneConflict -RunningNames @('kataglyphis-linux-lane-web-x64')).Count | Should Be 1
    }

    It 'reads an idle reusable container as not building' {
        $idle = @(
            'Name                PID   CPU   Private Working Set',
            'smss.exe            4312  00:00:00.031  270.3kB',
            'cmd.exe             5520  00:00:00.015  1.2MB',
            'PING.EXE            6184  00:00:00.000  897kB')
        Test-ActiveBuildProcess -ProcessLines $idle | Should Be $false
    }

    It 'reads a pwsh process as a running build' {
        $busy = @(
            'Name                PID   CPU   Private Working Set',
            'PING.EXE            6184  00:00:00.000  897kB',
            'pwsh.exe            7020  00:01:12.500  210MB')
        Test-ActiveBuildProcess -ProcessLines $busy | Should Be $true
    }

    It 'does not take a name that merely contains pwsh for a build' {
        Test-ActiveBuildProcess -ProcessLines @('notpwsh.exe  1  00:00:00  1kB') | Should Be $false
    }

    It 'treats an empty listing as idle' {
        Test-ActiveBuildProcess -ProcessLines @() | Should Be $false
    }
}
