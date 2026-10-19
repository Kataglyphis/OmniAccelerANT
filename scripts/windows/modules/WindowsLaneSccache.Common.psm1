#requires -Version 7.0

# The host's sccache S3 key for a local Linux lane; the Windows CI cache is the hub's Restore-CiCompilerCache.

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

Export-ModuleMember -Function Get-SccacheS3HostFilePath, Read-SccacheS3HostFile, New-LaneSccacheS3Secret, Remove-LaneSccacheS3Secret
