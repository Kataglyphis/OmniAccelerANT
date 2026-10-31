#requires -Version 7.0

Describe 'Windows detector model staging' {
    $stage = Join-Path $PSScriptRoot '..\Stage-DetectorModel.ps1'
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $shared = Join-Path $root 'third_party\ANTfrastructure\linux\scripts\lib\fetch-data-lock.py'
    $names = @('deim_dfine_n_coco.onnx', 'deim_dfine_n_coco.LICENSE', 'deim_dfine_n_coco.NOTICE')
    BeforeEach {
        $script:oldCache = $env:KATAGLYPHIS_MODEL_CACHE
        $script:workspace = Join-Path $TestDrive 'workspace'
        $script:runner = Join-Path $TestDrive 'runner'
        $script:source = Join-Path $TestDrive 'source'
        $fetch = Join-Path $script:workspace 'third_party\ANTfrastructure\linux\scripts\lib'
        $lockDir = Join-Path $script:workspace 'third_party\OxidANT\resources\models'
        foreach ($dir in $script:runner, $script:source, $fetch, $lockDir) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        Copy-Item -LiteralPath $shared -Destination (Join-Path $fetch 'fetch-data-lock.py')
        $env:KATAGLYPHIS_MODEL_CACHE = Join-Path $TestDrive 'cache'
        $script:lock = Join-Path $lockDir 'models.lock'
        $rows = foreach ($name in $names) {
            $path = Join-Path $script:source $name
            Set-Content -LiteralPath $path -Value "locked $name"
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
            "$hash  $name  $([Uri]::new($path).AbsoluteUri)"
        }
        Set-Content -LiteralPath $script:lock -Value $rows
    }
    AfterEach { $env:KATAGLYPHIS_MODEL_CACHE = $script:oldCache }

    It 'stages and verifies all three locked files' {
        { & $stage -WorkspaceDir $script:workspace -RunnerDir $script:runner } | Should Not Throw
        foreach ($name in $names) {
            (Get-FileHash -LiteralPath (Join-Path $script:runner "resources\models\$name")).Hash |
                Should Be (Get-FileHash -LiteralPath (Join-Path $script:source $name)).Hash
        }
        { & $stage -WorkspaceDir $script:workspace -RunnerDir $script:runner -VerifyOnly } | Should Not Throw
    }
    It 'rejects a corrupted model and a missing notice without fetching in verify-only mode' {
        & $stage -WorkspaceDir $script:workspace -RunnerDir $script:runner
        Set-Content -LiteralPath (Join-Path $script:runner 'resources\models\deim_dfine_n_coco.onnx') -Value 'corrupt'
        $archive = Join-Path $TestDrive 'matching-mutated-model.zip'
        Compress-Archive -LiteralPath (Join-Path $script:runner 'resources\models\deim_dfine_n_coco.onnx') -DestinationPath $archive
        $extracted = Join-Path $TestDrive 'matching-mutated-model'
        Expand-Archive -LiteralPath $archive -DestinationPath $extracted
        (Get-FileHash -LiteralPath (Join-Path $extracted 'deim_dfine_n_coco.onnx')).Hash |
            Should Be (Get-FileHash -LiteralPath (Join-Path $script:runner 'resources\models\deim_dfine_n_coco.onnx')).Hash
        $message = try { & $stage -WorkspaceDir $script:workspace -RunnerDir $script:runner -VerifyOnly; '' } catch { $_.Exception.Message }
        $message | Should Match 'verification failed'
        & $stage -WorkspaceDir $script:workspace -RunnerDir $script:runner
        Remove-Item -LiteralPath (Join-Path $script:runner 'resources\models\deim_dfine_n_coco.NOTICE')
        $message = try { & $stage -WorkspaceDir $script:workspace -RunnerDir $script:runner -VerifyOnly; '' } catch { $_.Exception.Message }
        $message | Should Match 'verification failed'
    }
    It 'refuses a lock that omits a required notice' {
        $rows = @(Get-Content -LiteralPath $script:lock | Where-Object { $_ -notmatch '\.NOTICE\s' })
        Set-Content -LiteralPath $script:lock -Value $rows
        $message = try { & $stage -WorkspaceDir $script:workspace -RunnerDir $script:runner | Out-Null; '' } catch { $_.Exception.Message }
        $message | Should Match 'verification failed'
    }
    It 'rejects a model directory junction before writing to its target' {
        $case = Join-Path $TestDrive "junction-case-$([guid]::NewGuid().ToString('N'))"
        $runner = Join-Path $case 'runner'
        $resources = Join-Path $runner 'resources'
        $outside = Join-Path $case 'outside-models'
        $models = Join-Path $resources 'models'
        New-Item -ItemType Directory -Force -Path $resources, $outside | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'sentinel') -Value 'untouched'
        New-Item -ItemType Junction -Path $models -Target $outside -ErrorAction Stop | Out-Null
        try {
            $message = try { & $stage -WorkspaceDir $script:workspace -RunnerDir $runner; '' } catch { $_.Exception.Message }
            $message | Should Match 'Unsafe model staging directory'
            (Get-Content -Raw -LiteralPath (Join-Path $outside 'sentinel')).Trim() | Should Be 'untouched'
            @(Get-ChildItem -LiteralPath $outside).Count | Should Be 1
        } finally {
            Remove-Item -LiteralPath $models -Force
        }
    }
    It 'requires verified model data in both Windows builds and before packaging' {
        $x64 = Get-Content (Join-Path $root 'scripts\windows\Build-Windows.ps1') -Raw
        $arm = Get-Content (Join-Path $root 'scripts\windows\Build-WindowsArm64Natives.ps1') -Raw
        $package = Get-Content (Join-Path $root 'scripts\windows\Package-OmniAccelerANT.ps1') -Raw
        $x64 | Should Match 'Stage-DetectorModel\.ps1'
        $arm | Should Match 'Stage-DetectorModel\.ps1'
        $package | Should Match 'Stage-DetectorModel\.ps1[^\r\n]+-VerifyOnly'
        $msi = $package.IndexOf('Assert-PackageBinary -Path "$base.msi"')
        $msix = $package.IndexOf('Assert-PackageBinary -Path "$base.msix"')
        $publish = $package.IndexOf('Move-Item -LiteralPath $outRoot -Destination $gpuDestination')
        $modelCheck = "Stage-DetectorModel.ps1') -WorkspaceDir `$repoRoot -RunnerDir `$AppDir -VerifyOnly"
        $afterMsi = $package.IndexOf($modelCheck, $msi)
        $afterMsix = $package.IndexOf($modelCheck, $msix)
        ($msi -ge 0 -and $afterMsi -gt $msi -and $afterMsi -lt $msix -and
            $afterMsix -gt $msix -and $afterMsix -lt $publish) | Should Be $true
        foreach ($name in $names) { $package | Should Match ([regex]::Escape("resources/models/$name")) }
    }
}
