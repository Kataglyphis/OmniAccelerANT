#requires -Version 7.0
# What the app and ObservANT installer checks share; callers import WindowsSmokeTest.Common and the hub's MSIX reader first.

Set-StrictMode -Version Latest

function Resolve-OneFile {
    # A wildcard argument must select exactly one file, because the check would otherwise grade an arbitrary build.
    param([Parameter(Mandatory)][string] $Pattern, [Parameter(Mandatory)][string] $What, [string] $Noun = 'file')
    $found = @(Get-ChildItem -Path $Pattern -File)
    if ($found.Count -ne 1) { throw "-$What must name exactly one $Noun; $Pattern matches $($found.Count)" }
    return $found[0].FullName
}

function Get-CheckedMsixView {
    <#
    .SYNOPSIS
        Asserts the MSIX's signer, then returns its manifest, entries, foundation namespace table and Identity node.
    #>
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Publisher)
    Assert-Test -Name "it is signed by $Publisher" { (Get-AuthenticodeSignature -LiteralPath $Path).SignerCertificate.Subject -eq $Publisher }
    $facts = Get-MsixArchiveInfo -Path $Path
    $ns = [System.Xml.XmlNamespaceManager]::new($facts.Manifest.NameTable)
    $ns.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    return [pscustomobject]@{
        Manifest = $facts.Manifest
        Entries  = $facts.Entries
        Ns       = $ns
        Identity = $facts.Manifest.SelectSingleNode('/m:Package/m:Identity', $ns)
    }
}

function Assert-MsixIdentity {
    # GetAttribute: unambiguous where an attribute shares its name with an XmlNode property.
    param([Parameter(Mandatory)] $Identity, [Parameter(Mandatory)][string] $Label, [Parameter(Mandatory)][hashtable] $Expected)
    Assert-Test -Name $Label { @($Expected.Keys | Where-Object { $Identity.GetAttribute($_) -ne $Expected[$_] }).Count -eq 0 }
}

function Assert-Healthz {
    # Prints the body so a failing run shows what the service answered; returns it for further checks.
    param([Parameter(Mandatory)][string] $Label)
    $health = Wait-Healthz
    Write-Host "      healthz: $health"
    Assert-Test -Name $Label { $health -match '"ok":true' }
    return $health
}

function Install-MsiSilently {
    <#
    .SYNOPSIS
        msiexec /i with a verbose log, asserted to succeed; returns the process so a caller can show the log on failure.
    #>
    param([Parameter(Mandatory)][string] $Msi, [Parameter(Mandatory)][string] $LogPath)
    $process = Start-Process msiexec.exe -ArgumentList '/i', "`"$Msi`"", '/qn', '/l*v', "`"$LogPath`"" -Wait -PassThru
    Assert-Test -Name 'msiexec installs it silently' { $process.ExitCode -eq 0 }
    return $process
}

function Uninstall-MsiSilently {
    param([Parameter(Mandatory)][string] $Msi)
    return Start-Process msiexec.exe -ArgumentList '/x', "`"$Msi`"", '/qn' -Wait -PassThru
}

function Wait-Healthz {
    <#
    .SYNOPSIS
        The service's /healthz body on :8080 within 40 s, or $null.
    #>
    $deadline = (Get-Date).AddSeconds(40)
    do {
        $body = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 http://127.0.0.1:8080/healthz).Content } catch { $null }
        if ($body) { return $body }
        Start-Sleep -Milliseconds 500
    } until ((Get-Date) -gt $deadline)
    return $null
}

Export-ModuleMember -Function Resolve-OneFile, Get-CheckedMsixView, Assert-MsixIdentity, Assert-Healthz, Install-MsiSilently, Uninstall-MsiSilently, Wait-Healthz
