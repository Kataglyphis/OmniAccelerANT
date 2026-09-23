#requires -Version 7.0

# PROJECT-LOCAL glue for the runner bundle: stage the image's chain ONNX Runtime beside the exe and
# prove it with ANTfrastructure's G6 census (WindowsOrtProvenance.Common), which the caller imports.
# Owner rule 2026-09-23 (third_party/ANTfrastructure/docs/onnxruntime-single-source.md). Every verdict is G6's;
# this module adds only the runner stamp, which lets a host without the image re-run G6 against the
# copy the build proved. NOT covered: which copy a process loads beyond G6's modelled loader order.

Set-StrictMode -Version Latest

$script:RunnerOrtFiles = @('onnxruntime.dll', 'onnxruntime_providers_shared.dll', 'DirectML.dll')
$script:RunnerOrtFamily = @('onnxruntime*.dll', 'DirectML.dll')
$script:RunnerOrtStampName = 'ort-chain-stamp.json'
$script:RunnerOrtStampSchema = 'omni-accelerant/ort-runner/2'

function Get-OrtCensusRequirement {
    <#
    .SYNOPSIS
        The error for a hub pin that lacks G6: which hub commit is needed, and where the pin is.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][object] $Cause = $null)

    $hub = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\third_party\ANTfrastructure'))
    $at = try { "$(& git -C $hub rev-parse --short HEAD 2>$null)".Trim() } catch { '' }
    return ("ONNX Runtime proof needs ANTfrastructure's G6 census (windows/scripts/modules/" +
        "WindowsOrtProvenance.Common.psm1, Test-OrtProvenanceTree), added by the hub's ORT single-source " +
        "commit of 2026-09-23 (third_party/ANTfrastructure/docs/onnxruntime-single-source.md). third_party/ANTfrastructure is at " +
        "$(if ($at) { $at } else { 'an unknown commit' }): move the gitlink to that commit or later." +
        $(if ($Cause) { " ($Cause)" } else { '' }))
}

function Assert-OrtCensusCommand {
    foreach ($cmd in 'Test-OrtProvenanceTree', 'Get-OrtChainSourceRoot', 'Test-OrtInstanceName') {
        if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) { throw (Get-OrtCensusRequirement -Cause "$cmd is not loaded") }
    }
}

function Test-RunnerOrtFamilyName {
    param([Parameter(Mandatory)][string] $Name)
    return @($script:RunnerOrtFamily | Where-Object { $Name -like $_ }).Count -gt 0
}

function Copy-RunnerChainOrt {
    <#
    .SYNOPSIS
        Replaces every ORT-family DLL at the top of RunnerDir with the chain's from OnnxRoot\bin.
        Provenance is not judged here: Invoke-RunnerOrtProof (G6) does that next.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $OnnxRoot,
        [Parameter(Mandatory)][string] $RunnerDir
    )

    if ([string]::IsNullOrWhiteSpace($OnnxRoot)) {
        throw "ONNX_ROOT is unset: build inside the family Windows image, whose chain-built ONNX Runtime is the only one allowed beside the exe (without it System32's Windows ML copy wins)."
    }
    $bin = Join-Path $OnnxRoot 'bin'
    if (-not (Test-Path -LiteralPath (Join-Path $bin 'onnxruntime.dll') -PathType Leaf)) {
        throw "No chain ONNX Runtime at $bin\onnxruntime.dll: ONNX_ROOT must be the image's chain install."
    }
    if (-not $PSCmdlet.ShouldProcess($RunnerDir, 'stage chain ONNX Runtime')) { return }
    Get-ChildItem -LiteralPath $RunnerDir -File | Where-Object { Test-RunnerOrtFamilyName -Name $_.Name } | Remove-Item -Force
    foreach ($name in $script:RunnerOrtFiles) {
        $src = Join-Path $bin $name
        if (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination $RunnerDir -Force }
    }
}

function Get-RunnerOrtFatal {
    param([Parameter(Mandatory)][object] $Census)
    return @($Census.Findings | Where-Object Fatal | ForEach-Object { "$($_.Verdict) $($_.Path) -- $($_.Detail)" })
}

function Get-RunnerOrtFamilyFinding {
    # Every ORT-family file anywhere under RunnerDir must be a stamped name with its stamped bytes.
    param([Parameter(Mandatory)][string] $RunnerDir, [Parameter(Mandatory)][hashtable] $Stamped)
    foreach ($file in @(Get-ChildItem -LiteralPath $RunnerDir -File -Recurse | Where-Object { Test-RunnerOrtFamilyName -Name $_.Name })) {
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not $Stamped.ContainsKey($file.Name)) { "STRAY $($file.FullName) is not a stamped chain file" }
        elseif ($Stamped[$file.Name] -ne $hash) { "CHANGED $($file.FullName) differs from the stamped chain copy" }
    }
}

function Invoke-RunnerOrtProof {
    <#
    .SYNOPSIS
        In the image: G6 over RunnerDir against the image's chain ORT, then the stamp that
        Assert-RunnerOrtStamp re-proves on a host. Throws on any fatal G6 finding.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunnerDir)

    Assert-OrtCensusCommand
    if (-not (Test-Path -LiteralPath (Join-Path $RunnerDir 'onnxruntime.dll') -PathType Leaf)) {
        throw "MISSING $RunnerDir\onnxruntime.dll: without it a client host loads System32's Windows ML copy."
    }
    $census = Test-OrtProvenanceTree -Root $RunnerDir -PassThru
    $fatal = @(Get-RunnerOrtFatal -Census $census)
    $stamped = @{}
    foreach ($name in $script:RunnerOrtFiles) {
        $path = Join-Path $RunnerDir $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { $stamped[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $fatal += @(Get-RunnerOrtFamilyFinding -RunnerDir $RunnerDir -Stamped $stamped)
    if ($fatal.Count -gt 0) {
        throw ("ONNX Runtime in $RunnerDir is not the image's chain build (G6):" + [Environment]::NewLine + '  ' + ($fatal -join ([Environment]::NewLine + '  ')))
    }
    $stamp = [ordered]@{ schema = $script:RunnerOrtStampSchema; proof = 'G6 Test-OrtProvenanceTree'; sha256 = $stamped }
    $stamp | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $RunnerDir $script:RunnerOrtStampName) -Encoding utf8
    return [pscustomobject]@{ Stamp = $stamp; Census = $census }
}

function Read-RunnerOrtStamp {
    param([Parameter(Mandatory)][string] $RunnerDir)
    $path = Join-Path $RunnerDir $script:RunnerOrtStampName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { return $null }
    if ($json -isnot [hashtable] -or $json['schema'] -ne $script:RunnerOrtStampSchema -or $json['sha256'] -isnot [hashtable]) { return $null }
    $sha = @{}
    foreach ($k in $json['sha256'].Keys) { $sha[$k] = "$($json['sha256'][$k])".ToLowerInvariant() }
    if (-not $sha.ContainsKey('onnxruntime.dll')) { return $null }
    return $sha
}

function Assert-RunnerOrtStamp {
    <#
    .SYNOPSIS
        On a host without the image: the runner still holds exactly the ORT the build proved, and G6,
        run against that stamped copy, finds no foreign ORT and no importer falling through to System32.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunnerDir)

    Assert-OrtCensusCommand
    $stamped = Read-RunnerOrtStamp -RunnerDir $RunnerDir
    if ($null -eq $stamped) {
        throw "UNSTAMPED $RunnerDir has no $($script:RunnerOrtStampName) of schema $($script:RunnerOrtStampSchema): it was not staged and proved by Build-Windows.ps1."
    }
    $findings = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $stamped.Keys) {
        if (-not (Test-Path -LiteralPath (Join-Path $RunnerDir $name) -PathType Leaf)) { $findings.Add("MISSING $name is stamped but absent from $RunnerDir") }
    }
    foreach ($f in @(Get-RunnerOrtFamilyFinding -RunnerDir $RunnerDir -Stamped $stamped)) { $findings.Add($f) }
    if ($findings.Count -eq 0) {
        # G6's reference is the stamped copy itself, which the fingerprint must still tie to the chain.
        $ref = Join-Path ([System.IO.Path]::GetTempPath()) "ort-runner-ref-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $ref | Out-Null
        try {
            foreach ($name in @($stamped.Keys | Where-Object { Test-OrtInstanceName -Name $_ })) { Copy-Item -LiteralPath (Join-Path $RunnerDir $name) -Destination $ref }
            $census = Test-OrtProvenanceTree -Root $RunnerDir -ReferenceDir @($ref) -PassThru
        } finally { Remove-Item -LiteralPath $ref -Recurse -Force -ErrorAction SilentlyContinue }
        foreach ($f in @(Get-RunnerOrtFatal -Census $census)) { $findings.Add($f) }
        # G6 already calls a foreign-rooted reference FOREIGN; a reference with no root at all it cannot judge.
        $core = @($census.Reference | Where-Object { $_.Name -eq 'onnxruntime.dll' }) | Select-Object -First 1
        if ($null -eq $core -or @($core.Roots).Count -eq 0) {
            $findings.Add("UNPROVEN $RunnerDir\onnxruntime.dll embeds no ORT source root, so nothing ties it to the chain ($(@(Get-OrtChainSourceRoot) -join ', '))")
        }
    }
    if ($findings.Count -gt 0) {
        throw ("ONNX Runtime in $RunnerDir is not the stamped chain build:" + [Environment]::NewLine + '  ' + ($findings -join ([Environment]::NewLine + '  ')))
    }
}

function Assert-RunnerOrtOverride {
    <#
    .SYNOPSIS
        ORT_DYLIB_PATH overrides the runner copy for oxidant.dll, so it may only name those same proven bytes.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $Value,
        [Parameter(Mandatory)][string] $ExeDir,
        [Parameter(Mandatory)][string] $RunnerDir
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    # Resolved like OxidANT's ort_runtime.rs: a relative value against the exe's directory.
    $path = [System.IO.Path]::GetFullPath($Value, $ExeDir)
    $stamped = Read-RunnerOrtStamp -RunnerDir $RunnerDir
    $hash = if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
    if ($null -eq $stamped -or $hash -ne $stamped['onnxruntime.dll']) {
        throw "ORT_DYLIB_PATH=$Value ($path) is not the chain ONNX Runtime the build proved for $RunnerDir (missing, or other bytes). Unset it; the stamped copy beside the exe is used then."
    }
}

Export-ModuleMember -Function Get-OrtCensusRequirement, Copy-RunnerChainOrt, Invoke-RunnerOrtProof,
    Assert-RunnerOrtStamp, Assert-RunnerOrtOverride
