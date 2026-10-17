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
    [ValidateRange(1, 600)][int]$Seconds = 20
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$product = 'OmniAccelerANT'
$exeName = 'omni_accelerant.exe'
$identityName = 'Kataglyphis.OmniAccelerANT'
$prefix = Join-Path $env:ProgramFiles $product
$machine = @{ x64 = 0x8664; arm64 = 0xAA64 }[$Arch]
$script:failures = 0

function Resolve-One([string]$Pattern, [string]$What) {
    $found = @(Get-ChildItem -Path $Pattern -File)
    if ($found.Count -ne 1) { throw "-$What must name exactly one file; $Pattern matches $($found.Count)" }
    return $found[0].FullName
}
function Test-Check {
    param([string]$Name, [scriptblock]$Condition)
    $ok = try { [bool](& $Condition) } catch { Write-Host "      $($_.Exception.Message)"; $false }
    if ($ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name"; $script:failures++ }
}
# The COFF machine of a PE file, 4 bytes past the 'PE\0\0' signature e_lfanew points at.
function Get-PeMachine([string]$Path) {
    $head = [IO.File]::ReadAllBytes($Path)
    return [BitConverter]::ToUInt16($head, [BitConverter]::ToInt32($head, 0x3C) + 4)
}
$Msi = Resolve-One $Msi 'Msi'
$Msix = Resolve-One $Msix 'Msix'
$launch = Join-Path $PSScriptRoot 'Test-LaunchSmoke.ps1'

Write-Host "=== the MSI: $Msi ==="
$log = Join-Path $env:TEMP "omni-accelerant-msi-$PID.log"
$p = Start-Process msiexec.exe -ArgumentList '/i', "`"$Msi`"", '/qn', '/l*v', "`"$log`"" -Wait -PassThru
Test-Check 'msiexec installs it silently' { $p.ExitCode -eq 0 }
Test-Check "it installs into $prefix, AccelerANTgine.dll beside the exe and no bin\" {
    (Test-Path -LiteralPath (Join-Path $prefix $exeName)) -and (Test-Path -LiteralPath (Join-Path $prefix 'AccelerANTgine.dll')) -and
    -not (Test-Path -LiteralPath (Join-Path $prefix 'bin'))
}
Test-Check ('the exe, the plugin and AccelerANTgine.dll are {0} binaries (0x{1:X4})' -f $Arch, $machine) {
    @($exeName, 'kataglyphis_native_inference_plugin.dll', 'AccelerANTgine.dll' | Where-Object { (Get-PeMachine (Join-Path $prefix $_)) -ne $machine }).Count -eq 0
}
Test-Check 'the Start menu shortcut exists' {
    Test-Path -LiteralPath (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$product\$product.lnk")
}
Test-Check "the installed app starts from Program Files without PATH help and is alive after $Seconds s" {
    & $launch -AppDir $prefix -Seconds $Seconds -OrtStamp | ForEach-Object { Write-Host "      $_" }
    $true
}
$u = Start-Process msiexec.exe -ArgumentList '/x', "`"$Msi`"", '/qn' -Wait -PassThru
Test-Check 'msiexec removes it silently, and the exe with it' { $u.ExitCode -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $prefix $exeName)) }
if ($p.ExitCode -ne 0 -and (Test-Path -LiteralPath $log)) { Get-Content -LiteralPath $log -Tail 40 | ForEach-Object { Write-Host "      $_" } }

Write-Host "=== the MSIX: $Msix ==="
Test-Check "it is signed by $Publisher" { (Get-AuthenticodeSignature -LiteralPath $Msix).SignerCertificate.Subject -eq $Publisher }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($Msix)
try {
    $reader = [System.IO.StreamReader]::new($zip.GetEntry('AppxManifest.xml').Open())
    [xml]$manifest = $reader.ReadToEnd()
    $reader.Dispose()
    $entries = @($zip.Entries | ForEach-Object FullName)
} finally { $zip.Dispose() }
$ns = [System.Xml.XmlNamespaceManager]::new($manifest.NameTable)
$ns.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$identity = $manifest.SelectSingleNode('/m:Package/m:Identity', $ns)
# GetAttribute: unambiguous where an attribute shares its name with an XmlNode property.
Test-Check "its identity is $identityName for $Arch, published by $Publisher" {
    $identity.GetAttribute('Name') -eq $identityName -and $identity.GetAttribute('ProcessorArchitecture') -eq $Arch -and
    $identity.GetAttribute('Publisher') -eq $Publisher
}
Test-Check 'it carries the exe and AccelerANTgine.dll side by side' { $entries -contains $exeName -and $entries -contains 'AccelerANTgine.dll' }

$cer = $Msix -replace '\.msix$', '-testcert.cer'
$trusted = $null
if (Test-Path -LiteralPath $cer) { $trusted = Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' }
try {
    Test-Check 'Add-AppxPackage installs it' { Add-AppxPackage -Path $Msix; [bool](Get-AppxPackage -Name $identityName) }
    $installed = Get-AppxPackage -Name $identityName
    if ($installed) {
        Test-Check "it starts through its app entry and is alive after $Seconds s" {
            Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exeName)) -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Process "shell:AppsFolder\$($installed.PackageFamilyName)!OmniAccelerANT"
            Start-Sleep -Seconds $Seconds
            $running = @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exeName)) -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -and $_.Path.StartsWith($installed.InstallLocation, [StringComparison]::OrdinalIgnoreCase) })
            $running | Stop-Process -Force
            $running.Count -ge 1
        }
        Remove-AppxPackage -Package $installed.PackageFullName
        Test-Check 'Remove-AppxPackage removes it' { -not (Get-AppxPackage -Name $identityName) }
    }
} finally {
    if ($trusted) { Remove-Item -LiteralPath "Cert:\LocalMachine\TrustedPeople\$($trusted.Thumbprint)" -ErrorAction SilentlyContinue }
}

Write-Host "$script:failures check(s) failed"
exit $script:failures
