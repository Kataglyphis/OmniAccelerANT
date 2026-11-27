#requires -Version 7.0
# An MSI and a signed MSIX from an app folder and their licence checks, for Package-OmniAccelerANT.ps1 and Package-ObservANT.ps1; the callers import WindowsMsix.Common, WindowsMsix.Signing and the three licence modules.

Set-StrictMode -Version Latest

function New-AppInstallerPlan {
    <#
    .SYNOPSIS
        What one app's MSI and MSIX share: the folder they pack, their arch, output and scratch paths, and the licences both must carry.
    .PARAMETER OutBase
        The installers' path without extension: the MSI lands at OutBase.msi, the MSIX at OutBase.msix.
    .PARAMETER Notice
        Flutter's NOTICES as an archive member pattern, e.g. '*flutter_assets/NOTICES.Z'; an MSI holds it by its file name.
    #>
    param(
        [Parameter(Mandatory)][string]$AppDir,
        [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
        [Parameter(Mandatory)][string]$OutBase,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Notice,
        [Parameter(Mandatory)][string]$OrtLicenseDirectory
    )
    return [pscustomobject]@{
        AppDir = $AppDir; Arch = $Arch; WorkDir = $WorkDir; Msi = "$OutBase.msi"; Msix = "$OutBase.msix"
        Fragment = Join-Path $WorkDir 'msi-payload-files.wxs'; RepoRoot = $RepoRoot; Notice = $Notice
        Asset = @(Get-ThirdPartyLicenseAsset -RepoRoot $RepoRoot); OrtLicenseDirectory = $OrtLicenseDirectory
    }
}

function New-AppMsi {
    <#
    .SYNOPSIS
        The plan's MSI through the hub's Invoke-MsiPackage: -ExeName is the .wxs's own file, every other file of the app folder a payload component.
    #>
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$ExeName,
        [Parameter(Mandatory)][string]$WxsFile,
        [Parameter(Mandatory)][string]$ProductName,
        [Parameter(Mandatory)][string]$Version,
        [string[]]$Extensions = @('WixToolset.UI.wixext'),
        [string]$LicenseFile = (Join-Path $PSScriptRoot '..\installer\License.rtf')
    )
    $appDir = $Plan.AppDir
    $exe = Join-Path $appDir $ExeName
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "no $ExeName in $appDir" }
    $payloadFiles = @(Get-ChildItem -LiteralPath $appDir -Recurse -File | Where-Object FullName -ne $exe | ForEach-Object {
            $sub = [IO.Path]::GetRelativePath($appDir, $_.DirectoryName)
            [pscustomobject]@{ Source = $_.FullName; Subdirectory = $(if ($sub -eq '.') { '' } else { $sub }) }
        })
    Invoke-MsiPackage -Context $Context -WxsFile $WxsFile -LicenseFile $LicenseFile -ProductName $ProductName -Manufacturer 'Kataglyphis' `
        -ExeSource $exe -Version $Version -OutFile $Plan.Msi -Arch $Plan.Arch -PayloadFiles $payloadFiles -FragmentPath $Plan.Fragment `
        -Extensions $Extensions | Out-Null
    Write-Host "wrote $($Plan.Msi) ($([math]::Round((Get-Item -LiteralPath $Plan.Msi).Length / 1MB)) MB, $($payloadFiles.Count + 1) files)"
}

function New-AppMsix {
    <#
    .SYNOPSIS
        The plan's MSIX, signed with -Pfx or else a throwaway test certificate whose .cer lands beside it; throws unless -Publisher signed it.
    .PARAMETER Version
        Four fields, as an MSIX version must have.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'a throwaway password for the per-build test certificate')]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$ManifestTemplate,
        [Parameter(Mandatory)][string]$LogoPath,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$Version,
        [string]$Publisher = 'CN=Kataglyphis',
        [string]$Pfx = ''
    )
    $outFile = $Plan.Msix
    $signing = Join-Path $Plan.WorkDir 'msix-signing'
    $stage = Join-Path $Plan.WorkDir 'msix-stage'
    Initialize-BuildDirectory -Path @($signing, $stage) -Empty
    $passwordBefore = $env:MSIX_PFX_PASSWORD
    try {
        if ($Pfx) {
            Copy-Item -LiteralPath $Pfx -Destination $signing
        } else {
            $env:MSIX_PFX_PASSWORD = [Guid]::NewGuid().ToString('N')
            $null = New-TestSigningCertificate -Subject $Publisher -PfxPath (Join-Path $signing 'test.pfx') `
                -CerPath ($outFile -replace '\.msix$', '-testcert.cer') -Password (ConvertTo-SecureString $env:MSIX_PFX_PASSWORD -AsPlainText -Force)
        }
        Invoke-MsixPackage -Context $Context -StagingDir $stage -ManifestTemplatePath $ManifestTemplate `
            -TokenMap @{ '__PUBLISHER__' = $Publisher; '__VERSION__' = $Version; '__ARCH__' = $Plan.Arch } `
            -ResourcesDir $Plan.AppDir -LogoPath $LogoPath -OutputPath $outFile -SigningRoot $signing `
            -RequireSignature -SignerSubject $Publisher | Out-Null
    } finally {
        $env:MSIX_PFX_PASSWORD = $passwordBefore
        Remove-Item -LiteralPath $signing -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "wrote $outFile ($([math]::Round((Get-Item -LiteralPath $outFile).Length / 1MB)) MB), signed by $Publisher"
}

function Assert-AppInstallerLicense {
    <#
    .SYNOPSIS
        The three licence checks every installer of the plan passes: the project LICENSE as Flutter's NOTICES, the third-party inventory beside it, and ONNX Runtime's wheel texts.
    .PARAMETER Path
        The plan's MSI or MSIX; an MSI's ONNX Runtime texts are found through the plan's payload fragment.
    #>
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$Path)
    $license = Join-Path $Plan.RepoRoot 'LICENSE'
    $prefix = $Plan.Notice.Substring(0, $Plan.Notice.LastIndexOf('/') + 1)
    $format = if ([IO.Path]::GetExtension($Path) -ieq '.msi') { 'msi' } else { 'archive' }
    if ($format -eq 'msi') { Assert-MsiPackageLicense -Path $Path -FileName $Plan.Notice.Substring($prefix.Length) -LicensePath $license }
    else { Assert-PackageLicense -Path $Path -Pattern $Plan.Notice -LicensePath $license }
    Assert-ThirdPartyLicensePackage -Path $Path -RepoRoot $Plan.RepoRoot -Asset $Plan.Asset -MemberPrefix $prefix
    Assert-OrtWheelLicensesInPackage -Path $Path -LicenseDirectory $Plan.OrtLicenseDirectory -Format $format -WixPath $Plan.Fragment
}

Export-ModuleMember -Function New-AppInstallerPlan, New-AppMsi, New-AppMsix, Assert-AppInstallerLicense
