#requires -Version 7.0

# The S3 level a local Linux lane's sccache joins: what reaches the file, and when there is none.

Describe 'WindowsLaneSccache.Common' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
        Import-BuildModule 'WindowsScripts.Shared'
        Import-BuildModule 'WindowsContainerBuild.Reuse'
        Import-BuildModule 'WindowsLaneSccache.Common'
        $script:work = Join-Path ([IO.Path]::GetTempPath()) ('lane-sccache-tests-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:work
        # A listener, so the hub's reachability probe answers without the real bucket.
        $script:listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $script:listener.Start()
        $script:endpoint = "http://127.0.0.1:$($script:listener.LocalEndpoint.Port)"
        $settings = @{
            KATAGLYPHIS_SCCACHE_S3_ENDPOINT          = $script:endpoint
            KATAGLYPHIS_SCCACHE_S3_BUCKET            = 'sccache'
            KATAGLYPHIS_SCCACHE_S3_REGION            = 'garage'
            KATAGLYPHIS_SCCACHE_S3_ACCESS_KEY_ID     = 'GKtest'
            KATAGLYPHIS_SCCACHE_S3_SECRET_ACCESS_KEY = 's3cret'
        }
        # Built here, not in an It: GetNewClosure copies only its own scope, and $settings lives in this one.
        $script:lookup = { param($name) "$($settings[$name])" }.GetNewClosure()
        $script:noKey = { param($name) if ($name -like '*SECRET*') { '' } else { "$($settings[$name])" } }.GetNewClosure()
        $script:dead = { param($name) if ($name -like '*ENDPOINT') { 'http://127.0.0.1:1' } else { "$($settings[$name])" } }.GetNewClosure()
        # The secret file from a host file holding the given extra lines, checked against the key pair it must end with.
        function Assert-HostFileSecret([string] $Name, [string[]] $Extra, [scriptblock] $EnvLookup, [string] $Expected) {
            $hostFile = Join-Path $script:work $Name
            Set-Content -LiteralPath $hostFile -Value (@("SCCACHE_BUCKET=sccache", "SCCACHE_ENDPOINT=$script:endpoint", 'SCCACHE_REGION=garage') + $Extra + @('AWS_ACCESS_KEY_ID=GKfile', 'AWS_SECRET_ACCESS_KEY=fromfile'))
            $file = New-LaneSccacheS3Secret -Directory $script:work -HostFile $hostFile -EnvLookup $EnvLookup
            ((Get-Content -LiteralPath $file) -join '|') | Should -Match $Expected
            Remove-LaneSccacheS3Secret $file
        }
    }

    It 'writes the six names the container library passes on, and nothing else' {
        $file = New-LaneSccacheS3Secret -Directory $script:work -Lookup $script:lookup
        $lines = @(Get-Content -LiteralPath $file)
        ($lines -join '|') | Should -Be "SCCACHE_BUCKET=sccache|SCCACHE_ENDPOINT=$script:endpoint|SCCACHE_REGION=garage|SCCACHE_S3_USE_SSL=false|AWS_ACCESS_KEY_ID=GKtest|AWS_SECRET_ACCESS_KEY=s3cret"
        Remove-LaneSccacheS3Secret $file
        (Test-Path -LiteralPath (Split-Path -Parent $file)) | Should -Be $false
    }

    It 'keeps the directory private and the file readable for the container uid' {
        if ($IsWindows) { return }
        $file = New-LaneSccacheS3Secret -Directory $script:work -Lookup $script:lookup
        (stat -c '%a' (Split-Path -Parent $file)) | Should -Be '700'
        (stat -c '%a' $file) | Should -Be '644'
        Remove-LaneSccacheS3Secret $file
    }

    It 'reads a Linux host file under the names set-sccache-s3-level.sh writes' {
        Assert-HostFileSecret 'sccache-s3.env' @('SCCACHE_S3_USE_SSL=false') { '' } 'AWS_ACCESS_KEY_ID=GKfile\|AWS_SECRET_ACCESS_KEY=fromfile$'
    }

    It 'prefers the host environment over the host file' {
        $envKey = { param($name) if ($name -like '*ACCESS_KEY_ID') { 'GKenv' } else { '' } }
        Assert-HostFileSecret 'sccache-s3-env-wins.env' @() $envKey 'AWS_ACCESS_KEY_ID=GKenv\|AWS_SECRET_ACCESS_KEY=fromfile$'
    }

    It 'writes nothing without a key, for an unreachable bucket, or when switched off' {
        New-LaneSccacheS3Secret -Directory $script:work -Lookup $script:noKey 3>$null | Should -BeNullOrEmpty
        New-LaneSccacheS3Secret -Directory $script:work -Lookup $script:dead 3>$null | Should -BeNullOrEmpty
        $env:KATAGLYPHIS_SCCACHE_S3 = 'off'
        try { New-LaneSccacheS3Secret -Directory $script:work -Lookup $script:lookup | Should -BeNullOrEmpty }
        finally { Remove-Item Env:\KATAGLYPHIS_SCCACHE_S3 }
        @(Get-ChildItem -LiteralPath $script:work -Directory).Count | Should -Be 0
    }

    It 'treats an absent path as a no-op on removal' {
        { Remove-LaneSccacheS3Secret $null } | Should -Not -Throw
    }

    AfterAll {
        $script:listener.Stop()
        Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
