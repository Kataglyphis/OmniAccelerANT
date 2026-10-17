#requires -Version 7.0

# The S3 level a local Linux lane's sccache joins: what reaches the file, and when there is none. Pester 3.4.0 dialect.

Describe 'WindowsLaneSccache.Common' {

    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule 'WindowsScripts.Shared'
    Import-BuildModule 'WindowsContainerBuild.Reuse'
    Import-BuildModule 'WindowsLaneSccache.Common'

    $work = Join-Path ([IO.Path]::GetTempPath()) ('lane-sccache-tests-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $work
    # A listener, so the hub's reachability probe answers without the real bucket.
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $endpoint = "http://127.0.0.1:$($listener.LocalEndpoint.Port)"
    $settings = @{
        KATAGLYPHIS_SCCACHE_S3_ENDPOINT          = $endpoint
        KATAGLYPHIS_SCCACHE_S3_BUCKET            = 'sccache'
        KATAGLYPHIS_SCCACHE_S3_REGION            = 'garage'
        KATAGLYPHIS_SCCACHE_S3_ACCESS_KEY_ID     = 'GKtest'
        KATAGLYPHIS_SCCACHE_S3_SECRET_ACCESS_KEY = 's3cret'
    }
    # Built here, not in an It: GetNewClosure copies only its own scope, and $settings lives in this one.
    $lookup = { param($name) "$($settings[$name])" }.GetNewClosure()
    $noKey = { param($name) if ($name -like '*SECRET*') { '' } else { "$($settings[$name])" } }.GetNewClosure()
    $dead = { param($name) if ($name -like '*ENDPOINT') { 'http://127.0.0.1:1' } else { "$($settings[$name])" } }.GetNewClosure()

    It 'writes the six names the container library passes on, and nothing else' {
        $file = New-LaneSccacheS3Secret -Directory $work -Lookup $lookup
        $lines = @(Get-Content -LiteralPath $file)
        ($lines -join '|') | Should Be "SCCACHE_BUCKET=sccache|SCCACHE_ENDPOINT=$endpoint|SCCACHE_REGION=garage|SCCACHE_S3_USE_SSL=false|AWS_ACCESS_KEY_ID=GKtest|AWS_SECRET_ACCESS_KEY=s3cret"
        Remove-LaneSccacheS3Secret $file
        (Test-Path -LiteralPath (Split-Path -Parent $file)) | Should Be $false
    }

    It 'keeps the directory private and the file readable for the container uid' {
        if ($IsWindows) { return }
        $file = New-LaneSccacheS3Secret -Directory $work -Lookup $lookup
        (stat -c '%a' (Split-Path -Parent $file)) | Should Be '700'
        (stat -c '%a' $file) | Should Be '644'
        Remove-LaneSccacheS3Secret $file
    }

    It 'reads a Linux host file under the names set-sccache-s3-level.sh writes' {
        $hostFile = Join-Path $work 'sccache-s3.env'
        Set-Content -LiteralPath $hostFile -Value @(
            "SCCACHE_BUCKET=sccache", "SCCACHE_ENDPOINT=$endpoint", 'SCCACHE_REGION=garage',
            'SCCACHE_S3_USE_SSL=false', 'AWS_ACCESS_KEY_ID=GKfile', 'AWS_SECRET_ACCESS_KEY=fromfile')
        $file = New-LaneSccacheS3Secret -Directory $work -HostFile $hostFile
        ((Get-Content -LiteralPath $file) -join '|') | Should Match 'AWS_ACCESS_KEY_ID=GKfile\|AWS_SECRET_ACCESS_KEY=fromfile$'
        Remove-LaneSccacheS3Secret $file
    }

    It 'writes nothing without a key, for an unreachable bucket, or when switched off' {
        New-LaneSccacheS3Secret -Directory $work -Lookup $noKey 3>$null | Should BeNullOrEmpty
        New-LaneSccacheS3Secret -Directory $work -Lookup $dead 3>$null | Should BeNullOrEmpty
        $env:KATAGLYPHIS_SCCACHE_S3 = 'off'
        try { New-LaneSccacheS3Secret -Directory $work -Lookup $lookup | Should BeNullOrEmpty }
        finally { Remove-Item Env:\KATAGLYPHIS_SCCACHE_S3 }
        @(Get-ChildItem -LiteralPath $work -Directory).Count | Should Be 0
    }

    It 'treats an absent path as a no-op on removal' {
        { Remove-LaneSccacheS3Secret $null } | Should Not Throw
    }

    $listener.Stop()
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
