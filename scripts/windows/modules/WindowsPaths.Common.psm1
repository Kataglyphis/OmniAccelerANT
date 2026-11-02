#requires -Version 7.0

# Local on purpose: this repo's per-preset build/windows/x64/{runner,plugins} layout; anything generic belongs upstream.

Set-StrictMode -Version Latest

function Get-KataglyphisBuildConfigValue {
    # An absent key and a blank value are the same to every caller: empty.
    param([Parameter(Mandatory)][hashtable] $WindowsBuildConfig, [Parameter(Mandatory)][string] $Key)
    if ($WindowsBuildConfig.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($WindowsBuildConfig[$Key])) { return $WindowsBuildConfig[$Key] }
    return ''
}

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

    $candidateInputs.Add((Get-KataglyphisBuildConfigValue -WindowsBuildConfig $WindowsBuildConfig -Key 'BuildRootDir'))

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

function Join-KataglyphisConfigDir {
    param([Parameter(Mandatory)][string] $Base, [AllowEmptyString()][string] $Configuration)
    if ([string]::IsNullOrWhiteSpace($Configuration)) { return $Base }
    return [System.IO.Path]::GetFullPath((Join-Path $Base $Configuration))
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

    foreach ($required in 'RunnerExeName', 'RustDllName') {
        if (-not (Get-KataglyphisBuildConfigValue -WindowsBuildConfig $WindowsBuildConfig -Key $required)) {
            throw "$required is missing in Windows build config."
        }
    }

    # An explicit -Configuration wins; the config file's CMakeConfiguration is only the fallback.
    $cmakeConfig = if (-not [string]::IsNullOrWhiteSpace($Configuration)) {
        $Configuration
    } else {
        Get-KataglyphisBuildConfigValue -WindowsBuildConfig $WindowsBuildConfig -Key 'CMakeConfiguration'
    }

    $buildRootNormalized = [System.IO.Path]::GetFullPath($BuildRootFull)
    $cmakeBuildDir = [System.IO.Path]::GetFullPath((Join-Path $buildRootNormalized 'windows/x64'))
    
    $runnerDirBase = [System.IO.Path]::GetFullPath((Join-Path $cmakeBuildDir 'runner'))
    $runnerDir = Join-KataglyphisConfigDir -Base $runnerDirBase -Configuration $cmakeConfig

    $pluginDirBase = [System.IO.Path]::GetFullPath((Join-Path $cmakeBuildDir 'plugins'))
    $pluginDir = Join-KataglyphisConfigDir -Base $pluginDirBase -Configuration $cmakeConfig

    $rustPluginSubDir = Get-KataglyphisBuildConfigValue -WindowsBuildConfig $WindowsBuildConfig -Key 'RustPluginSubDir'
    if (-not $rustPluginSubDir) { $rustPluginSubDir = [System.IO.Path]::GetFileNameWithoutExtension($WindowsBuildConfig.RustDllName) }
    
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

Export-ModuleMember -Function Get-KataglyphisBuildConfigValue, Resolve-KataglyphisWindowsBuildRootCandidates, Resolve-KataglyphisWindowsLayout
