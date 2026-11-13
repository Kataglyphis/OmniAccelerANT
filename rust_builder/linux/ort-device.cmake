include("${CMAKE_CURRENT_LIST_DIR}/oxidant-ort-devices.cmake")

# The same provider must configure both the plugin and its Rust runtime.
function(omni_linux_ort_device output oxidant_dir)
  set(_provider "$ENV{KATAGLYPHIS_ORT_PROVIDER}")
  if(_provider STREQUAL "")
    set(_provider "cpu")
  endif()
  if(NOT
     _provider
     MATCHES
     "^(cpu|cuda|migraphx)$")
    message(FATAL_ERROR "KATAGLYPHIS_ORT_PROVIDER must be cpu, cuda, or migraphx")
  endif()
  string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _arch)
  if(_provider STREQUAL "migraphx")
    if(NOT
       _arch
       MATCHES
       "^(x86_64|amd64)$")
      message(FATAL_ERROR "Linux AMD GPU builds are supported on x64 only")
    endif()
    omni_oxidant_advertises_ort_device(_supports_migraphx "${oxidant_dir}" "migraphx")
    if(NOT _supports_migraphx)
      message(FATAL_ERROR "MIGraphX builds require an OxidANT pin advertising AMD provider selection")
    endif()
  endif()
  set(${output}
      "${_provider}"
      PARENT_SCOPE)
endfunction()

# AccelerANTgine and Rust must resolve the same chain runtime.
function(omni_linux_ort_root provider)
  if(provider STREQUAL "cpu")
    return()
  endif()
  if(NOT DEFINED ENV{ORT_LIB_LOCATION} OR "$ENV{ORT_LIB_LOCATION}" STREQUAL "")
    message(
      FATAL_ERROR
        "GPU builds require ORT_LIB_LOCATION to name their ONNX Runtime's lib directory: the GPU build for cuda, the CPU build for migraphx"
    )
  endif()
  get_filename_component(_lib "$ENV{ORT_LIB_LOCATION}" REALPATH)
  get_filename_component(_root "${_lib}" DIRECTORY)
  if(NOT IS_DIRECTORY "${_lib}"
     OR NOT EXISTS "${_lib}/libonnxruntime.so"
     OR NOT EXISTS "${_root}/include/onnxruntime_cxx_api.h")
    message(FATAL_ERROR "ORT_LIB_LOCATION must name a chain ONNX Runtime lib directory with matching headers")
  endif()
  if(DEFINED ONNXRUNTIME_ROOT
     AND NOT
         ONNXRUNTIME_ROOT
         STREQUAL
         "")
    get_filename_component(_configured "${ONNXRUNTIME_ROOT}" REALPATH)
    if(NOT
       _configured
       STREQUAL
       _root)
      message(FATAL_ERROR "ONNXRUNTIME_ROOT conflicts with the selected GPU ORT_LIB_LOCATION")
    endif()
  endif()
  set(ONNXRUNTIME_ROOT
      "${_root}"
      CACHE PATH "ONNX Runtime prefix selected by OmniAccelerANT" FORCE)
  set(ONNXRUNTIME_ROOT
      "${_root}"
      PARENT_SCOPE)
endfunction()

# The GPU modules a package of this provider carries beside ONNX Runtime; the hub names AMD's plugin module and its place in the image.
function(
  omni_linux_ort_modules
  output
  provider
  ort_lib_dir
  hub_dir)
  set(_modules "")
  if(provider STREQUAL "cuda")
    set(_modules "${ort_lib_dir}/libonnxruntime_providers_shared.so" "${ort_lib_dir}/libonnxruntime_providers_cuda.so")
  elseif(provider STREQUAL "migraphx")
    execute_process(
      COMMAND bash -c [=[set -e; source "$1"; printf '%s/%s' "$(ort_amdgpu_ep_dir)" "${ORT_AMDGPU_EP_MODULE:?}"]=] _
              "${hub_dir}/linux/scripts/06-packaging/ort-runtime-bundle.sh"
      RESULT_VARIABLE _status
      OUTPUT_VARIABLE _modules)
    if(NOT
       _status
       STREQUAL
       "0"
       OR _modules STREQUAL "")
      message(
        FATAL_ERROR
          "MIGraphX builds need the plugin module's name and place from ANTfrastructure's ort-runtime-bundle.sh under ${hub_dir}"
      )
    endif()
  endif()
  set(${output}
      "${_modules}"
      PARENT_SCOPE)
endfunction()
