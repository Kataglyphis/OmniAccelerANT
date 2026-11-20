#requires -Version 7.0
<#
.SYNOPSIS
    Runs the real Windows packager on a lock naming another model and checks the finished zip; it does not build the MSI or MSIX, or run that model.
#>
param(
    [Parameter(Mandatory)][string]$WebRoot,
    [Parameter(Mandatory)][string]$Packages
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$package = 'omni-observant'
$fixture = 'fixture_detector'
$shipped = [IO.Path]::GetFileNameWithoutExtension(@(& (Join-Path $PSScriptRoot '..\Get-DetectorModelFile.ps1'))[0])
$work = Join-Path ([IO.Path]::GetTempPath()) "observant-fixture-$PID"
$source = Join-Path $work 'source'
$out = Join-Path $work 'out'
$null = New-Item -ItemType Directory -Force -Path $source, $out
$env:KATAGLYPHIS_MODEL_CACHE = Join-Path $work 'cache'

# Opens ZIP, hands its one entry named NAME and the archive to USE, and returns what USE returns.
function Use-ZipEntry([string]$Zip, [string]$Name, [scriptblock]$Use) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $found = @($archive.Entries | Where-Object { $_.Name -ceq $Name })
        if ($found.Count -ne 1) { throw "expected one $Name in $(Split-Path -Leaf $Zip), found $($found.Count)" }
        & $Use $found[0] $archive
    } finally { $archive.Dispose() }
}

$lock = Join-Path $work 'models.lock'
$rows = foreach ($suffix in 'onnx', 'LICENSE', 'NOTICE') {
    $path = Join-Path $source "$fixture.$suffix"
    Set-Content -LiteralPath $path -Value "fixture $suffix"
    "$((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant())  $fixture.$suffix  $([Uri]::new($path).AbsoluteUri)"
}
Set-Content -LiteralPath $lock -Value $rows

# The producer of the zip this job just built: a second cargo build would prove nothing more.
$built = @(Get-ChildItem -Path (Join-Path $Packages "$package-*-windows-*.zip") -File)
if ($built.Count -ne 1) { throw "expected one built zip in $Packages, found $($built.Count)" }
$producer = Join-Path $work 'kataglyphis_observant.exe'
Use-ZipEntry $built[0].FullName 'kataglyphis_observant.exe' { param($exe) [IO.Compression.ZipFileExtensions]::ExtractToFile($exe, $producer) }

& (Join-Path $PSScriptRoot 'Package-ObservANT.ps1') -WebRoot $WebRoot -Producer $producer -ModelsLock $lock -OutDir $out -SkipMsi

$finished = @(Get-ChildItem -Path (Join-Path $out "$package-*-windows-*.zip") -File)
if ($finished.Count -ne 1) { throw "expected one fixture zip, found $($finished.Count)" }
$entries, $modelHash = Use-ZipEntry $finished[0].FullName "$fixture.onnx" {
    param($model, $archive)
    $stream = $model.Open()
    try { $hash = (Get-FileHash -Algorithm SHA256 -InputStream $stream).Hash } finally { $stream.Dispose() }
    , @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $hash
}
if (-not @($entries | Where-Object { $_ -like "*/models/$fixture.onnx" })) { throw "the zip does not carry models/$fixture.onnx" }
if ($modelHash -cne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $source "$fixture.onnx")).Hash) { throw 'the model is not the fixture lock''s bytes' }
foreach ($notice in "$fixture.LICENSE", "$fixture.NOTICE") {
    if (-not @($entries | Where-Object { $_ -like "*/$notice" })) { throw "the zip does not carry $notice" }
}
$foreign = @($entries | Where-Object { $_ -like "*$shipped*" })
if ($foreign.Count -gt 0) { throw "the zip still carries $shipped`: $($foreign -join ', ')" }
Write-Host "PASS  the finished zip carries $fixture and not $shipped"
