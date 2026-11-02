#requires -Version 7.0
# Fixtures several Pester suites share; they stand in for a chain checkout and prove nothing about a real ONNX Runtime.

Set-StrictMode -Version Latest

function Get-ThrowMessage {
    # Pester 3.4 under pwsh 7 has no working `Should Throw`.
    param([scriptblock] $Block)
    try { & $Block | Out-Null } catch { return "$($_.Exception.Message)" }
    return ''
}

function Get-GpuChainDllName {
    'onnxruntime.dll', 'onnxruntime_providers_shared.dll', 'onnxruntime_providers_cuda.dll', 'DirectML.dll'
}

function New-GpuOxidantFixture {
    # An OxidANT crate advertising both Windows GPU devices, beside an empty chain bin directory.
    param([Parameter(Mandatory)][string] $Oxidant, [Parameter(Mandatory)][string] $Bin)
    New-Item -ItemType Directory -Force -Path (Join-Path $Oxidant 'crates\inference'), $Bin | Out-Null
    Set-Content -LiteralPath (Join-Path $Oxidant 'crates\inference\Cargo.toml') -Value @('[package.metadata.kataglyphis]', 'ort-devices = ["cuda", "directml"]')
}

Export-ModuleMember -Function Get-ThrowMessage, Get-GpuChainDllName, New-GpuOxidantFixture
