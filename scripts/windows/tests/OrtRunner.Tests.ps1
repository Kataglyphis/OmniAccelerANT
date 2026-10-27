#requires -Version 7.0

# Pester 3.4.0 dialect: no BeforeAll outside Describe, dash-less Should, no `Should Throw` under pwsh 7.

Describe 'WindowsOrtRunner.Common' {

    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsOrtRunner.Common', 'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common')
    Import-Module (Join-Path $PSScriptRoot '..\..\..\third_party\ANTfrastructure\windows\scripts\tests\TestHarness.psm1') -Function Get-TestScriptAst, New-OrtTestPe -ErrorAction Stop

    # NUL-terminated like a compiler's __FILE__: G6 takes only a whole terminated path as a fingerprint.
    $chainSrc = 'C:\temp\onnx-src\onnxruntime\core\session\inference_session.cc'
    $foreignSrc = 'C:\__w\1\s\onnxruntime\core\session\inference_session.cc'

    function Get-ThrowText([scriptblock] $Block) {
        try { & $Block | Out-Null } catch { return "$($_.Exception.Message)" }
        return ''
    }

    function Get-MsixPackagingStep([string] $ScriptPath = '') {
        $source = if ($ScriptPath) { $ScriptPath } else { Join-Path $PSScriptRoot '..\Build-Windows.ps1' }
        $ast = Get-TestScriptAst -ScriptPath $source
        $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Invoke-BuildStep' -and $n.Extent.Text -match '-StepName "MSIX Packaging"' }, $true)
    }

    # A chain ONNX_ROOT, and a runner whose exe hosts AccelerANTgine.dll and oxidant.dll (both use ORT).
    function New-Case([string] $Name) {
        $case = Join-Path $TestDrive $Name
        $bin = Join-Path $case 'onnx\bin'
        New-OrtTestPe -Path (Join-Path $bin 'onnxruntime.dll') -Text "$chainSrc`0OrtGetApiBase"
        New-OrtTestPe -Path (Join-Path $bin 'onnxruntime_providers_shared.dll') -Text 'provider bridge'
        New-OrtTestPe -Path (Join-Path $bin 'DirectML.dll') -Text 'directml'
        $runner = Join-Path $case 'runner'
        New-OrtTestPe -Path (Join-Path $runner 'omni_accelerant.exe') -Text 'main'
        New-OrtTestPe -Path (Join-Path $runner 'AccelerANTgine.dll') -Text 'OrtGetApiBase'
        New-OrtTestPe -Path (Join-Path $runner 'oxidant.dll') -Text 'OrtGetApiBase'
        return [pscustomobject]@{ Root = (Join-Path $case 'onnx'); Runner = $runner }
    }

    function Invoke-WithOnnxRoot([string] $Root, [scriptblock] $Block) {
        $saved = $env:ONNX_ROOT
        $env:ONNX_ROOT = $Root
        try { & $Block } finally { $env:ONNX_ROOT = $saved }
    }

    It 'stages the chain ORT over stale copies, proves it with G6 and re-proves the stamp on a host' {
        $c = New-Case 'green'
        New-OrtTestPe -Path (Join-Path $c.Runner 'onnxruntime.dll') -Text $foreignSrc
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            $proof = Invoke-RunnerOrtProof -RunnerDir $c.Runner
            @($proof.Stamp.sha256.Keys).Count | Should Be 3
        }
        # The host has no image: the stamped copy is G6's reference.
        Invoke-WithOnnxRoot (Join-Path $TestDrive 'no-image') {
            Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Be ''
            Get-ThrowText { Assert-RunnerOrtOverride -Value 'onnxruntime.dll' -ExeDir $c.Runner -RunnerDir $c.Runner } | Should Be ''
        }
    }

    It 'refuses at build time a foreign, a stale or a missing ORT, and a stray ORT-family file (mutation)' {
        $c = New-Case 'build-red'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            New-OrtTestPe -Path (Join-Path $c.Runner 'onnxruntime.dll') -Text $foreignSrc
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'FOREIGN'
            New-OrtTestPe -Path (Join-Path $c.Runner 'onnxruntime.dll') -Text "$chainSrc`0FileVersion 1.27.0"
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'STALE'
            Remove-Item -LiteralPath (Join-Path $c.Runner 'onnxruntime.dll')
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'MISSING'
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            New-OrtTestPe -Path (Join-Path $c.Runner 'gstreamer-1.0\onnxruntime-genai.dll') -Text 'genai'
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'STRAY .*onnxruntime-genai'
        }
    }

    It 'refuses at launch an unstamped, changed, stray or unfingerprinted runner (mutation)' {
        $c = New-Case 'host-red'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            $null = Invoke-RunnerOrtProof -RunnerDir $c.Runner
        }
        $stamp = Join-Path $c.Runner 'ort-chain-stamp.json'
        $saved = Get-Content -LiteralPath $stamp -Raw
        New-OrtTestPe -Path (Join-Path $c.Runner 'DirectML.dll') -Text 'other directml'
        Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'CHANGED .*DirectML'
        Copy-Item -LiteralPath (Join-Path $c.Root 'bin\DirectML.dll') -Destination $c.Runner -Force
        New-OrtTestPe -Path (Join-Path $c.Runner 'onnxruntime_extra.dll') -Text 'extra'
        Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'STRAY .*onnxruntime_extra'
        Remove-Item -LiteralPath (Join-Path $c.Runner 'onnxruntime_extra.dll')
        # A renamed ORT is invisible to the family names; G6 still sees its fingerprint.
        New-OrtTestPe -Path (Join-Path $c.Runner 'helper.dll') -Text $foreignSrc
        Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'FOREIGN .*helper.dll'
        Remove-Item -LiteralPath (Join-Path $c.Runner 'helper.dll')
        # Stamp and bytes swapped together for an ORT with no source root at all: G6 alone cannot tell.
        New-OrtTestPe -Path (Join-Path $c.Runner 'onnxruntime.dll') -Text 'OrtGetApiBase no fingerprint'
        $sha = (Get-FileHash -LiteralPath (Join-Path $c.Runner 'onnxruntime.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
        $forged = $saved | ConvertFrom-Json -AsHashtable
        $forged['sha256']['onnxruntime.dll'] = $sha
        $forged | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stamp -Encoding utf8
        Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'UNPROVEN'
        Remove-Item -LiteralPath $stamp
        Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'UNSTAMPED'
    }

    It 'lets ORT_DYLIB_PATH name only the proven bytes' {
        $c = New-Case 'override'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            $null = Invoke-RunnerOrtProof -RunnerDir $c.Runner
        }
        $other = Join-Path $TestDrive 'override\sys\onnxruntime.dll'
        New-OrtTestPe -Path $other -Text "$chainSrc`0FileVersion 1.27.0"
        Get-ThrowText { Assert-RunnerOrtOverride -Value $other -ExeDir $c.Runner -RunnerDir $c.Runner } | Should Match 'not the chain ONNX Runtime the build proved'
        Get-ThrowText { Assert-RunnerOrtOverride -Value '' -ExeDir $c.Runner -RunnerDir $c.Runner } | Should Be ''
    }

    It 'wires G6 into MSIX packaging: the packed runner\Release is proved before msix:create (mutation)' {
        $step = @(Get-MsixPackagingStep)
        $step.Count | Should Be 1
        $text = $step[0].Extent.Text
        $proof = $text.IndexOf('Invoke-RunnerOrtProof -RunnerDir (Resolve-NormalizedPath -Path (Join-Path $workspace "build/windows/x64/runner/Release"))')
        ($proof -ge 0 -and $proof -lt $text.IndexOf('msix:create')) | Should Be $true
    }

    It 'rejects malformed build source before inspecting MSIX wiring (mutation)' {
        $broken = Join-Path $TestDrive 'Build-Windows.ps1'
        Set-Content -LiteralPath $broken -Value @('Invoke-BuildStep -StepName "MSIX Packaging" -Script {}', 'if (')
        Get-ThrowText { $null = Get-MsixPackagingStep -ScriptPath $broken } | Should Match 'parse errors'
    }

    It 'refuses to stage without a chain ONNX_ROOT' {
        $c = New-Case 'noroot'
        Get-ThrowText { Copy-ChainOrtBeside -OnnxRoot '' -Destination $c.Runner } | Should Match 'ONNX_ROOT is not set'
    }
}
