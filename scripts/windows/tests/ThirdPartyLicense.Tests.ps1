#requires -Version 7.0

# Tests the Windows wrappers over scripts/licenses on synthetic payloads; real MSI cabinets are the packagers' job. Pester 3.4.0 dialect.

Describe 'WindowsThirdPartyLicense.Common' {

    # Pester 3.4 under pwsh 7 has no working `Should Throw`.
    function Get-ThrowMessage([scriptblock] $Block) {
        try { & $Block | Out-Null } catch { return "$($_.Exception.Message)" }
        return ''
    }

    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsMsiLicense.Common', 'WindowsThirdPartyLicense.Common')
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $work = Join-Path ([IO.Path]::GetTempPath()) "third-party-license-$PID"
    $null = New-Item -ItemType Directory -Force -Path $work
    $assets = @(Get-ThirdPartyLicenseAsset -RepoRoot $repoRoot)

    It 'lists the index and its text files' {
        ($assets -contains 'assets/licenses/third-party-licenses.json') | Should Be $true
        $assets.Count -gt 1 | Should Be $true
    }

    It 'accepts a payload whose native files all have an entry, and refuses an unknown DLL' {
        $payload = Join-Path $work 'payload'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $payload 'gstreamer-1.0')
        Set-Content -LiteralPath (Join-Path $payload 'omni_accelerant.exe') -Value ''
        Set-Content -LiteralPath (Join-Path $payload 'gstreamer-1.0\gstapp.dll') -Value ''
        Get-ThrowMessage { Assert-NativeLicenseCoverage -Path $payload -RepoRoot $repoRoot } | Should Be ''
        Set-Content -LiteralPath (Join-Path $payload 'x264-164.dll') -Value ''
        Get-ThrowMessage { Assert-NativeLicenseCoverage -Path $payload -RepoRoot $repoRoot } | Should Match 'no third-party license entry'
    }

    It 'requires every inventory file in an archive, byte for byte' {
        $good = Join-Path $work 'good.zip'
        $bare = Join-Path $work 'bare.zip'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        foreach ($zip in $good, $bare) {
            if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
            $archive = [IO.Compression.ZipFile]::Open($zip, 'Create')
            try {
                $members = if ($zip -eq $good) { $assets } else { @($assets[0]) }
                foreach ($asset in $members) {
                    $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $repoRoot $asset), "data/flutter_assets/$asset")
                }
            } finally { $archive.Dispose() }
        }
        Get-ThrowMessage { Assert-ThirdPartyLicensePackage -Path $good -RepoRoot $repoRoot -Asset $assets } | Should Be ''
        Get-ThrowMessage { Assert-ThirdPartyLicensePackage -Path $bare -RepoRoot $repoRoot -Asset $assets } | Should Match 'license verification failed'
    }

    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
