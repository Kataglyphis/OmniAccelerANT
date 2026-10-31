#requires -Version 7.0

Describe 'Windows GPU preflight' {
    Import-Module (Join-Path $PSScriptRoot '..\modules\WindowsGpuBuild.Common.psm1') -Force
    $workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    function Get-GpuThrow([scriptblock] $Action) {
        try { $null = & $Action; return '' } catch { return $_.Exception.Message }
    }

    BeforeEach {
        $script:oldCopy = Get-Item Function:\global:Copy-ChainOrtBeside -ErrorAction SilentlyContinue
        $script:oldLicense = Get-Item Function:\global:Copy-OrtWheelLicenses -ErrorAction SilentlyContinue
        $script:oldRuntimeFile = Get-Item Function:\global:Get-ChainOrtRuntimeFile -ErrorAction SilentlyContinue
        $oxidant = Join-Path $TestDrive 'oxidant'
        $bin = Join-Path $TestDrive 'onnx\bin'
        New-Item -ItemType Directory -Force -Path (Join-Path $oxidant 'crates\inference'), $bin | Out-Null
        Set-Content -LiteralPath (Join-Path $oxidant 'crates\inference\Cargo.toml') -Value @('[package.metadata.kataglyphis]', 'ort-devices = ["cuda", "directml"]')
        foreach ($name in 'onnxruntime.dll', 'onnxruntime_providers_shared.dll', 'onnxruntime_providers_cuda.dll', 'DirectML.dll') {
            Set-Content -LiteralPath (Join-Path $bin $name) -Value 'fixture'
        }
        function global:Copy-ChainOrtBeside { param($RequiredProvider) }
        function global:Copy-OrtWheelLicenses { param($ProviderDll, $DirectMlDll) }
        function global:Get-ChainOrtRuntimeFile {
            param($OnnxRoot, $Name)
            foreach ($directory in 'bin', 'lib') {
                $file = Join-Path $OnnxRoot "$directory\$Name"
                if (Test-Path -LiteralPath $file -PathType Leaf) { return $file }
            }
            throw "Required ONNX Runtime DLL $Name is missing from $OnnxRoot"
        }
    }

    AfterEach {
        Remove-Item Function:\global:Copy-ChainOrtBeside, Function:\global:Copy-OrtWheelLicenses, Function:\global:Get-ChainOrtRuntimeFile -ErrorAction SilentlyContinue
        if ($script:oldCopy) { Set-Item Function:\global:Copy-ChainOrtBeside -Value $script:oldCopy.ScriptBlock }
        if ($script:oldLicense) { Set-Item Function:\global:Copy-OrtWheelLicenses -Value $script:oldLicense.ScriptBlock }
        if ($script:oldRuntimeFile) { Set-Item Function:\global:Get-ChainOrtRuntimeFile -Value $script:oldRuntimeFile.ScriptBlock }
    }

    It 'keeps the CPU path independent of the new GPU capabilities' {
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider cpu -Workspace $workspace -OxidantDir 'missing' } | Should Be ''
    }

    It 'requires no built-in MSIX packaging for either GPU provider' {
        Get-GpuThrow { Assert-WindowsGpuPackagingMode -Provider cpu } | Should Be ''
        foreach ($provider in 'cuda', 'directml') {
            Get-GpuThrow { Assert-WindowsGpuPackagingMode -Provider $provider } | Should Match 'require -SkipMsixPackaging'
            Get-GpuThrow { Assert-WindowsGpuPackagingMode -Provider $provider -SkipMsixPackaging } | Should Be ''
        }
    }

    It 'rejects GPU-marked runners and CUDA DLLs before host packaging' {
        $runner = Join-Path $TestDrive 'candidate'
        New-Item -ItemType Directory -Force -Path $runner | Out-Null
        $exe = Join-Path $runner 'omni_accelerant.exe'
        [IO.File]::WriteAllBytes($exe, [Text.Encoding]::ASCII.GetBytes('ordinary CPU runner'))
        Get-GpuThrow { Assert-WindowsInstallerCandidate -RunnerDir $runner } | Should Be ''
        foreach ($provider in 'cuda', 'directml') {
            $bytes = [Text.Encoding]::ASCII.GetBytes(('x' * 65530) + "OMNI_ACCELERANT_GPU_VARIANT_${provider}_V1")
            [IO.File]::WriteAllBytes($exe, $bytes)
            Get-GpuThrow { Assert-WindowsInstallerCandidate -RunnerDir $runner } | Should Match 'GPU-marked runner'
        }
        [IO.File]::WriteAllBytes($exe, [Text.Encoding]::ASCII.GetBytes('ordinary CPU runner'))
        Set-Content -LiteralPath (Join-Path $runner 'onnxruntime_providers_cuda.dll') -Value 'fixture'
        Get-GpuThrow { Assert-WindowsInstallerCandidate -RunnerDir $runner } | Should Match 'CUDA runner'
    }

    It 'checks the executable before creating installer outputs' {
        $packager = Get-Content -LiteralPath (Join-Path $workspace 'scripts\windows\Package-OmniAccelerANT.ps1') -Raw
        $check = $packager.IndexOf('Assert-WindowsInstallerCandidate -RunnerDir $AppDir')
        ($check -ge 0 -and $check -lt $packager.IndexOf('New-AppMsi') -and
            $check -lt $packager.IndexOf('New-AppMsix')) | Should Be $true
    }

    It 'publishes GPU installer candidates only after both finished-package checks' {
        $packager = Get-Content -LiteralPath (Join-Path $workspace 'scripts\windows\Package-OmniAccelerANT.ps1') -Raw
        $msi = $packager.IndexOf('Assert-PackageBinary -Path "$base.msi"')
        $msix = $packager.IndexOf('Assert-PackageBinary -Path "$base.msix"')
        $publish = $packager.IndexOf('Move-Item -LiteralPath $outRoot -Destination $gpuDestination')
        ($msi -ge 0 -and $msi -lt $msix -and $msix -lt $publish) | Should Be $true
        $packager.Contains('unverified-omni-windows-x64-$vendor-installers') | Should Be $true
        $packager.Contains('.pending-omni-$vendor-') | Should Be $true
    }

    It 'accepts only an explicit matching x64 GPU installer candidate' {
        $oldProof = Get-Item Function:\global:Resolve-RunnerOrtLicense -ErrorAction SilentlyContinue
        function global:Resolve-RunnerOrtLicense { param($RunnerDir, $RequiredProvider, [switch]$RequireDirectMl) }
        try {
            $runner = Join-Path $TestDrive 'installer-candidate'
            New-Item -ItemType Directory -Force -Path $runner | Out-Null
            foreach ($name in 'oxidant.dll', 'AccelerANTgine.dll', 'ort-chain-stamp.json', 'onnxruntime_providers_shared.dll', 'DirectML.dll') {
                Set-Content -LiteralPath (Join-Path $runner $name) -Value $name
            }
            Set-Content -LiteralPath (Join-Path $runner 'omni_accelerant.exe') -Value 'OMNI_ACCELERANT_GPU_VARIANT_directml_V1'
            Get-GpuThrow { Assert-WindowsInstallerCandidate -RunnerDir $runner } | Should Match 'GPU-marked runner'
            Get-GpuThrow { Assert-WindowsInstallerCandidate -RunnerDir $runner -Provider directml -Arch arm64 } | Should Match 'require x64'
            Get-GpuThrow { Assert-WindowsInstallerCandidate -RunnerDir $runner -Provider cuda -Arch x64 } | Should Match 'not the requested'
            Get-GpuThrow { Assert-WindowsInstallerCandidate -RunnerDir $runner -Provider directml -Arch x64 } | Should Be ''
            Remove-Item -LiteralPath (Join-Path $runner 'DirectML.dll')
            Get-GpuThrow { Assert-WindowsInstallerCandidate -RunnerDir $runner -Provider directml -Arch x64 } | Should Match 'missing DirectML.dll'
        } finally {
            Remove-Item Function:\global:Resolve-RunnerOrtLicense -ErrorAction SilentlyContinue
            if ($oldProof) { Set-Item Function:\global:Resolve-RunnerOrtLicense -Value $oldProof.ScriptBlock }
        }
    }

    It 'preflights before initializing either compiler cache' {
        $driver = Get-Content -LiteralPath (Join-Path $workspace 'scripts\windows\Build-Windows.ps1') -Raw
        $check = $driver.IndexOf('Assert-WindowsGpuBuild -Provider $OrtProvider')
        ($check -ge 0 -and $check -lt $driver.IndexOf('Initialize-BuildCacheEnvironment') -and
            $check -lt $driver.IndexOf('Restore-CiCompilerCache')) | Should Be $true
    }

    It 'gates every GPU preset after the host sync even when errors may continue' {
        $driver = Get-Content -LiteralPath (Join-Path $workspace 'scripts\windows\Build-Windows.ps1') -Raw
        $sync = $driver.IndexOf('Sync-FastLocalArtifactsToHost -Context')
        $proof = $driver.IndexOf('-StepName "Verify GPU Delivery" -Critical')
        $check = $driver.IndexOf('Assert-WindowsGpuDelivery -SourceDir')
        $fail = $driver.IndexOf('if (-not $gpuDelivered)')
        ($sync -ge 0 -and $sync -lt $proof -and $proof -lt $check -and $check -lt $fail) | Should Be $true
        $driver.Substring($proof, $check - $proof).Contains('foreach ($currentPreset in $presetsToRun)') | Should Be $true
    }

    It 'requires a delivered CUDA provider and re-proves both source and host' {
        $oldProof = Get-Item Function:\global:Resolve-RunnerOrtLicense -ErrorAction SilentlyContinue
        $script:gpuProofPaths = [System.Collections.Generic.List[string]]::new()
        function global:Resolve-RunnerOrtLicense { param($RunnerDir, $RequiredProvider, [switch]$RequireDirectMl) $script:gpuProofPaths.Add($RunnerDir) }
        try {
            $source = Join-Path $TestDrive 'cuda-source'
            $hostDir = Join-Path $TestDrive 'cuda-host'
            New-Item -ItemType Directory -Force -Path $source, $hostDir | Out-Null
            foreach ($name in 'omni_accelerant.exe', 'oxidant.dll', 'AccelerANTgine.dll', 'ort-chain-stamp.json', 'onnxruntime_providers_shared.dll', 'onnxruntime_providers_cuda.dll') {
                $content = if ($name -eq 'omni_accelerant.exe') { 'OMNI_ACCELERANT_GPU_VARIANT_cuda_V1' } else { $name }
                Set-Content -LiteralPath (Join-Path $source $name) -Value $content
                Copy-Item -LiteralPath (Join-Path $source $name) -Destination $hostDir
            }
            Get-GpuThrow { Assert-WindowsGpuDelivery -SourceDir $source -DestinationDir $hostDir -Provider cuda } | Should Be ''
            @($script:gpuProofPaths).Count | Should Be 2
            Remove-Item -LiteralPath (Join-Path $hostDir 'onnxruntime_providers_cuda.dll')
            Get-GpuThrow { Assert-WindowsGpuDelivery -SourceDir $source -DestinationDir $hostDir -Provider cuda } | Should Match 'missing the CUDA provider'
        } finally {
            Remove-Item Function:\global:Resolve-RunnerOrtLicense -ErrorAction SilentlyContinue
            if ($oldProof) { Set-Item Function:\global:Resolve-RunnerOrtLicense -Value $oldProof.ScriptBlock }
            Remove-Variable -Name gpuProofPaths -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'accepts CUDA only when the runtime and shared APIs are present' {
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider cuda -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Be ''
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider CUDA -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Be ''
        Remove-Item -LiteralPath (Join-Path $bin 'onnxruntime_providers_shared.dll')
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider cuda -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Match 'is missing'
    }

    It 'requires newer hub staging and wheel matching APIs' {
        function global:Copy-ChainOrtBeside { param($OnnxRoot) }
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider cuda -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Match 'pinned ANTfrastructure'
        function global:Copy-ChainOrtBeside { param($RequiredProvider) }
        function global:Copy-OrtWheelLicenses { param($OrtDll) }
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider cuda -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Match 'pinned ANTfrastructure'
    }

    It 'requires DirectML and the advertised DirectML capability' {
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider directml -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Be ''
        function global:Copy-OrtWheelLicenses { param($ProviderDll) }
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider directml -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Match 'DirectMlDll'
        function global:Copy-OrtWheelLicenses { param($ProviderDll, $DirectMlDll) }
        Remove-Item -LiteralPath (Join-Path $bin 'DirectML.dll')
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider directml -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Match 'is missing'
        Set-Content -LiteralPath (Join-Path $oxidant 'crates\inference\Cargo.toml') -Value @('[package]', 'name = "old"')
        Get-GpuThrow { Assert-WindowsGpuBuild -Provider directml -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) } | Should Match 'does not support strict'
    }

    It 'checks image architecture and selected wheel members before building' {
        $oldArch = Get-Item Function:\global:Assert-PeTargetMachine -ErrorAction SilentlyContinue
        $script:gpuImageProof = @{}
        function global:Assert-PeTargetMachine { param($Path, $Arch, $Context) $script:gpuImageProof.Arch = $Arch; $script:gpuImageProof.Paths = $Path }
        function global:Copy-OrtWheelLicenses {
            param($OrtDll, $WheelDir, $Destination, $ProviderDll, $DirectMlDll)
            $script:gpuImageProof.Core = $OrtDll
            $script:gpuImageProof.Provider = @($ProviderDll | Where-Object { $null -ne $_ })
            $script:gpuImageProof.Scratch = $Destination
            $script:gpuImageProof.DirectMl = $DirectMlDll
            if ($script:gpuImageProof.Reject) { throw 'wheel mismatch' }
        }
        try {
            foreach ($provider in 'cuda', 'directml') {
                Get-GpuThrow { Assert-WindowsGpuImage -Provider $provider -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) -WheelDir 'wheel-store' -ScratchRoot $TestDrive } | Should Be ''
                $script:gpuImageProof.Arch | Should Be 'amd64'
                (Split-Path $script:gpuImageProof.Core -Leaf) | Should Be 'onnxruntime.dll'
                if ($provider -eq 'cuda') {
                    @($script:gpuImageProof.Provider | ForEach-Object { Split-Path $_ -Leaf }) -join ',' | Should Be 'onnxruntime_providers_shared.dll,onnxruntime_providers_cuda.dll'
                } else {
                    @($script:gpuImageProof.Provider | ForEach-Object { Split-Path $_ -Leaf }) -join ',' | Should Be 'onnxruntime_providers_shared.dll'
                    (Split-Path $script:gpuImageProof.DirectMl -Leaf) | Should Be 'DirectML.dll'
                }
                Test-Path -LiteralPath $script:gpuImageProof.Scratch | Should Be $false
            }
            $script:gpuImageProof.Reject = $true
            Get-GpuThrow { Assert-WindowsGpuImage -Provider cuda -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) -WheelDir 'wheel-store' -ScratchRoot $TestDrive } | Should Match 'wheel mismatch'
            Test-Path -LiteralPath $script:gpuImageProof.Scratch | Should Be $false
        } finally {
            Remove-Item Function:\global:Assert-PeTargetMachine -ErrorAction SilentlyContinue
            if ($oldArch) { Set-Item Function:\global:Assert-PeTargetMachine -Value $oldArch.ScriptBlock }
            Remove-Variable -Name gpuImageProof -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'keeps the Windows GPU candidates x64, separately labelled and preflighted' {
        $workflow = Get-Content -LiteralPath (Join-Path $workspace '.github\workflows\windows-gpu-candidates.yml') -Raw
        $rows = @([regex]::Matches($workflow, '(?m)^\s*- vendor: (\S+)\s*\n\s*tag: (\S+)\s*\n\s*provider: (\S+)\s*$') | ForEach-Object { "$($_.Groups[1].Value):$($_.Groups[2].Value):$($_.Groups[3].Value)" })
        $rows.Count | Should Be 2
        $rows -contains 'nvidia:winamd64-nvidia:cuda' | Should Be $true
        $rows -contains 'amd:winamd64-rocm:directml' | Should Be $true
        $workflow.Contains('winarm64') | Should Be $false
        $workflow.Contains('unverified-omni-windows-x64-${{ matrix.vendor }}-runner') | Should Be $true
        $workflow | Should Match 'name: unverified-omni-windows-x64-\$\{\{ matrix\.vendor \}\}-runner\s+overwrite: true'
        $workflow | Should Match 'name: unverified-omni-windows-x64-\$\{\{ matrix\.vendor \}\}-installers\s+overwrite: true'
        $pinCheck = $workflow.IndexOf('Test-WindowsGpuPins.ps1')
        $pull = $workflow.IndexOf('prepare-windows-container-host@')
        $imageCheck = $workflow.IndexOf('Test-WindowsGpuImage.ps1')
        $build = $workflow.IndexOf('Build-Windows.ps1')
        $upload = $workflow.IndexOf('actions/upload-artifact@')
        ($pinCheck -ge 0 -and $pinCheck -lt $pull -and $pull -lt $imageCheck -and $imageCheck -lt $build -and $build -lt $upload) | Should Be $true
        $package = $workflow.IndexOf('Package-OmniAccelerANT.ps1')
        $install = $workflow.IndexOf('Test-OmniAccelerANTInstallers.ps1')
        $installerUpload = $workflow.IndexOf('name: unverified-omni-windows-x64-${{ matrix.vendor }}-installers')
        ($package -gt $build -and $install -gt $package -and $installerUpload -gt $install) | Should Be $true
    }
}
