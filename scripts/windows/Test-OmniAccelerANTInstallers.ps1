#requires -Version 7.0
<#
.SYNOPSIS
    Installs the OmniAccelerANT MSI and MSIX the way a user does, starts each, and removes each; on the runner, as admin.
.DESCRIPTION
    Each check prints PASS or FAIL; the exit code is the number of failures. The MSI's app starts through
    Test-LaunchSmoke.ps1 from Program Files without any PATH help, as the Start menu shortcut starts it, so every DLL it
    loads at start must sit beside it or in Windows. The MSIX is read for its signature, identity and architecture,
    installed once its test certificate is trusted, started through its app entry and removed again.
.PARAMETER Msi
    The omni-accelerant-<version>-windows-<arch>.msi; a wildcard naming exactly one file works too.
.PARAMETER Msix
    The matching .msix; its -testcert.cer must sit beside it unless -Publisher's certificate is trusted already.
.PARAMETER Arch
    x64 or arm64: the machine every installed binary must be built for.
#>
param(
    [Parameter(Mandatory)][string]$Msi,
    [Parameter(Mandatory)][string]$Msix,
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
    [string]$Publisher = 'CN=Kataglyphis',
    [ValidateRange(1, 600)][int]$Seconds = 20,
    [switch]$CheckOnnx
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsTargetArch.Common', 'WindowsSmokeTest.Common')
Initialize-SmokeTestRun
$product = 'OmniAccelerANT'
$exeName = 'omni_accelerant.exe'
$identityName = 'Kataglyphis.OmniAccelerANT'
$prefix = Join-Path $env:ProgramFiles $product
$machine = Get-PeMachineType -Arch $Arch
$modelFiles = @('deim_dfine_n_coco.onnx', 'deim_dfine_n_coco.LICENSE', 'deim_dfine_n_coco.NOTICE')

function Resolve-One([string]$Pattern, [string]$What) {
    $found = @(Get-ChildItem -Path $Pattern -File)
    if ($found.Count -ne 1) { throw "-$What must name exactly one file; $Pattern matches $($found.Count)" }
    return $found[0].FullName
}
$Msi = Resolve-One $Msi 'Msi'
$Msix = Resolve-One $Msix 'Msix'
$launch = Join-Path $PSScriptRoot 'Test-LaunchSmoke.ps1'

Write-Host "=== the MSI: $Msi ==="
$log = Join-Path $env:TEMP "omni-accelerant-msi-$PID.log"
$p = Start-Process msiexec.exe -ArgumentList '/i', "`"$Msi`"", '/qn', '/l*v', "`"$log`"" -Wait -PassThru
Assert-Test -Name 'msiexec installs it silently' { $p.ExitCode -eq 0 }
Assert-Test -Name "it installs into $prefix, AccelerANTgine.dll beside the exe and no bin\" {
    (Test-Path -LiteralPath (Join-Path $prefix $exeName)) -and (Test-Path -LiteralPath (Join-Path $prefix 'AccelerANTgine.dll')) -and
    -not (Test-Path -LiteralPath (Join-Path $prefix 'bin'))
}
Assert-Test -Name ('the exe, the plugin and AccelerANTgine.dll are {0} binaries (0x{1:X4})' -f $Arch, $machine) {
    @($exeName, 'kataglyphis_native_inference_plugin.dll', 'AccelerANTgine.dll' | Where-Object { (Get-PeFileMachine -Path (Join-Path $prefix $_)) -ne $machine }).Count -eq 0
}
Assert-Test -Name 'the Start menu shortcut exists' {
    Test-Path -LiteralPath (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$product\$product.lnk")
}
Assert-Test -Name 'the installed MSI contains the model and its notices' {
    @($modelFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $prefix "resources\models\$_") -PathType Leaf) }).Count -eq 0
}
Assert-Test -Name "the installed app starts from Program Files without PATH help and is alive after $Seconds s" {
    & $launch -AppDir $prefix -Seconds $Seconds -OrtStamp | ForEach-Object { Write-Host "      $_" }
    $true
}
if ($CheckOnnx) {
    Assert-Test -Name 'the installed MSI runs the bundled model on ONNX Runtime CPU' {
        & (Join-Path $PSScriptRoot 'Test-OnnxSelfCheck.ps1') -AppDir $prefix
        $true
    }
}
$u = Start-Process msiexec.exe -ArgumentList '/x', "`"$Msi`"", '/qn' -Wait -PassThru
Assert-Test -Name 'msiexec removes it silently, and the exe with it' { $u.ExitCode -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $prefix $exeName)) }
if ($p.ExitCode -ne 0 -and (Test-Path -LiteralPath $log)) { Get-Content -LiteralPath $log -Tail 40 | ForEach-Object { Write-Host "      $_" } }

Write-Host "=== the MSIX: $Msix ==="
Assert-Test -Name "it is signed by $Publisher" { (Get-AuthenticodeSignature -LiteralPath $Msix).SignerCertificate.Subject -eq $Publisher }
$facts = Get-MsixArchiveInfo -Path $Msix
$manifest = $facts.Manifest
$entries = $facts.Entries
$ns = [System.Xml.XmlNamespaceManager]::new($manifest.NameTable)
$ns.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$identity = $manifest.SelectSingleNode('/m:Package/m:Identity', $ns)
# GetAttribute: unambiguous where an attribute shares its name with an XmlNode property.
Assert-Test -Name "its identity is $identityName for $Arch, published by $Publisher" {
    $identity.GetAttribute('Name') -eq $identityName -and $identity.GetAttribute('ProcessorArchitecture') -eq $Arch -and
    $identity.GetAttribute('Publisher') -eq $Publisher
}
Assert-Test -Name 'it carries the exe and AccelerANTgine.dll side by side' { $entries -contains $exeName -and $entries -contains 'AccelerANTgine.dll' }
Assert-Test -Name 'the MSIX contains the model and its notices' {
    @($modelFiles | Where-Object { $entries -cnotcontains "resources/models/$_" }).Count -eq 0
}

$cer = $Msix -replace '\.msix$', '-testcert.cer'
$trusted = $null
if (Test-Path -LiteralPath $cer) { $trusted = Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' }
try {
    Assert-Test -Name 'Add-AppxPackage installs it' { Add-AppxPackage -Path $Msix; [bool](Get-AppxPackage -Name $identityName) }
    $installed = Get-AppxPackage -Name $identityName
    if ($installed) {
        Assert-Test -Name "it starts through its app entry and is alive after $Seconds s" {
            Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exeName)) -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Process "shell:AppsFolder\$($installed.PackageFamilyName)!OmniAccelerANT"
            Start-Sleep -Seconds $Seconds
            $running = @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exeName)) -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -and $_.Path.StartsWith($installed.InstallLocation, [StringComparison]::OrdinalIgnoreCase) })
            $running | Stop-Process -Force
            $running.Count -ge 1
        }
        Remove-AppxPackage -Package $installed.PackageFullName
        Assert-Test -Name 'Remove-AppxPackage removes it' { -not (Get-AppxPackage -Name $identityName) }
    }
} finally {
    if ($trusted) { Remove-Item -LiteralPath "Cert:\LocalMachine\TrustedPeople\$($trusted.Thumbprint)" -ErrorAction SilentlyContinue }
}

$failed = (Get-SmokeTestSummary).Failed
Write-Host "$failed check(s) failed"
exit $failed
