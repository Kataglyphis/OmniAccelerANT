#requires -Version 7.0

# Wraps scripts/licenses for the Windows packagers; the package verdicts are the hub's WindowsMsiLicense.Common.

Set-StrictMode -Version Latest

function Get-ThirdPartyLicenseAsset {
    <#
    .SYNOPSIS
        The shipped inventory files, repo-relative with forward slashes.
    #>
    param([Parameter(Mandatory)][string] $RepoRoot, [string] $PythonPath = 'python')
    $assets = @(& $PythonPath (Join-Path $RepoRoot 'scripts/licenses/generate-third-party-licenses.py') --list-assets)
    if ($LASTEXITCODE -ne 0 -or $assets.Count -eq 0) { throw 'the third-party license inventory lists no assets' }
    return $assets
}

function Assert-NativeLicenseCoverage {
    <#
    .SYNOPSIS
        Fails when a native file under Path has no component in scripts/licenses/native-components.json.
    #>
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $RepoRoot, [string] $PythonPath = 'python')
    & $PythonPath (Join-Path $RepoRoot 'scripts/licenses/check-native-coverage.py') --platform windows $Path
    if ($LASTEXITCODE -ne 0) { throw "a native file in $Path has no third-party license entry" }
}

function Assert-ThirdPartyLicensePackage {
    <#
    .SYNOPSIS
        Checks every inventory file byte for byte in an MSI (by file name) or an archive (under MemberPrefix).
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string[]] $Asset,
        [string] $MemberPrefix = '*flutter_assets/'
    )
    $isMsi = [IO.Path]::GetExtension($Path) -ieq '.msi'
    foreach ($item in $Asset) {
        $license = Join-Path $RepoRoot $item
        if ($isMsi) { Assert-MsiPackageLicense -Path $Path -FileName (Split-Path $item -Leaf) -LicensePath $license }
        else { Assert-PackageLicense -Path $Path -Pattern "$MemberPrefix$item" -LicensePath $license }
    }
}

Export-ModuleMember -Function Get-ThirdPartyLicenseAsset, Assert-NativeLicenseCoverage, Assert-ThirdPartyLicensePackage
