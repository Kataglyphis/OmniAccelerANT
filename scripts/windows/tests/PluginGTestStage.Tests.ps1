#requires -Version 7.0

# Staging only: running the gtest needs flutter_windows.dll, which the Windows lanes provide.
Describe 'Invoke-PluginGTest.ps1 -StageTo' {
    BeforeAll {
        $script:runner = Join-Path $PSScriptRoot '..\Invoke-PluginGTest.ps1'
        $script:leaf = 'plugins\kataglyphis_native_inference'
        function New-BuiltTree([string] $Root, [switch] $NoPdb) {
            $dir = Join-Path $Root $script:leaf
            $null = New-Item -ItemType Directory -Force -Path $dir
            Set-Content -LiteralPath (Join-Path $dir 'kataglyphis_native_inference_test.exe') -Value 'exe'
            if (-not $NoPdb) { Set-Content -LiteralPath (Join-Path $dir 'kataglyphis_native_inference_test.pdb') -Value 'pdb' }
        }
    }

    It 'copies the built exe and its pdb into a tree that -BuildDir can name, and still only builds' {
        $tree = Join-Path $TestDrive 'tree'
        New-BuiltTree $tree
        $stage = Join-Path $TestDrive 'stage'
        $out = & $script:runner -BuildDir $tree -NoRun -StageTo $stage
        $staged = Join-Path $stage $script:leaf
        Get-Content -LiteralPath (Join-Path $staged 'kataglyphis_native_inference_test.exe') | Should -Be 'exe'
        Get-Content -LiteralPath (Join-Path $staged 'kataglyphis_native_inference_test.pdb') | Should -Be 'pdb'
        ($out -join "`n") | Should -Match 'built '
    }

    It 'stages an exe that has no pdb, and refuses a tree with no exe before staging anything' {
        $tree = Join-Path $TestDrive 'bare'
        New-BuiltTree $tree -NoPdb
        $stage = Join-Path $TestDrive 'bare-stage'
        $null = & $script:runner -BuildDir $tree -NoRun -StageTo $stage
        Test-Path -LiteralPath (Join-Path $stage "$script:leaf\kataglyphis_native_inference_test.exe") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $stage "$script:leaf\kataglyphis_native_inference_test.pdb") | Should -BeFalse
        $empty = Join-Path $TestDrive 'empty-stage'
        { & $script:runner -BuildDir (Join-Path $TestDrive 'none') -NoRun -StageTo $empty } | Should -Throw '*build the kataglyphis_native_inference_test target first*'
        Test-Path -LiteralPath $empty | Should -BeFalse
    }
}
