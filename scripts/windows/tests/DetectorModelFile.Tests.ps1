#requires -Version 7.0

Describe 'The default detector file names come from the model lock' {
    BeforeAll {
        $script:reader = Join-Path $PSScriptRoot '..\Get-DetectorModelFile.ps1'
        $script:rows = {
            param([string[]]$Names)
            $Names | ForEach-Object { "$('0' * 64)  $_  https://example.invalid/$_" }
        }
    }

    BeforeEach { $script:lock = Join-Path $TestDrive 'models.lock' }

    It 'the lock of this pin names a model with its license and notice' {
        $files = @(& $script:reader)
        $files.Count | Should -Be 3
        $files[0] | Should -Match '\.onnx$'
        $stem = [IO.Path]::GetFileNameWithoutExtension($files[0])
        $files[1] | Should -Be "$stem.LICENSE"
        $files[2] | Should -Be "$stem.NOTICE"
    }

    It 'follows a lock that names a different model file, skipping comments' {
        Set-Content -LiteralPath $script:lock -Value (@('# sha256 file url', '') + (& $script:rows @('other.LICENSE', 'other.onnx', 'other.NOTICE')))
        $files = @(& $script:reader -Lock $script:lock)
        ($files -join ',') | Should -Be 'other.onnx,other.LICENSE,other.NOTICE'
    }

    It 'refuses a lock without a model, a missing notice and a missing lock' {
        Set-Content -LiteralPath $script:lock -Value (& $script:rows @('other.LICENSE', 'other.NOTICE'))
        { & $script:reader -Lock $script:lock } | Should -Throw -ExpectedMessage '*no .onnx model*'
        Set-Content -LiteralPath $script:lock -Value (& $script:rows @('other.onnx', 'other.LICENSE'))
        { & $script:reader -Lock $script:lock } | Should -Throw -ExpectedMessage '*other.NOTICE*'
        { & $script:reader -Lock (Join-Path $TestDrive 'absent.lock') } | Should -Throw -ExpectedMessage '*Missing model lock*'
    }

    It 'the packaging scripts ask the reader instead of naming the model' {
        foreach ($relative in 'Package-OmniAccelerANT.ps1', 'Test-OmniAccelerANTInstallers.ps1', 'Test-OnnxSelfCheck.ps1',
            'observant/Test-ObservANTMsix.ps1', 'observant/Test-ObservANTWindows.ps1') {
            (Get-Content -Raw (Join-Path $PSScriptRoot "..\$relative")) | Should -Match 'Get-DetectorModelFile\.ps1'
        }
    }
}
