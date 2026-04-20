Set-StrictMode -Version Latest

function Resolve-KataglyphisWindowsBuildRootCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepoRoot,

        [Parameter()]
        [string] $BuildRootDir = "",

        [Parameter(Mandatory = $true)]
        [hashtable] $WindowsBuildConfig,

        [Parameter()]
        [switch] $IncludeDefaultFallbacks
    )

    $candidateInputs = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($BuildRootDir)) {
        $candidateInputs.Add($BuildRootDir)
    }

    if ($WindowsBuildConfig.ContainsKey('BuildRootDir') -and -not [string]::IsNullOrWhiteSpace($WindowsBuildConfig.BuildRootDir)) {
        $candidateInputs.Add($WindowsBuildConfig.BuildRootDir)
    }

    if ($IncludeDefaultFallbacks) {
        $candidateInputs.Add('out')
        $candidateInputs.Add('build')
    }

    $resolved = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($candidate in $candidateInputs) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $fullPath = if ([System.IO.Path]::IsPathRooted($candidate)) {
            [System.IO.Path]::GetFullPath($candidate)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $candidate))
        }

        if ($seen.Add($fullPath)) {
            $resolved.Add($fullPath)
        }
    }

    return @($resolved)
}

function Resolve-KataglyphisWindowsLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BuildRootFull,

        [Parameter(Mandatory = $true)]
        [hashtable] $WindowsBuildConfig,

        [Parameter()]
        [string] $Configuration = ""
    )

    if (-not $WindowsBuildConfig.ContainsKey('RunnerExeName') -or [string]::IsNullOrWhiteSpace($WindowsBuildConfig.RunnerExeName)) {
        throw "RunnerExeName is missing in Windows build config."
    }

    if (-not $WindowsBuildConfig.ContainsKey('RustDllName') -or [string]::IsNullOrWhiteSpace($WindowsBuildConfig.RustDllName)) {
        throw "RustDllName is missing in Windows build config."
    }

    $buildRootNormalized = [System.IO.Path]::GetFullPath($BuildRootFull)
    $cmakeBuildDir = [System.IO.Path]::GetFullPath((Join-Path $buildRootNormalized 'windows/x64'))
    
    $runnerDirBase = [System.IO.Path]::GetFullPath((Join-Path $cmakeBuildDir 'runner'))
    $runnerDir = if ([string]::IsNullOrWhiteSpace($Configuration)) {
        $runnerDirBase
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $runnerDirBase $Configuration))
    }

    $pluginDirBase = [System.IO.Path]::GetFullPath((Join-Path $cmakeBuildDir 'plugins'))
    $pluginDir = if ([string]::IsNullOrWhiteSpace($Configuration)) {
        $pluginDirBase
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $pluginDirBase $Configuration))
    }

    $rustPluginSubDir = if ($WindowsBuildConfig.ContainsKey('RustPluginSubDir') -and -not [string]::IsNullOrWhiteSpace($WindowsBuildConfig.RustPluginSubDir)) {
        $WindowsBuildConfig.RustPluginSubDir
    } else {
        [System.IO.Path]::GetFileNameWithoutExtension($WindowsBuildConfig.RustDllName)
    }
    
    $rustPluginDir = [System.IO.Path]::GetFullPath((Join-Path $pluginDir $rustPluginSubDir))
    
    # Fallback to base plugin dir if configuration-specific one doesn't exist
    if (-not (Test-Path -LiteralPath $rustPluginDir -PathType Container)) {
        $rustPluginDirBase = [System.IO.Path]::GetFullPath((Join-Path $pluginDirBase $rustPluginSubDir))
        if (Test-Path -LiteralPath $rustPluginDirBase -PathType Container) {
            $rustPluginDir = $rustPluginDirBase
        }
    }

    $runnerExePath = [System.IO.Path]::GetFullPath((Join-Path $runnerDir $WindowsBuildConfig.RunnerExeName))
    
    # If the exe is not in the configuration dir, fallback to base
    if (-not (Test-Path -LiteralPath $runnerExePath -PathType Leaf)) {
        $runnerExePathBase = [System.IO.Path]::GetFullPath((Join-Path $runnerDirBase $WindowsBuildConfig.RunnerExeName))
        if (Test-Path -LiteralPath $runnerExePathBase -PathType Leaf) {
            $runnerExePath = $runnerExePathBase
            $runnerDir = $runnerDirBase
        }
    }

    $rustPluginDllPath = [System.IO.Path]::GetFullPath((Join-Path $rustPluginDir $WindowsBuildConfig.RustDllName))

    return [pscustomobject]@{
        BuildRoot         = $buildRootNormalized
        CMakeBuildDir     = $cmakeBuildDir
        RunnerDir         = $runnerDir
        PluginDir         = $pluginDir
        RustPluginDir     = $rustPluginDir
        RunnerExePath     = $runnerExePath
        RustPluginDllPath = $rustPluginDllPath
    }
}

Export-ModuleMember -Function Resolve-KataglyphisWindowsBuildRootCandidates, Resolve-KataglyphisWindowsLayout
