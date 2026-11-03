#requires -Version 7.0

# Stamps the runner's G6 proof so a host without the image can re-prove that copy; every verdict is G6's.

Set-StrictMode -Version Latest

$script:RunnerOrtFiles = @('onnxruntime.dll', 'onnxruntime_providers_shared.dll', 'DirectML.dll')
$script:RunnerOrtStampName = 'ort-chain-stamp.json'
$script:RunnerOrtStampSchema = 'omni-accelerant/ort-runner/3'
$script:RunnerOrtLicenseNames = @('LICENSE', 'ThirdPartyNotices.txt')

function Get-RunnerOrtFatal {
    param([Parameter(Mandatory)][object] $Census)
    return @($Census.Findings | Where-Object Fatal | ForEach-Object { "$($_.Verdict) $($_.Path) -- $($_.Detail)" })
}

function Stop-RunnerOrtFinding {
    # Nothing found returns; anything found is one error naming the header and each finding.
    param([Parameter(Mandatory)][string] $Header, [string[]] $Finding = @())
    if ($Finding.Count -eq 0) { return }
    $separator = [Environment]::NewLine + '  '
    throw ($Header + $separator + ($Finding -join $separator))
}

function Get-RunnerOrtFamilyFinding {
    # Every ORT-family file anywhere under RunnerDir must be a stamped name with its stamped bytes.
    param([Parameter(Mandatory)][string] $RunnerDir, [Parameter(Mandatory)][hashtable] $Stamped)
    foreach ($file in @(Get-OrtFamilyFile -Directory $RunnerDir -Recurse)) {
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not $Stamped.ContainsKey($file.Name)) { "STRAY $($file.FullName) is not a stamped chain file" }
        elseif ($Stamped[$file.Name] -ne $hash) { "CHANGED $($file.FullName) differs from the stamped chain copy" }
    }
}

function Assert-RunnerOrtProofInput {
    # The runner holds the core DLL and each requested provider, and the pinned hub can match them to a wheel.
    param([Parameter(Mandatory)][string] $RunnerDir, [string[]] $RequiredProvider = @(), [switch] $RequireDirectMl)
    if (-not (Test-Path -LiteralPath (Join-Path $RunnerDir 'onnxruntime.dll') -PathType Leaf)) {
        throw "MISSING $RunnerDir\onnxruntime.dll: without it a client host loads System32's Windows ML copy."
    }
    foreach ($name in $RequiredProvider) {
        if (-not (Test-Path -LiteralPath (Join-Path $RunnerDir $name) -PathType Leaf)) {
            throw "MISSING required ONNX Runtime provider $RunnerDir\$name"
        }
    }
    if ($RequiredProvider.Count -gt 0) {
        $bridge = Join-Path $RunnerDir 'onnxruntime_providers_shared.dll'
        if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) { throw "MISSING required ONNX Runtime provider $bridge" }
        if (-not (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('ProviderDll')) {
            throw 'The pinned ANTfrastructure cannot verify provider DLLs against the matching ORT wheel.'
        }
    }
    if ($RequireDirectMl -and -not (Get-Command Copy-OrtWheelLicenses).Parameters.ContainsKey('DirectMlDll')) {
        throw 'The pinned ANTfrastructure cannot verify DirectML against the matching ORT wheel.'
    }
}

function Invoke-RunnerOrtProof {
    <#
    .SYNOPSIS
        In the image: G6 over RunnerDir, then the stamp Assert-RunnerOrtStamp re-proves on a host; throws on a fatal finding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RunnerDir,
        [ValidateSet('onnxruntime_providers_shared.dll', 'onnxruntime_providers_cuda.dll')][string[]] $RequiredProvider = @(),
        [switch] $RequireDirectMl
    )

    Assert-RunnerOrtProofInput -RunnerDir $RunnerDir -RequiredProvider $RequiredProvider -RequireDirectMl:$RequireDirectMl
    $census = Test-OrtProvenanceTree -Root $RunnerDir -PassThru
    $fatal = @(Get-RunnerOrtFatal -Census $census)
    $stamped = @{}
    foreach ($name in @($script:RunnerOrtFiles) + @($RequiredProvider) | Select-Object -Unique) {
        $path = Join-Path $RunnerDir $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { $stamped[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $fatal += @(Get-RunnerOrtFamilyFinding -RunnerDir $RunnerDir -Stamped $stamped)
    Stop-RunnerOrtFinding -Header "ONNX Runtime in $RunnerDir is not the image's chain build (G6):" -Finding $fatal
    # Only the image has the wheel store, so the texts are matched here and the host re-checks their stamped bytes.
    $licenseArgs = @{ OrtDll = (Join-Path $RunnerDir 'onnxruntime.dll'); WheelDir = (Get-OrtChainWheelStore); Destination = $RunnerDir }
    if ($RequiredProvider.Count -gt 0) {
        $bridge = Join-Path $RunnerDir 'onnxruntime_providers_shared.dll'
        $licenseArgs.ProviderDll = @(@($bridge) + @($RequiredProvider | ForEach-Object { Join-Path $RunnerDir $_ }) | Select-Object -Unique)
    }
    if ($RequireDirectMl) { $licenseArgs.DirectMlDll = Join-Path $RunnerDir 'DirectML.dll' }
    $licenseDir = Copy-OrtWheelLicenses @licenseArgs
    $licenses = [ordered]@{}
    foreach ($name in $script:RunnerOrtLicenseNames) { $licenses[$name] = (Get-FileHash -LiteralPath (Join-Path $licenseDir $name) -Algorithm SHA256).Hash.ToLowerInvariant() }
    $verifiedProviders = @()
    if ($RequiredProvider.Count -gt 0) { $verifiedProviders = @(@('onnxruntime_providers_shared.dll') + $RequiredProvider | Select-Object -Unique) }
    $stamp = [ordered]@{ schema = $script:RunnerOrtStampSchema; proof = 'G6 Test-OrtProvenanceTree'; sha256 = $stamped; licenses = $licenses; verified_providers = $verifiedProviders; verified_directml = $RequireDirectMl.IsPresent }
    $stamp | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $RunnerDir $script:RunnerOrtStampName) -Encoding utf8
    return [pscustomobject]@{ Stamp = $stamp; Census = $census }
}

function Read-RunnerOrtStamp {
    param([Parameter(Mandatory)][string] $RunnerDir, [ValidateSet('sha256', 'licenses')][string] $Section = 'sha256')
    $path = Join-Path $RunnerDir $script:RunnerOrtStampName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { return $null }
    if ($json -isnot [hashtable] -or $json['schema'] -ne $script:RunnerOrtStampSchema -or $json[$Section] -isnot [hashtable]) { return $null }
    $sha = @{}
    foreach ($k in $json[$Section].Keys) { $sha[$k] = "$($json[$Section][$k])".ToLowerInvariant() }
    $required = if ($Section -eq 'licenses') { $script:RunnerOrtLicenseNames } else { @('onnxruntime.dll') }
    foreach ($name in $required) { if (-not $sha.ContainsKey($name)) { return $null } }
    return $sha
}

function Assert-RunnerOrtStampVerified {
    # The image matched each requested provider, and DirectML when asked, to the core wheel before stamping.
    param([Parameter(Mandatory)][string] $RunnerDir, [Parameter(Mandatory)][hashtable] $Stamped,
        [string[]] $RequiredProvider = @(), [switch] $RequireDirectMl)
    if ($RequiredProvider.Count -gt 0) {
        $stamp = Get-Content -LiteralPath (Join-Path $RunnerDir $script:RunnerOrtStampName) -Raw | ConvertFrom-Json -AsHashtable
        $verified = @($stamp['verified_providers'])
        foreach ($name in $RequiredProvider) {
            if ($name -notin $verified -or -not $Stamped.ContainsKey($name)) {
                throw "UNPROVEN $name was not matched to the core ONNX Runtime wheel for $RunnerDir."
            }
        }
    }
    if ($RequireDirectMl) {
        $stamp = Get-Content -LiteralPath (Join-Path $RunnerDir $script:RunnerOrtStampName) -Raw | ConvertFrom-Json -AsHashtable
        if ($stamp['verified_directml'] -isnot [bool] -or -not $stamp['verified_directml'] -or -not $Stamped.ContainsKey('DirectML.dll')) {
            throw "UNPROVEN DirectML.dll was not matched to the core ONNX Runtime wheel for $RunnerDir."
        }
    }
}

function Get-RunnerOrtCopyFinding {
    # G6's reference is the stamped copy itself, which the fingerprint must still tie to the chain.
    param([Parameter(Mandatory)][string] $RunnerDir, [Parameter(Mandatory)][hashtable] $Stamped)
    $ref = Join-Path ([System.IO.Path]::GetTempPath()) "ort-runner-ref-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $ref | Out-Null
    try {
        foreach ($name in @($Stamped.Keys | Where-Object { Test-OrtInstanceName -Name $_ })) { Copy-Item -LiteralPath (Join-Path $RunnerDir $name) -Destination $ref }
        $census = Test-OrtProvenanceTree -Root $RunnerDir -ReferenceDir @($ref) -PassThru
    } finally { Remove-Item -LiteralPath $ref -Recurse -Force -ErrorAction SilentlyContinue }
    Get-RunnerOrtFatal -Census $census
    # G6 already calls a foreign-rooted reference FOREIGN; a reference with no root at all it cannot judge.
    $core = @($census.Reference | Where-Object { $_.Name -eq 'onnxruntime.dll' }) | Select-Object -First 1
    if ($null -eq $core -or @($core.Roots).Count -eq 0) {
        "UNPROVEN $RunnerDir\onnxruntime.dll embeds no ORT source root, so nothing ties it to the chain ($(@(Get-OrtChainSourceRoot) -join ', '))"
    }
}

function Get-RunnerOrtStampFinding {
    # G6 runs only over a tree already holding exactly the stamped bytes.
    param([Parameter(Mandatory)][string] $RunnerDir, [Parameter(Mandatory)][hashtable] $Stamped)
    $absent = @($Stamped.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RunnerDir $_) -PathType Leaf) } | ForEach-Object { "MISSING $_ is stamped but absent from $RunnerDir" })
    $family = @(Get-RunnerOrtFamilyFinding -RunnerDir $RunnerDir -Stamped $Stamped)
    $absent + $family
    if ($absent.Count + $family.Count -eq 0) { Get-RunnerOrtCopyFinding -RunnerDir $RunnerDir -Stamped $Stamped }
}

function Get-RunnerOrtLicenseFinding {
    param([Parameter(Mandatory)][string] $Directory, [Parameter(Mandatory)][hashtable] $Stamped)
    foreach ($name in $script:RunnerOrtLicenseNames) {
        $path = Join-Path $Directory $name
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($null -eq $item -or $item.PSIsContainer) { "MISSING $path"; continue }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { "LINK $path"; continue }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Stamped[$name]) { "CHANGED $path differs from the wheel text the image matched" }
    }
}

function Assert-RunnerOrtStamp {
    <#
    .SYNOPSIS
        On a host: the runner holds exactly the stamped ORT, and G6 against that copy finds nothing foreign.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RunnerDir,
        [ValidateSet('onnxruntime_providers_shared.dll', 'onnxruntime_providers_cuda.dll')][string[]] $RequiredProvider = @(),
        [switch] $RequireDirectMl)

    $stamped = Read-RunnerOrtStamp -RunnerDir $RunnerDir
    if ($null -eq $stamped) {
        throw "UNSTAMPED $RunnerDir has no $($script:RunnerOrtStampName) of schema $($script:RunnerOrtStampSchema): it was not staged and proved by Build-Windows.ps1."
    }
    Assert-RunnerOrtStampVerified -RunnerDir $RunnerDir -Stamped $stamped -RequiredProvider $RequiredProvider -RequireDirectMl:$RequireDirectMl
    Stop-RunnerOrtFinding -Header "ONNX Runtime in $RunnerDir is not the stamped chain build:" -Finding @(Get-RunnerOrtStampFinding -RunnerDir $RunnerDir -Stamped $stamped)
}

function Resolve-RunnerOrtLicense {
    <#
    .SYNOPSIS
        On a host: the stamp re-proves, and licenses\onnxruntime holds exactly the wheel texts the image matched; returns that directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $RunnerDir, [string[]] $RequiredProvider = @(), [switch] $RequireDirectMl)

    Assert-RunnerOrtStamp -RunnerDir $RunnerDir -RequiredProvider $RequiredProvider -RequireDirectMl:$RequireDirectMl
    $stamped = Read-RunnerOrtStamp -RunnerDir $RunnerDir -Section licenses
    if ($null -eq $stamped) {
        throw "UNSTAMPED $RunnerDir\$($script:RunnerOrtStampName) records no wheel-matched ONNX Runtime license texts: it was not staged by Build-Windows.ps1 or Build-WindowsArm64Natives.ps1."
    }
    $dir = Join-Path $RunnerDir 'licenses\onnxruntime'
    Stop-RunnerOrtFinding -Header "ONNX Runtime license texts in $RunnerDir are not the stamped wheel texts:" -Finding @(Get-RunnerOrtLicenseFinding -Directory $dir -Stamped $stamped)
    return $dir
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

Export-ModuleMember -Function Invoke-RunnerOrtProof, Assert-RunnerOrtStamp, Resolve-RunnerOrtLicense, Assert-RunnerOrtOverride
