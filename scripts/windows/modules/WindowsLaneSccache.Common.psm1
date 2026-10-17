#requires -Version 7.0

# sccache's lane levels: the host's S3 key for a local Linux lane, and the Windows CI cache kept across runs.

Set-StrictMode -Version Latest

# Set-SccacheS3Level.ps1's Windows settings, by the name set-sccache-s3-level.sh writes each under on a Linux host.
$script:HostFileNames = [ordered]@{
    KATAGLYPHIS_SCCACHE_S3_ENDPOINT          = 'SCCACHE_ENDPOINT'
    KATAGLYPHIS_SCCACHE_S3_BUCKET            = 'SCCACHE_BUCKET'
    KATAGLYPHIS_SCCACHE_S3_REGION            = 'SCCACHE_REGION'
    KATAGLYPHIS_SCCACHE_S3_ACCESS_KEY_ID     = 'AWS_ACCESS_KEY_ID'
    KATAGLYPHIS_SCCACHE_S3_SECRET_ACCESS_KEY = 'AWS_SECRET_ACCESS_KEY'
}
# What the container's library passes to the server; it ignores every other name.
$script:SecretNames = 'SCCACHE_BUCKET', 'SCCACHE_ENDPOINT', 'SCCACHE_REGION', 'SCCACHE_S3_USE_SSL', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY'

function Get-SccacheS3HostFilePath {
    if ($env:KATAGLYPHIS_SCCACHE_S3_FILE) { return $env:KATAGLYPHIS_SCCACHE_S3_FILE }
    $config = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    return (Join-Path $config 'kataglyphis/sccache-s3.env')
}

function Read-SccacheS3HostFile {
    # NAME=value lines as a map; an absent file is an empty one.
    param([Parameter(Mandatory)][string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([A-Z0-9_]+)=(.*)$') { $values[$Matches[1]] = $Matches[2] }
    }
    return $values
}

function New-LaneSccacheS3Secret {
    <#
    .SYNOPSIS
        Writes the S3 level the lane's sccache server joins, and returns the file to bind at /run/secrets/sccache_s3.
    .DESCRIPTION
        The settings come from the KATAGLYPHIS_SCCACHE_S3_* variables (Windows) or the host file (Linux), and the hub's
        Get-HostSccacheS3ExecEnv decides whether the level is complete and answers. $null means the lane runs on disk alone.
    .OUTPUTS
        [string] - the file's path, or $null.
    #>
    param(
        [string]$HostFile = (Get-SccacheS3HostFilePath),
        [string]$Directory = [IO.Path]::GetTempPath(),
        # Reads a KATAGLYPHIS_SCCACHE_S3_* setting; the default asks the host's environment, then the host file.
        [scriptblock]$Lookup
    )
    if ("$env:KATAGLYPHIS_SCCACHE_S3" -in 'off', '0', 'false', 'no') { return $null }
    if (-not $Lookup) {
        $fromFile = Read-SccacheS3HostFile -Path $HostFile
        $names = $script:HostFileNames
        $Lookup = {
            param($name)
            $value = Get-HostSettingValue $name
            if (-not $value -and $names.Contains($name)) { $value = "$($fromFile[$names[$name]])" }
            return $value
        }.GetNewClosure()
    }
    $s3 = Get-HostSccacheS3ExecEnv -WebdavEndpoint '' -Lookup $Lookup
    if ($s3.Count -eq 0) { return $null }

    $dir = Join-Path $Directory ('kataglyphis-lane-sccache-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $dir
    # The container's uid 1001 reads the file through the bind, and the private directory keeps the host's other users out.
    if (-not $IsWindows) { chmod 700 $dir }
    $file = Join-Path $dir 'sccache_s3'
    $lines = foreach ($name in $script:SecretNames) { if ($s3.Contains($name)) { "$name=$($s3[$name])" } }
    Set-Content -LiteralPath $file -Value $lines -Encoding ascii
    if (-not $IsWindows) { chmod 644 $file }
    return $file
}

function Remove-LaneSccacheS3Secret {
    # Removes what New-LaneSccacheS3Secret wrote; a $null path is a no-op.
    param([AllowNull()][AllowEmptyString()][string]$Path)
    if ($Path) { Remove-Item -LiteralPath (Split-Path -Parent $Path) -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SccacheModuleSafe {
    <#
    .SYNOPSIS
        $true when this sccache keys a clang-cl C++20 module importer on the interfaces it imports (mozilla/sccache#2876).
    .DESCRIPTION
        0.18.0 and older serve stale importer objects, so a cache kept across CI runs is safe only on the hub's build
        (0.18.0+<rev>.<patches>, shared/upstream/sccache/README.md) or a release cut after the fix, 0.19.0 on.
    #>
    param([AllowEmptyString()][string]$VersionText)
    if ($VersionText -notmatch '(\d+)\.(\d+)\.(\d+)(\+\S+)?') { return $false }
    if ($Matches[4]) { return $true }
    return ([version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" -ge [version]'0.19.0')
}

function Move-CompilerCacheTree {
    # Moves a cache directory's content; a missing source is an empty cache, not an error.
    param([Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To)
    if (-not (Test-Path -LiteralPath $From)) { return }
    $null = New-Item -ItemType Directory -Force -Path $To
    & robocopy $From $To /E /MOVE /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy $From -> $To failed with exit code $LASTEXITCODE" }
    $global:LASTEXITCODE = 0
}

Export-ModuleMember -Function Get-SccacheS3HostFilePath, Read-SccacheS3HostFile, New-LaneSccacheS3Secret, Remove-LaneSccacheS3Secret,
    Test-SccacheModuleSafe, Move-CompilerCacheTree
