#requires -Version 7.0
<#
.SYNOPSIS
    Checks the Windows cat cam MSIX: its signature and manifest anywhere, and with -Install the installed package too.
.DESCRIPTION
    Each check prints PASS or FAIL; the exit code is the number of failures. The static half reads the package itself,
    so it runs in :winamd64, where AppX deployment does not work. -Install needs a Windows desktop host whose
    LocalMachine\TrustedPeople already trusts the signing certificate (Package-CatCam.ps1 writes a test one beside
    the package); it installs for the current user, runs the omni-catcam alias, and removes the package again.
.PARAMETER Msix
    The omni-accelerant-catcam-<version>-windows-<arch>.msix; a wildcard naming exactly one file works too.
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

$packageName = 'Kataglyphis.OmniAccelerANTCatCam'
$msixFiles = @(Get-ChildItem -Path $Msix -File)
if ($msixFiles.Count -ne 1) { throw "-Msix must name exactly one MSIX; $Msix matches $($msixFiles.Count)" }
$Msix = $msixFiles[0].FullName
$script:failures = 0

function Test-Check {
    param([string]$Name, [scriptblock]$Condition)
    $ok = try { [bool](& $Condition) } catch { Write-Host "      $($_.Exception.Message)"; $false }
    if ($ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name"; $script:failures++ }
}

Write-Host '=== the package ==='
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
$ns.AddNamespace('desktop', 'http://schemas.microsoft.com/appx/manifest/desktop/windows10')
$ns.AddNamespace('desktop2', 'http://schemas.microsoft.com/appx/manifest/desktop/windows10/2')
$identity = $manifest.SelectSingleNode('/m:Package/m:Identity', $ns)
# GetAttribute: unambiguous where an attribute shares its name with an XmlNode property.
Test-Check 'its identity names the cat cam and the signing publisher' {
    $identity.GetAttribute('Name') -eq $packageName -and $identity.GetAttribute('Publisher') -eq $Publisher
}
Test-Check 'it starts at logon through a startup task' {
    $task = $manifest.SelectSingleNode('//desktop:StartupTask', $ns)
    $task -and $task.Enabled -eq 'true'
}
Test-Check 'it answers to omni-catcam from any shell' { $manifest.SelectSingleNode("//desktop:ExecutionAlias[@Alias='omni-catcam.exe']", $ns) }
Test-Check 'it opens 8080/tcp and the ICE range on private and domain networks only' {
    $rules = @($manifest.SelectNodes('//desktop2:Rule', $ns))
    $tcp = @($rules | Where-Object { $_.IPProtocol -eq 'TCP' -and $_.LocalPortMin -eq '8080' })
    $udp = @($rules | Where-Object { $_.IPProtocol -eq 'UDP' -and $_.LocalPortMin -eq '40000' -and $_.LocalPortMax -eq '40099' })
    $tcp.Count -eq 1 -and $udp.Count -eq 1 -and @($rules | Where-Object { $_.Profile -ne 'domainAndPrivate' }).Count -eq 0
}
Test-Check 'it carries the exe, its plugins, the scanner, ORT, the model and the page' {
    foreach ($e in 'kataglyphis_cat_webrtc.exe', 'onnxruntime.dll', 'lib/gstreamer-1.0/gstrswebrtc.dll',
        'libexec/gstreamer-1.0/gst-plugin-scanner.exe', 'models/yolo26n.onnx', 'web/index.html') {
        if ($entries -notcontains $e) { throw "missing from the package: $e" }
    }
    $true
}
if (-not $Install) {
    Write-Host "$($script:failures) failure(s)"
    exit $script:failures
}

Write-Host '=== installed for this user ==='
Add-AppxPackage -Path $Msix
$pkg = Get-AppxPackage -Name $packageName
Test-Check 'Add-AppxPackage installs it' { $pkg -and $pkg.Status -eq 'Ok' }
$alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\omni-catcam.exe'
Test-Check 'the omni-catcam alias is on PATH' { Test-Path $alias }
$exeInPackage = Join-Path $pkg.InstallLocation 'kataglyphis_cat_webrtc.exe'
if ((Get-Service MpsSvc -ErrorAction SilentlyContinue).Status -eq 'Running') {
    Test-Check 'Windows Firewall carries its two inbound rules' {
        $rules = @(Get-NetFirewallApplicationFilter -Program $exeInPackage -ErrorAction SilentlyContinue | Get-NetFirewallRule |
                Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' })
        foreach ($r in $rules) { Write-Host "      rule: $($r.DisplayName) profile=$($r.Profile) $(($r | Get-NetFirewallPortFilter | ForEach-Object { "$($_.Protocol) $($_.LocalPort)" }) -join ', ')" }
        $rules.Count -ge 2
    }
}
$taskKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$($pkg.PackageFamilyName)\CatCamAtLogon"
Write-Host "      startup task state: $(if (Test-Path $taskKey) { (Get-ItemProperty $taskKey).State } else { 'not registered yet' })"

$proc = Start-Process -FilePath $alias -ArgumentList '--camera', 'test', '--inference', 'off' -PassThru -WindowStyle Minimized
$health = $null
$deadline = (Get-Date).AddSeconds(40)
do {
    $health = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 http://127.0.0.1:8080/healthz).Content } catch { $null }
    if (-not $health) { Start-Sleep -Milliseconds 500 }
} until ($health -or (Get-Date) -gt $deadline)
Write-Host "      healthz: $health"
Test-Check 'started through the alias, it answers /healthz' { $health -match '"ok":true' }
$running = Get-Process kataglyphis_cat_webrtc -ErrorAction SilentlyContinue | Select-Object -First 1
$foreign = @($running.Modules | ForEach-Object FileName | Where-Object {
        -not $_.StartsWith($pkg.InstallLocation, [StringComparison]::OrdinalIgnoreCase) -and
        -not $_.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)
    })
if ($foreign) { Write-Host "      outside: $($foreign -join ', ')" }
Test-Check 'it loads modules only from its package and Windows' { $running -and $foreign.Count -eq 0 }
Get-Process kataglyphis_cat_webrtc -ErrorAction SilentlyContinue | Stop-Process -Force
if ($proc -and -not $proc.HasExited) { $proc.Kill() }

Write-Host '=== removed ==='
Remove-AppxPackage -Package $pkg.PackageFullName
Test-Check 'Remove-AppxPackage leaves no package and no alias' { -not (Get-AppxPackage -Name $packageName) -and -not (Test-Path $alias) }
Write-Host "$($script:failures) failure(s)"
exit $script:failures
