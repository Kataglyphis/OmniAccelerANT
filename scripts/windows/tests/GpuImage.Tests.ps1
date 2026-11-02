#requires -Version 7.0

. (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsTargetArch.Common', 'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common',
    'WindowsOrtLicense.Common', 'WindowsGpuBuild.Common')
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$resolver = Get-Command Get-ChainOrtRuntimeFile -ErrorAction SilentlyContinue
$hasProviderApi = (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('ProviderDll') -and
    (Get-Command Copy-ChainOrtBeside).Parameters.ContainsKey('RequiredProvider') -and $null -ne $resolver
$hasDirectMlApi = $hasProviderApi -and (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('DirectMlDll')


function New-GpuImagePe([string] $Path, [byte] $Marker, [bool] $Arm = $false) {
    $bytes = [byte[]]::new(256)
    $bytes[0x3c] = 0x80; $bytes[0x80] = 0x50; $bytes[0x81] = 0x45
    if ($Arm) { $bytes[0x84] = 0x64; $bytes[0x85] = 0xaa }
    else { $bytes[0x84] = 0x64; $bytes[0x85] = 0x86 }
    $bytes[0xf0] = $Marker
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function New-GpuImageWheel([string] $Path, [string] $Bin) {
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in 'onnxruntime.dll', 'onnxruntime_providers_shared.dll', 'onnxruntime_providers_cuda.dll', 'DirectML.dll') {
            $inputStream = [IO.File]::OpenRead((Join-Path $Bin $name))
            $outputStream = $archive.CreateEntry("onnxruntime/capi/$name").Open()
            try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
        }
        foreach ($name in 'LICENSE', 'ThirdPartyNotices.txt') {
            $writer = [IO.StreamWriter]::new($archive.CreateEntry("onnxruntime/$name").Open())
            try { $writer.Write('original wheel text') } finally { $writer.Dispose() }
        }
    } finally { $archive.Dispose() }
}

Describe 'Windows GPU image wheel proof' {
    Import-Module (Join-Path $PSScriptRoot 'OmniTestFixtures.psm1') -Force

    function Set-ChainDll([string] $Name, [int] $Marker, [bool] $Arm = $false) {
        New-GpuImagePe -Path (Join-Path $bin $Name) -Marker $Marker -Arm $Arm
    }

    # The proof over this case's fixture; reads the variables BeforeEach set for the running test.
    function Get-ImageProofError([string] $Provider) {
        Get-ThrowMessage { Assert-WindowsGpuImage -Provider $Provider -Workspace $workspace -OxidantDir $oxidant -OnnxRoot (Split-Path $bin) -WheelDir $wheels -ScratchRoot $caseRoot }
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $oxidant = Join-Path $caseRoot 'oxidant'
        $bin = Join-Path $caseRoot 'onnx\bin'
        $wheels = Join-Path $caseRoot 'wheels'
        New-GpuOxidantFixture -Oxidant $oxidant -Bin $bin
        New-Item -ItemType Directory -Force -Path $wheels | Out-Null
        $marker = 1
        foreach ($name in Get-GpuChainDllName) {
            New-GpuImagePe -Path (Join-Path $bin $name) -Marker $marker
            $marker++
        }
        New-GpuImageWheel -Path (Join-Path $wheels 'onnxruntime_gpu-1.2.3-cp315-cp315-win_amd64.whl') -Bin $bin
    }

    It 'requires the DirectML core, bridge and runtime to match its wheel and rejects wrong architecture' -Skip:(-not $hasDirectMlApi) {
        Get-ImageProofError directml | Should Be ''
        Set-ChainDll 'onnxruntime_providers_shared.dll' 9
        Get-ImageProofError directml | Should Match 'differs from the matching wheel'
        Set-ChainDll 'onnxruntime_providers_shared.dll' 2
        Set-ChainDll 'DirectML.dll' 9
        Get-ImageProofError directml | Should Match 'DirectML runtime differs'
        Set-ChainDll 'DirectML.dll' 4 -Arm $true
        (Get-PeFileMachine -Path (Join-Path $bin 'DirectML.dll')) | Should Be 43620
        Get-ImageProofError directml | Should Match 'PE machine'
        @(Get-ChildItem -LiteralPath $caseRoot -Filter 'omni-gpu-image-proof-*').Count | Should Be 0
    }

    It 'requires CUDA and the bridge to match the same wheel' -Skip:(-not $hasProviderApi) {
        Get-ImageProofError cuda | Should Be ''
        $lib = Join-Path (Split-Path $bin) 'lib'
        New-Item -ItemType Directory -Path $lib | Out-Null
        Move-Item -LiteralPath (Join-Path $bin 'onnxruntime_providers_cuda.dll') -Destination $lib
        Get-ImageProofError cuda | Should Be ''
        New-GpuImagePe -Path (Join-Path $lib 'onnxruntime_providers_cuda.dll') -Marker 9
        Get-ImageProofError cuda | Should Match 'differs from the matching wheel'
        @(Get-ChildItem -LiteralPath $caseRoot -Filter 'omni-gpu-image-proof-*').Count | Should Be 0
    }
}
