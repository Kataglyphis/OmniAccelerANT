#requires -Version 7.0
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
# NOT covered: a Flutter build or DLL bytes; the Windows import walk checks the packaged app.

Describe 'Windows Flutter optional JNI' {
    function Assert-JniDiscoveryDisabled([string]$Text) {
        $active = ($Text -split "`n" | Where-Object { $_ -notmatch '^[ \t]*#' }) -join "`n"
        $guard = [regex]::Matches($active, '(?m)^[ \t]*set\s*\(\s*CMAKE_DISABLE_FIND_PACKAGE_JNI\s+TRUE\s*\)')
        $plugins = [regex]::Matches($active, '(?m)^[ \t]*include\s*\(\s*flutter/generated_plugins\.cmake\s*\)')
        $guard.Count | Should Be 1
        $plugins.Count | Should Be 1
        ($guard[0].Index -lt $plugins[0].Index) | Should Be $true
    }

    It 'disables optional JNI before the generated Windows plugins' {
        $cmake = Join-Path $PSScriptRoot '..\..\..\windows\CMakeLists.txt'
        Assert-JniDiscoveryDisabled ([IO.File]::ReadAllText($cmake))
    }

    It 'rejects absent, disabled, commented, or late JNI guards' {
        $guard = 'set(CMAKE_DISABLE_FIND_PACKAGE_JNI TRUE)'
        $plugins = 'include(flutter/generated_plugins.cmake)'
        Assert-JniDiscoveryDisabled "$guard`n$plugins"
        foreach ($bad in @(
            $plugins,
            "set(CMAKE_DISABLE_FIND_PACKAGE_JNI FALSE)`n$plugins",
            "# $guard`n$plugins",
            "$plugins`n$guard"
        )) {
            $threw = $false
            try { Assert-JniDiscoveryDisabled $bad } catch { $threw = $true }
            $threw | Should Be $true
        }
    }
}
