Set-StrictMode -Version Latest

$script:KataglyphisWindowsBuildConfig = @{
    BuildRootDir          = "build"
    RustDllName           = "kataglyphis_rustprojecttemplate.dll"
    PluginRelativeDir     = "build/windows/x64/plugins"
    RunnerExeName         = "kataglyphis_inference_engine.exe"
    RunnerExeRelativePath = "build/windows/x64/runner/kataglyphis_inference_engine.exe"
    RunLogRelativePath    = "run_output.txt"
}

function Get-KataglyphisWindowsBuildConfig {
    return $script:KataglyphisWindowsBuildConfig
}
