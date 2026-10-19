#requires -Version 7.0
# An MSI and a signed MSIX from an app folder, for Package-OmniAccelerANT.ps1 and Package-ObservANT.ps1; the callers import WindowsMsix.Common and WindowsMsix.Signing.

Set-StrictMode -Version Latest

function New-AppMsi {
    <#
    .SYNOPSIS
        One MSI of -AppDir through the hub's Invoke-MsiPackage: -ExeName is the .wxs's own file, every other file a payload component.
    #>
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AppDir,
        [Parameter(Mandatory)][string]$ExeName,
        [Parameter(Mandatory)][string]$WxsFile,
        [Parameter(Mandatory)][string]$LicenseFile,
        [Parameter(Mandatory)][string]$ProductName,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string]$FragmentPath,
        [string[]]$Extensions = @('WixToolset.UI.wixext')
    )
    $exe = Join-Path $AppDir $ExeName
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "no $ExeName in $AppDir" }
    $payloadFiles = @(Get-ChildItem -LiteralPath $AppDir -Recurse -File | Where-Object FullName -ne $exe | ForEach-Object {
            $sub = [IO.Path]::GetRelativePath($AppDir, $_.DirectoryName)
            [pscustomobject]@{ Source = $_.FullName; Subdirectory = $(if ($sub -eq '.') { '' } else { $sub }) }
        })
    Invoke-MsiPackage -Context $Context -WxsFile $WxsFile -LicenseFile $LicenseFile -ProductName $ProductName -Manufacturer 'Kataglyphis' `
        -ExeSource $exe -Version $Version -OutFile $OutFile -Arch $Arch -PayloadFiles $payloadFiles -FragmentPath $FragmentPath `
        -Extensions $Extensions | Out-Null
    Write-Host "wrote $OutFile ($([math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB)) MB, $($payloadFiles.Count + 1) files)"
}

function New-AppMsix {
    <#
    .SYNOPSIS
        One MSIX of -AppDir, signed with -Pfx or else a throwaway test certificate whose .cer lands beside it; throws unless -Publisher signed it.
    .PARAMETER Version
        Four fields, as an MSIX version must have.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'a throwaway password for the per-build test certificate')]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AppDir,
        [Parameter(Mandatory)][string]$ManifestTemplate,
        [Parameter(Mandatory)][string]$LogoPath,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$Version,
        [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string]$WorkDir,
        [string]$Publisher = 'CN=Kataglyphis',
        [string]$Pfx = ''
    )
    $signing = Join-Path $WorkDir 'msix-signing'
    $stage = Join-Path $WorkDir 'msix-stage'
    foreach ($d in $signing, $stage) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
    $null = New-Item -ItemType Directory -Force -Path $signing
    $passwordBefore = $env:MSIX_PFX_PASSWORD
    try {
        if ($Pfx) {
            Copy-Item -LiteralPath $Pfx -Destination $signing
        } else {
            $env:MSIX_PFX_PASSWORD = [Guid]::NewGuid().ToString('N')
            $null = New-TestSigningCertificate -Subject $Publisher -PfxPath (Join-Path $signing 'test.pfx') `
                -CerPath ($OutFile -replace '\.msix$', '-testcert.cer') -Password (ConvertTo-SecureString $env:MSIX_PFX_PASSWORD -AsPlainText -Force)
        }
        Invoke-MsixPackage -Context $Context -StagingDir $stage -ManifestTemplatePath $ManifestTemplate `
            -TokenMap @{ '__PUBLISHER__' = $Publisher; '__VERSION__' = $Version; '__ARCH__' = $Arch } `
            -ResourcesDir $AppDir -LogoPath $LogoPath -OutputPath $OutFile -SigningRoot $signing `
            -RequireSignature -SignerSubject $Publisher | Out-Null
    } finally {
        $env:MSIX_PFX_PASSWORD = $passwordBefore
        Remove-Item -LiteralPath $signing -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "wrote $OutFile ($([math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB)) MB), signed by $Publisher"
}

Export-ModuleMember -Function New-AppMsi, New-AppMsix
