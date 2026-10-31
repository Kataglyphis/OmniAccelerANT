#requires -Version 7.0

Set-StrictMode -Version Latest

function Assert-WindowsGpuPackagingMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('cpu', 'cuda', 'directml')][string] $Provider,
        [switch] $SkipMsixPackaging
    )
    if ($Provider -ne 'cpu' -and -not $SkipMsixPackaging) {
        throw 'GPU builds require -SkipMsixPackaging until a verified GPU installer is available.'
    }
}

function Get-WindowsGpuExecutableProvider {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $ExePath)

    $stream = [IO.File]::OpenRead($ExePath)
    try {
        $buffer = [byte[]]::new(65536)
        $encoding = [Text.Encoding]::GetEncoding('iso-8859-1')
        $tail = ''
        $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $chunk = $tail + $encoding.GetString($buffer, 0, $read)
            foreach ($provider in 'cuda', 'directml') {
                if ($chunk.Contains("OMNI_ACCELERANT_GPU_VARIANT_${provider}_V1")) { $null = $found.Add($provider) }
            }
            $tail = $chunk.Substring([Math]::Max(0, $chunk.Length - 64))
        }
        if ($found.Count -gt 1) { throw "Conflicting GPU variant markers in $ExePath" }
        if ($found.Count -eq 0) { return 'cpu' }
        return @($found)[0]
    } finally { $stream.Dispose() }
}

function Assert-WindowsInstallerCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunnerDir,
        [ValidateSet('cpu', 'cuda', 'directml')][string] $Provider = 'cpu',
        [ValidateSet('x64', 'arm64')][string] $Arch = 'x64')

    if ($Provider -ne 'cpu') {
        if ($Arch -ne 'x64') { throw 'Windows GPU installers require x64.' }
        Assert-WindowsGpuDelivery -SourceDir $RunnerDir -DestinationDir $RunnerDir -Provider $Provider
        return
    }
    if (Test-Path -LiteralPath (Join-Path $RunnerDir 'onnxruntime_providers_cuda.dll') -PathType Leaf) {
        throw 'GPU installers are not yet verified; refusing a CUDA runner.'
    }
    if ((Get-WindowsGpuExecutableProvider -ExePath (Join-Path $RunnerDir 'omni_accelerant.exe')) -ne 'cpu') {
        throw 'GPU installers are not yet verified; refusing a GPU-marked runner.'
    }
}

function Assert-WindowsGpuDelivery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourceDir,
        [Parameter(Mandatory)][string] $DestinationDir,
        [Parameter(Mandatory)][ValidateSet('cuda', 'directml')][string] $Provider
    )
    $exe = 'omni_accelerant.exe'
    $variant = Get-WindowsGpuExecutableProvider -ExePath (Join-Path $SourceDir $exe)
    if ($variant -ne $Provider) { throw "Built runner is marked '$variant', not the requested '$Provider' provider." }
    foreach ($name in @($exe, 'oxidant.dll', 'AccelerANTgine.dll', 'ort-chain-stamp.json')) {
        $source = Join-Path $SourceDir $name
        $destination = Join-Path $DestinationDir $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            throw "GPU delivery is missing $name; repair the host sync and rerun."
        }
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
            throw "GPU delivery has a stale or incomplete $name in $DestinationDir; repair the host sync and rerun."
        }
    }
    if ($Provider -eq 'directml' -and (Test-Path -LiteralPath (Join-Path $DestinationDir 'onnxruntime_providers_cuda.dll') -PathType Leaf)) {
        throw "GPU delivery contains a stale CUDA provider in $DestinationDir; move the old output aside and rerun."
    }
    if ($Provider -eq 'cuda' -and -not (Test-Path -LiteralPath (Join-Path $DestinationDir 'onnxruntime_providers_cuda.dll') -PathType Leaf)) {
        throw "GPU delivery is missing the CUDA provider in $DestinationDir; repair the host sync and rerun."
    }
    if ($Provider -eq 'directml' -and -not (Test-Path -LiteralPath (Join-Path $DestinationDir 'DirectML.dll') -PathType Leaf)) {
        throw "GPU delivery is missing DirectML.dll in $DestinationDir; repair the host sync and rerun."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $DestinationDir 'onnxruntime_providers_shared.dll') -PathType Leaf)) {
        throw "GPU delivery is missing the shared provider in $DestinationDir; repair the host sync and rerun."
    }
    $required = @('onnxruntime_providers_shared.dll')
    if ($Provider -eq 'cuda') { $required += 'onnxruntime_providers_cuda.dll' }
    $null = Resolve-RunnerOrtLicense -RunnerDir $SourceDir -RequiredProvider $required -RequireDirectMl:($Provider -eq 'directml')
    $null = Resolve-RunnerOrtLicense -RunnerDir $DestinationDir -RequiredProvider $required -RequireDirectMl:($Provider -eq 'directml')
}

function Assert-WindowsGpuDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('cpu', 'cuda', 'directml')][string] $Provider,
        [Parameter(Mandatory)][string] $Workspace,
        [Parameter(Mandatory)][string] $OxidantDir
    )

    $Provider = $Provider.ToLowerInvariant()
    if ($Provider -eq 'cpu') { return }
    $check = Join-Path $Workspace 'scripts/windows/validate-ort-device.cmake'
    & cmake "-DOMNI_WINDOWS_ORT_PROVIDER=$Provider" '-DFLUTTER_TARGET_PLATFORM=windows-x64' "-DOXIDANT_DIR=$OxidantDir" -P $check
    if ($LASTEXITCODE -ne 0) { throw "OxidANT does not support strict $Provider selection." }

    foreach ($entry in @(@('Copy-ChainOrtBeside', 'RequiredProvider'), @('Get-ChainOrtRuntimeFile', 'Name'), @('Copy-OrtWheelLicenses', 'ProviderDll'))) {
        $command = Get-Command $entry[0] -ErrorAction SilentlyContinue
        if (-not $command -or -not $command.Parameters.ContainsKey($entry[1])) {
            throw "The pinned ANTfrastructure needs $($entry[0]) -$($entry[1]) for GPU staging and wheel verification."
        }
    }
    if ($Provider -eq 'directml' -and -not (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('DirectMlDll')) {
        throw 'The pinned ANTfrastructure needs Copy-OrtWheelLicenses -DirectMlDll for DirectML wheel verification.'
    }
}

function Assert-WindowsGpuBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('cpu', 'cuda', 'directml')][string] $Provider,
        [Parameter(Mandatory)][string] $Workspace,
        [Parameter(Mandatory)][string] $OxidantDir,
        [AllowEmptyString()][string] $OnnxRoot = ''
    )
    $Provider = $Provider.ToLowerInvariant()
    if ($Provider -eq 'cpu') { return }
    Assert-WindowsGpuDependencies -Provider $Provider -Workspace $Workspace -OxidantDir $OxidantDir
    if ([string]::IsNullOrWhiteSpace($OnnxRoot)) { throw 'GPU builds require ONNX_ROOT to name the chain runtime.' }
    $required = @('onnxruntime.dll', 'onnxruntime_providers_shared.dll')
    if ($Provider -eq 'cuda') {
        $required += 'onnxruntime_providers_cuda.dll'
    } else {
        $required += 'DirectML.dll'
    }
    foreach ($name in $required) { $null = Get-ChainOrtRuntimeFile -OnnxRoot $OnnxRoot -Name $name }
}

function Assert-WindowsGpuImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('cuda', 'directml')][string] $Provider,
        [Parameter(Mandatory)][string] $Workspace,
        [Parameter(Mandatory)][string] $OxidantDir,
        [Parameter(Mandatory)][string] $OnnxRoot,
        [Parameter(Mandatory)][string] $WheelDir,
        [string] $ScratchRoot = [IO.Path]::GetTempPath()
    )
    $Provider = $Provider.ToLowerInvariant()
    Assert-WindowsGpuBuild -Provider $Provider -Workspace $Workspace -OxidantDir $OxidantDir -OnnxRoot $OnnxRoot
    $names = @('onnxruntime.dll', 'onnxruntime_providers_shared.dll')
    if ($Provider -eq 'cuda') { $names += 'onnxruntime_providers_cuda.dll' }
    else { $names += 'DirectML.dll' }
    $files = @($names | ForEach-Object { Get-ChainOrtRuntimeFile -OnnxRoot $OnnxRoot -Name $_ })
    $null = Assert-PeTargetMachine -Path $files -Arch 'amd64' -Context 'Windows GPU inputs require x64'
    $parent = (Resolve-Path -LiteralPath $ScratchRoot -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Scratch root is not a directory: $parent" }
    $scratch = Join-Path $parent "omni-gpu-image-proof-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $scratch -ErrorAction Stop
    try {
        $licenseArgs = @{ OrtDll = $files[0]; WheelDir = $WheelDir; Destination = $scratch }
        $licenseArgs.ProviderDll = if ($Provider -eq 'cuda') { [string[]]@($files[1], $files[2]) } else { [string[]]@($files[1]) }
        if ($Provider -eq 'directml') { $licenseArgs.DirectMlDll = $files[2] }
        $null = Copy-OrtWheelLicenses @licenseArgs
    } finally {
        $resolved = (Resolve-Path -LiteralPath $scratch -ErrorAction Stop).ProviderPath
        $prefix = $parent.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Invalid GPU proof scratch directory: $resolved" }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Export-ModuleMember -Function Assert-WindowsGpuBuild, Assert-WindowsGpuDependencies, Assert-WindowsGpuImage, Assert-WindowsGpuPackagingMode, Assert-WindowsInstallerCandidate, Assert-WindowsGpuDelivery
