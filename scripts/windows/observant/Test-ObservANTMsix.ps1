#requires -Version 7.0
<#
.SYNOPSIS
    Checks the Windows ObservANT MSIX: its signature and manifest anywhere, and with -Install the installed package too.
.DESCRIPTION
    Each check prints PASS or FAIL; the exit code is the number of failures. The static half reads the package itself,
    so it runs in :winamd64, where AppX deployment does not work. -Install needs a Windows desktop host whose
    LocalMachine\TrustedPeople already trusts the signing certificate (Package-ObservANT.ps1 writes a test one beside
    the package); it installs for the current user, runs the omni-observant alias, and removes the package again.
.PARAMETER Msix
    The omni-observant-<version>-windows-<arch>.msix; a wildcard naming exactly one file works too.
.PARAMETER Publisher
    The publisher the package must be signed by.
#>
param(
    [Parameter(Mandatory)][string]$Msix,
    [string]$Publisher = 'CN=Kataglyphis',
    [switch]$Install
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
Import-BuildModule 'WindowsSmokeTest.Common'
Initialize-SmokeTestRun

$packageName = 'Kataglyphis.OmniAccelerANTObservANT'
$msixFiles = @(Get-ChildItem -Path $Msix -File)
if ($msixFiles.Count -ne 1) { throw "-Msix must name exactly one MSIX; $Msix matches $($msixFiles.Count)" }
$Msix = $msixFiles[0].FullName

Write-Host '=== the package ==='
Assert-Test -Name "it is signed by $Publisher" { (Get-AuthenticodeSignature -LiteralPath $Msix).SignerCertificate.Subject -eq $Publisher }
$facts = Get-MsixArchiveInfo -Path $Msix
$manifest = $facts.Manifest
$entries = $facts.Entries
$ns = [System.Xml.XmlNamespaceManager]::new($manifest.NameTable)
$ns.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$ns.AddNamespace('desktop', 'http://schemas.microsoft.com/appx/manifest/desktop/windows10')
$ns.AddNamespace('desktop2', 'http://schemas.microsoft.com/appx/manifest/desktop/windows10/2')
$identity = $manifest.SelectSingleNode('/m:Package/m:Identity', $ns)
# GetAttribute: unambiguous where an attribute shares its name with an XmlNode property.
Assert-Test -Name 'its identity names ObservANT and the signing publisher' {
    $identity.GetAttribute('Name') -eq $packageName -and $identity.GetAttribute('Publisher') -eq $Publisher
}
Assert-Test -Name 'it starts at logon through a startup task' {
    $task = $manifest.SelectSingleNode('//desktop:StartupTask', $ns)
    $task -and $task.Enabled -eq 'true'
}
Assert-Test -Name 'it answers to omni-observant from any shell' { $manifest.SelectSingleNode("//desktop:ExecutionAlias[@Alias='omni-observant.exe']", $ns) }
Assert-Test -Name 'it opens 8080/tcp and the ICE range on private and domain networks only' {
    $rules = @($manifest.SelectNodes('//desktop2:Rule', $ns))
    $tcp = @($rules | Where-Object { $_.IPProtocol -eq 'TCP' -and $_.LocalPortMin -eq '8080' })
    $udp = @($rules | Where-Object { $_.IPProtocol -eq 'UDP' -and $_.LocalPortMin -eq '40000' -and $_.LocalPortMax -eq '40099' })
    $tcp.Count -eq 1 -and $udp.Count -eq 1 -and @($rules | Where-Object { $_.Profile -ne 'domainAndPrivate' }).Count -eq 0
}
Assert-Test -Name 'it carries the exe, its plugins, the scanner, ORT, the model and the page' {
    foreach ($e in 'kataglyphis_observant.exe', 'onnxruntime.dll', 'lib/gstreamer-1.0/gstrswebrtc.dll',
        'libexec/gstreamer-1.0/gst-plugin-scanner.exe', 'models/deim_dfine_n_coco.onnx', 'web/index.html') {
        if ($entries -notcontains $e) { throw "missing from the package: $e" }
    }
    $true
}
if (-not $Install) {
    $failed = (Get-SmokeTestSummary).Failed
    Write-Host "$failed failure(s)"
    exit $failed
}

Write-Host '=== installed for this user ==='
Add-AppxPackage -Path $Msix
$pkg = Get-AppxPackage -Name $packageName
Assert-Test -Name 'Add-AppxPackage installs it' { $pkg -and $pkg.Status -eq 'Ok' }
$alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\omni-observant.exe'
Assert-Test -Name 'the omni-observant alias is on PATH' { Test-Path $alias }
$exeInPackage = Join-Path $pkg.InstallLocation 'kataglyphis_observant.exe'
if ((Get-Service MpsSvc -ErrorAction SilentlyContinue).Status -eq 'Running') {
    Assert-Test -Name 'Windows Firewall carries its two inbound rules' {
        $rules = @(Get-NetFirewallApplicationFilter -Program $exeInPackage -ErrorAction SilentlyContinue | Get-NetFirewallRule |
                Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' })
        foreach ($r in $rules) { Write-Host "      rule: $($r.DisplayName) profile=$($r.Profile) $(($r | Get-NetFirewallPortFilter | ForEach-Object { "$($_.Protocol) $($_.LocalPort)" }) -join ', ')" }
        $rules.Count -ge 2
    }
}
$taskKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$($pkg.PackageFamilyName)\ObservANTAtLogon"
Write-Host "      startup task state: $(if (Test-Path $taskKey) { (Get-ItemProperty $taskKey).State } else { 'not registered yet' })"

$proc = Start-Process -FilePath $alias -ArgumentList '--camera', 'test', '--inference', 'off' -PassThru -WindowStyle Minimized
$health = $null
$deadline = (Get-Date).AddSeconds(40)
do {
    $health = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 http://127.0.0.1:8080/healthz).Content } catch { $null }
    if (-not $health) { Start-Sleep -Milliseconds 500 }
} until ($health -or (Get-Date) -gt $deadline)
Write-Host "      healthz: $health"
Assert-Test -Name 'started through the alias, it answers /healthz' { $health -match '"ok":true' }
$running = Get-Process kataglyphis_observant -ErrorAction SilentlyContinue | Select-Object -First 1
$foreign = @($running.Modules | ForEach-Object FileName | Where-Object {
        -not $_.StartsWith($pkg.InstallLocation, [StringComparison]::OrdinalIgnoreCase) -and
        -not $_.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)
    })
if ($foreign) { Write-Host "      outside: $($foreign -join ', ')" }
Assert-Test -Name 'it loads modules only from its package and Windows' { $running -and $foreign.Count -eq 0 }
Get-Process kataglyphis_observant -ErrorAction SilentlyContinue | Stop-Process -Force
if ($proc -and -not $proc.HasExited) { $proc.Kill() }

Write-Host '=== removed ==='
Remove-AppxPackage -Package $pkg.PackageFullName
Assert-Test -Name 'Remove-AppxPackage leaves no package and no alias' { -not (Get-AppxPackage -Name $packageName) -and -not (Test-Path $alias) }
$failed = (Get-SmokeTestSummary).Failed
Write-Host "$failed failure(s)"
exit $failed
