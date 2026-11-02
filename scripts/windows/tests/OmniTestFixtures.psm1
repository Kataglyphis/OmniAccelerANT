#requires -Version 7.0
# Fixtures several Pester suites share; they stand in for a chain checkout and prove nothing about a real ONNX Runtime.

Set-StrictMode -Version Latest

function Get-ThrowMessage {
    # Pester 3.4 under pwsh 7 has no working `Should Throw`.
    param([scriptblock] $Block)
    try { & $Block | Out-Null } catch { return "$($_.Exception.Message)" }
    return ''
}

function Test-TextBefore {
    # First is present and precedes every Later marker; a missing Later marker reads -1 and fails.
    param([Parameter(Mandatory)][string] $Text, [Parameter(Mandatory)][string] $First, [Parameter(Mandatory)][string[]] $Later)
    $at = $Text.IndexOf($First)
    if ($at -lt 0) { return $false }
    foreach ($marker in $Later) { if ($at -ge $Text.IndexOf($marker)) { return $false } }
    return $true
}

function Get-CommandTextCount {
    # How many command ASTs contain every given piece of text.
    param([object[]] $Commands, [Parameter(Mandatory)][string[]] $Contains)
    return @($Commands | Where-Object { $text = $_.Extent.Text; @($Contains | Where-Object { -not $text.Contains($_) }).Count -eq 0 }).Count
}

function Test-CommandAfter {
    param([Parameter(Mandatory)] $Later, [Parameter(Mandatory)] $Earlier)
    return $Later.Extent.StartOffset -gt $Earlier.Extent.StartOffset
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

Export-ModuleMember -Function Get-CommandTextCount, Test-CommandAfter, Get-ThrowMessage, Test-TextBefore, Get-GpuChainDllName, New-GpuOxidantFixture
