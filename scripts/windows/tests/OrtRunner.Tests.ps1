#requires -Version 7.0

# WindowsOrtRunner.Common: the runner carries the image's chain-built ONNX Runtime and nothing else
# (owner rule 2026-09-23), staged by the hub's WindowsOrtPayload.Common, proved by its G6 census at build
# time and re-proved at launch against the stamped copy. The DLLs are byte fixtures behind an amd64 PE
# header, which the hub's staging checks; the chain is a TestDrive ONNX_ROOT, G6's reference.
# NOTE: Pester 3.4.0 dialect, as OxidANT's and AccelerANTgine's suites - no BeforeAll outside
# Describe, dash-less Should, and no `Should Throw` under pwsh 7. CI: windows-x64.yml's
# ort-runner-suite job. Locally: pwsh -c "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester scripts/windows/tests"

Describe 'WindowsOrtRunner.Common' {

    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsOrtRunner.Common', 'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common')

    # A fake __FILE__ path ends in NUL, as a compiler writes it: G6 takes only a whole NUL-terminated
    # ORT source path as a fingerprint (hub fix of 2026-09-24), so "$chainSrc text" would be none.
    $chainSrc = 'C:\temp\onnx-src\onnxruntime\core\session\inference_session.cc'
    $foreignSrc = 'C:\__w\1\s\onnxruntime\core\session\inference_session.cc'

    # MZ, e_lfanew = 0x40, 'PE\0\0', machine amd64: enough for Get-PeFileMachine; the text follows.
    function New-FakeDll([string] $Path, [string] $Text) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
        $h = [byte[]]::new(0x80)
        $h[0] = 0x4D; $h[1] = 0x5A; $h[0x3C] = 0x40; $h[0x40] = 0x50; $h[0x41] = 0x45; $h[0x44] = 0x64; $h[0x45] = 0x86
        [System.IO.File]::WriteAllBytes($Path, [byte[]]($h + [System.Text.Encoding]::Latin1.GetBytes("`0$Text`0")))
    }

    function Get-ThrowText([scriptblock] $Block) {
        try { & $Block | Out-Null } catch { return "$($_.Exception.Message)" }
        return ''
    }

    # A chain ONNX_ROOT, and a runner whose exe hosts AccelerANTgine.dll and oxidant.dll (both use ORT).
    function New-Case([string] $Name) {
        $case = Join-Path $TestDrive $Name
        $bin = Join-Path $case 'onnx\bin'
        New-FakeDll (Join-Path $bin 'onnxruntime.dll') "$chainSrc`0OrtGetApiBase"
        New-FakeDll (Join-Path $bin 'onnxruntime_providers_shared.dll') 'provider bridge'
        New-FakeDll (Join-Path $bin 'DirectML.dll') 'directml'
        $runner = Join-Path $case 'runner'
        New-FakeDll (Join-Path $runner 'omni_accelerant.exe') 'main'
        New-FakeDll (Join-Path $runner 'AccelerANTgine.dll') 'OrtGetApiBase'
        New-FakeDll (Join-Path $runner 'oxidant.dll') 'OrtGetApiBase'
        return [pscustomobject]@{ Root = (Join-Path $case 'onnx'); Runner = $runner }
    }

    function Invoke-WithOnnxRoot([string] $Root, [scriptblock] $Block) {
        $saved = $env:ONNX_ROOT
        $env:ONNX_ROOT = $Root
        try { & $Block } finally { $env:ONNX_ROOT = $saved }
    }

    It 'stages the chain ORT over stale copies, proves it with G6 and re-proves the stamp on a host' {
        $c = New-Case 'green'
        New-FakeDll (Join-Path $c.Runner 'onnxruntime.dll') $foreignSrc
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
            New-FakeDll (Join-Path $c.Runner 'onnxruntime.dll') $foreignSrc
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'FOREIGN'
            New-FakeDll (Join-Path $c.Runner 'onnxruntime.dll') "$chainSrc`0FileVersion 1.27.0"
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'STALE'
            Remove-Item -LiteralPath (Join-Path $c.Runner 'onnxruntime.dll')
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'MISSING'
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            New-FakeDll (Join-Path $c.Runner 'gstreamer-1.0\onnxruntime-genai.dll') 'genai'
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
        New-FakeDll (Join-Path $c.Runner 'DirectML.dll') 'other directml'
        Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'CHANGED .*DirectML'
        Copy-Item -LiteralPath (Join-Path $c.Root 'bin\DirectML.dll') -Destination $c.Runner -Force
        New-FakeDll (Join-Path $c.Runner 'onnxruntime_extra.dll') 'extra'
        Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'STRAY .*onnxruntime_extra'
        Remove-Item -LiteralPath (Join-Path $c.Runner 'onnxruntime_extra.dll')
        # A renamed ORT is invisible to the family names; G6 still sees its fingerprint.
        New-FakeDll (Join-Path $c.Runner 'helper.dll') $foreignSrc
        Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'FOREIGN .*helper.dll'
        Remove-Item -LiteralPath (Join-Path $c.Runner 'helper.dll')
        # Stamp and bytes swapped together for an ORT with no source root at all: G6 alone cannot tell.
        New-FakeDll (Join-Path $c.Runner 'onnxruntime.dll') 'OrtGetApiBase no fingerprint'
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
        New-FakeDll $other "$chainSrc`0FileVersion 1.27.0"
        Get-ThrowText { Assert-RunnerOrtOverride -Value $other -ExeDir $c.Runner -RunnerDir $c.Runner } | Should Match 'not the chain ONNX Runtime the build proved'
        Get-ThrowText { Assert-RunnerOrtOverride -Value '' -ExeDir $c.Runner -RunnerDir $c.Runner } | Should Be ''
    }

    It 'wires G6 into MSIX packaging: the packed runner\Release is proved before msix:create (mutation)' {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\Build-Windows.ps1'), [ref] $tokens, [ref] $errors)
        $step = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Invoke-BuildStep' -and $n.Extent.Text -match '-StepName "MSIX Packaging"' }, $true))
        $step.Count | Should Be 1
        $text = $step[0].Extent.Text
        $proof = $text.IndexOf('Invoke-RunnerOrtProof -RunnerDir (Resolve-NormalizedPath -Path (Join-Path $workspace "build/windows/x64/runner/Release"))')
        ($proof -ge 0 -and $proof -lt $text.IndexOf('msix:create')) | Should Be $true
    }

    It 'refuses to stage without a chain ONNX_ROOT' {
        $c = New-Case 'noroot'
        Get-ThrowText { Copy-ChainOrtBeside -OnnxRoot '' -Destination $c.Runner } | Should Match 'ONNX_ROOT is not set'
    }
}
