#requires -Version 7.0

# Pester 3.4.0 dialect: no BeforeAll outside Describe, dash-less Should, no `Should Throw` under pwsh 7.

Describe 'WindowsOrtRunner.Common' {

    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsOrtRunner.Common', 'WindowsGpuBuild.Common', 'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common', 'WindowsOrtLicense.Common')
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
        $wheels = Join-Path $case 'onnx\wheels'
        New-OrtCaseWheel -Path (Join-Path $wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl') -Dll (Join-Path $bin 'onnxruntime.dll')
        return [pscustomobject]@{ Root = (Join-Path $case 'onnx'); Runner = $runner; Wheels = $wheels }
    }

    # The image's chain wheel: the core DLL's exact bytes beside ORT's own two texts.
    function New-OrtCaseWheel([string] $Path, [string] $Dll, [string] $Notice = 'chain notices', [string[]] $ProviderDll = @()) {
        $tree = "$Path.tree"
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $tree 'onnxruntime\capi'), (Split-Path $Path -Parent)
        Copy-Item -LiteralPath $Dll -Destination (Join-Path $tree 'onnxruntime\capi\onnxruntime.dll')
        foreach ($provider in $ProviderDll) { Copy-Item -LiteralPath $provider -Destination (Join-Path $tree 'onnxruntime\capi') }
        [IO.File]::WriteAllText((Join-Path $tree 'onnxruntime\LICENSE'), 'chain MIT text')
        [IO.File]::WriteAllText((Join-Path $tree 'onnxruntime\ThirdPartyNotices.txt'), $Notice)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($tree, $Path)
        Remove-Item -LiteralPath $tree -Recurse -Force
    }

    function Invoke-WithOnnxRoot([string] $Root, [scriptblock] $Block) {
        $saved = $env:ONNX_ROOT, $env:PYTHON_WHEELS
        $env:ONNX_ROOT = $Root
        $env:PYTHON_WHEELS = Join-Path $Root 'wheels'
        try { & $Block } finally { $env:ONNX_ROOT, $env:PYTHON_WHEELS = $saved }
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

    It 're-proves GPU delivery and rejects stale executables, Rust binaries, ORT and CUDA leftovers' {
        $c = New-Case 'gpu-delivery'
        New-OrtTestPe -Path (Join-Path $c.Runner 'omni_accelerant.exe') -Text 'OMNI_ACCELERANT_GPU_VARIANT_directml_V1'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            $null = Invoke-RunnerOrtProof -RunnerDir $c.Runner
        }
        Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $c.Runner -Provider directml } | Should Match 'UNPROVEN'
        Get-ThrowText { Assert-WindowsInstallerCandidate -RunnerDir $c.Runner -Provider directml -Arch x64 } | Should Match 'UNPROVEN'
        if (-not (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('DirectMlDll')) { return }
        Invoke-WithOnnxRoot $c.Root {
            Remove-Item -LiteralPath (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl')
            New-OrtCaseWheel -Path (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl') -Dll (Join-Path $c.Root 'bin\onnxruntime.dll') -ProviderDll @((Join-Path $c.Root 'bin\onnxruntime_providers_shared.dll'), (Join-Path $c.Root 'bin\DirectML.dll'))
            $null = Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider 'onnxruntime_providers_shared.dll'
            Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $c.Runner -Provider directml } | Should Match 'UNPROVEN DirectML'
            $null = Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider 'onnxruntime_providers_shared.dll' -RequireDirectMl
        }
        $hostDir = Join-Path $TestDrive 'gpu-delivery-host'
        Copy-Item -LiteralPath $c.Runner -Destination $hostDir -Recurse
        Invoke-WithOnnxRoot (Join-Path $TestDrive 'no-image') {
            Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $hostDir -Provider directml } | Should Be ''
            Get-ThrowText { Assert-WindowsInstallerCandidate -RunnerDir $hostDir -Provider directml -Arch x64 } | Should Be ''
            New-OrtTestPe -Path (Join-Path $hostDir 'DirectML.dll') -Text 'tampered DirectML'
            Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $hostDir -Provider directml } | Should Match 'CHANGED .*DirectML'
            Copy-Item -LiteralPath (Join-Path $c.Runner 'DirectML.dll') -Destination $hostDir -Force
            Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $hostDir -Provider cuda } | Should Match 'not the requested'
            New-OrtTestPe -Path (Join-Path $hostDir 'omni_accelerant.exe') -Text 'old'
            Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $hostDir -Provider directml } | Should Match 'stale or incomplete omni_accelerant'
            Copy-Item -LiteralPath (Join-Path $c.Runner 'omni_accelerant.exe') -Destination $hostDir -Force
            New-OrtTestPe -Path (Join-Path $hostDir 'oxidant.dll') -Text 'old'
            Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $hostDir -Provider directml } | Should Match 'stale or incomplete oxidant'
            Copy-Item -LiteralPath (Join-Path $c.Runner 'oxidant.dll') -Destination $hostDir -Force
            New-OrtTestPe -Path (Join-Path $hostDir 'onnxruntime_providers_cuda.dll') -Text 'stale CUDA'
            Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $hostDir -Provider directml } | Should Match 'stale CUDA provider'
            Remove-Item -LiteralPath (Join-Path $hostDir 'onnxruntime_providers_cuda.dll')
            New-OrtTestPe -Path (Join-Path $hostDir 'onnxruntime.dll') -Text 'different ORT'
            Get-ThrowText { Assert-WindowsGpuDelivery -SourceDir $c.Runner -DestinationDir $hostDir -Provider directml } | Should Match 'CHANGED .*onnxruntime'
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

    It 'requires provider-capable wheel verification before stamping CUDA' {
        $c = New-Case 'cuda-provider'
        $name = 'onnxruntime_providers_cuda.dll'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider $name } | Should Match 'MISSING required ONNX Runtime provider'
            New-OrtTestPe -Path (Join-Path $c.Root "bin\$name") -Text "$chainSrc`0CUDA provider"
            Copy-Item -LiteralPath (Join-Path $c.Root "bin\$name") -Destination $c.Runner
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'STRAY .*onnxruntime_providers_cuda'
            if (-not (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('ProviderDll')) {
                Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider $name } | Should Match 'cannot verify provider DLLs'
                return
            }
            Remove-Item -LiteralPath (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl')
            New-OrtCaseWheel -Path (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl') -Dll (Join-Path $c.Root 'bin\onnxruntime.dll') -ProviderDll @((Join-Path $c.Root 'bin\onnxruntime_providers_shared.dll'), (Join-Path $c.Root "bin\$name"))
            New-OrtTestPe -Path (Join-Path $c.Runner $name) -Text "$chainSrc`0stale CUDA provider"
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider $name } | Should Match 'STALE .*onnxruntime_providers_cuda'
            Copy-Item -LiteralPath (Join-Path $c.Root "bin\$name") -Destination $c.Runner -Force
            $proof = Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider $name
            $proof.Stamp.sha256.ContainsKey($name) | Should Be $true
            @($proof.Stamp.verified_providers) -contains $name | Should Be $true
        }
        if ((Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('ProviderDll')) { Invoke-WithOnnxRoot (Join-Path $TestDrive 'no-image') {
            Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner -RequiredProvider @('onnxruntime_providers_shared.dll', $name) } | Should Be ''
            $stampPath = Join-Path $c.Runner 'ort-chain-stamp.json'
            $stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json -AsHashtable
            $stamp['verified_providers'] = @('onnxruntime_providers_shared.dll')
            $stamp | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stampPath -Encoding utf8
            Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner -RequiredProvider $name } | Should Match 'UNPROVEN'
            $stamp['verified_providers'] = @('onnxruntime_providers_shared.dll', $name)
            $stamp | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stampPath -Encoding utf8
            New-OrtTestPe -Path (Join-Path $c.Runner $name) -Text 'tampered CUDA provider'
            Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'CHANGED .*onnxruntime_providers_cuda'
            Remove-Item -LiteralPath (Join-Path $c.Runner $name)
            Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner } | Should Match 'MISSING .*onnxruntime_providers_cuda'
        } }
    }

    It 'requires the DirectML bridge from the core wheel before stamping' {
        $c = New-Case 'directml-bridge'
        $name = 'onnxruntime_providers_shared.dll'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            if (-not (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('ProviderDll')) {
                Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider $name } | Should Match 'cannot verify provider DLLs'
                return
            }
            Remove-Item -LiteralPath (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl')
            $wrong = Join-Path $c.Root "wrong\$name"
            New-OrtTestPe -Path $wrong -Text 'wrong provider bridge'
            New-OrtCaseWheel -Path (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl') -Dll (Join-Path $c.Root 'bin\onnxruntime.dll') -ProviderDll $wrong
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider $name } | Should Match 'differs from the matching wheel'
            Remove-Item -LiteralPath (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl')
            New-OrtCaseWheel -Path (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl') -Dll (Join-Path $c.Root 'bin\onnxruntime.dll') -ProviderDll (Join-Path $c.Root "bin\$name")
            $proof = Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequiredProvider $name
            $proof.Stamp.sha256.ContainsKey($name) | Should Be $true
        }
    }

    It 'requires the DirectML runtime from the core wheel before marking it verified' {
        $c = New-Case 'directml-wheel'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            if (-not (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('DirectMlDll')) {
                Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequireDirectMl } | Should Match 'cannot verify DirectML'
                return
            }
            Remove-Item -LiteralPath (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl')
            New-OrtCaseWheel -Path (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl') -Dll (Join-Path $c.Root 'bin\onnxruntime.dll')
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequireDirectMl } | Should Match 'matched 0 entries'
            Remove-Item -LiteralPath (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl')
            $wrong = Join-Path $c.Root 'wrong\DirectML.dll'
            New-OrtTestPe -Path $wrong -Text 'wrong directml'
            New-OrtCaseWheel -Path (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl') -Dll (Join-Path $c.Root 'bin\onnxruntime.dll') -ProviderDll $wrong
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequireDirectMl } | Should Match 'DirectML runtime differs'
            Remove-Item -LiteralPath (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl')
            New-OrtCaseWheel -Path (Join-Path $c.Wheels 'onnxruntime-1.31.0-cp315-cp315-win_amd64.whl') -Dll (Join-Path $c.Root 'bin\onnxruntime.dll') -ProviderDll (Join-Path $c.Root 'bin\DirectML.dll')
            $proof = Invoke-RunnerOrtProof -RunnerDir $c.Runner -RequireDirectMl
            $proof.Stamp.verified_directml | Should Be $true
            Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner -RequireDirectMl } | Should Be ''
            $stampPath = Join-Path $c.Runner 'ort-chain-stamp.json'
            $stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json -AsHashtable
            $stamp['verified_directml'] = 'true'
            $stamp | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stampPath -Encoding utf8
            Get-ThrowText { Assert-RunnerOrtStamp -RunnerDir $c.Runner -RequireDirectMl } | Should Match 'UNPROVEN DirectML'
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

    It 'stages the wheel-matched texts in the image and re-checks their stamped bytes on a host (mutation)' {
        $c = New-Case 'licenses'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            $null = Invoke-RunnerOrtProof -RunnerDir $c.Runner
        }
        Invoke-WithOnnxRoot (Join-Path $TestDrive 'no-image') {
            $dir = Resolve-RunnerOrtLicense -RunnerDir $c.Runner
            $dir | Should Be (Join-Path $c.Runner 'licenses\onnxruntime')
            [IO.File]::ReadAllText((Join-Path $dir 'ThirdPartyNotices.txt')) | Should Be 'chain notices'
            [IO.File]::WriteAllText((Join-Path $dir 'ThirdPartyNotices.txt'), 'edited notices')
            Get-ThrowText { Resolve-RunnerOrtLicense -RunnerDir $c.Runner } | Should Match 'CHANGED .*ThirdPartyNotices'
            [IO.File]::WriteAllText((Join-Path $dir 'ThirdPartyNotices.txt'), 'chain notices')
            Remove-Item -LiteralPath (Join-Path $dir 'LICENSE')
            Get-ThrowText { Resolve-RunnerOrtLicense -RunnerDir $c.Runner } | Should Match 'MISSING .*LICENSE'
            [IO.File]::WriteAllText((Join-Path $dir 'LICENSE'), 'chain MIT text')
            $stamp = Join-Path $c.Runner 'ort-chain-stamp.json'
            $json = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json -AsHashtable
            $json.Remove('licenses')
            $json | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stamp -Encoding utf8
            Get-ThrowText { Resolve-RunnerOrtLicense -RunnerDir $c.Runner } | Should Match 'UNSTAMPED .*license texts'
        }
    }

    It 'refuses in the image a runner ORT that matches no chain wheel, or two (mutation)' {
        $c = New-Case 'wheel-red'
        Invoke-WithOnnxRoot $c.Root {
            $null = Copy-ChainOrtBeside -OnnxRoot $c.Root -Destination $c.Runner
            Remove-Item -Path (Join-Path $c.Wheels '*.whl')
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'matched 0 wheels'
            foreach ($v in '1.31.0', '1.31.1') { New-OrtCaseWheel -Path (Join-Path $c.Wheels "onnxruntime-$v-cp315-cp315-win_amd64.whl") -Dll (Join-Path $c.Root 'bin\onnxruntime.dll') }
            Get-ThrowText { Invoke-RunnerOrtProof -RunnerDir $c.Runner } | Should Match 'matched 2 wheels'
            Test-Path -LiteralPath (Join-Path $c.Runner 'licenses') | Should Be $false
        }
    }

    It 'carries the arm64 proof copy''s matched texts into the natives artifact with its stamp (mutation)' {
        $ast = Get-TestScriptAst -ScriptPath (Join-Path $PSScriptRoot '..\Build-WindowsArm64Natives.ps1')
        $copies = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Copy-Item' -and
                    $n.Extent.Text -match [regex]::Escape("(Join-Path `$proofDir 'licenses') -Destination `$runtime -Recurse") }, $true))
        $copies.Count | Should Be 1
        $proof = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-RunnerOrtProof' }, $true))
        $proof.Count | Should Be 1
        ($copies[0].Extent.StartOffset -gt $proof[0].Extent.StartOffset) | Should Be $true
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
