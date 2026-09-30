cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "oxidant")
project(${PROJECT_NAME} LANGUAGES CXX)

# REALPATH: the kernel resolves the ephemeral symlink before "..", so a count from it overshoots (AGENTS.md § 4).
get_filename_component(MANIFEST_ABS "${CMAKE_SOURCE_DIR}/../third_party/OxidANT" ABSOLUTE)
get_filename_component(PLUGIN_LINUX_REAL "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
file(
  RELATIVE_PATH
  MANIFEST_REL
  "${PLUGIN_LINUX_REAL}"
  "${MANIFEST_ABS}")

# Features reach cargo via the local CARGOKIT_EXTRA_CARGO_FLAGS patch (AGENTS.md § 1); keep identical to windows/.
if(DEFINED ENV{KATAGLYPHIS_RUST_FEATURES}
   AND NOT
       "$ENV{KATAGLYPHIS_RUST_FEATURES}"
       STREQUAL
       "")
  set(CARGOKIT_EXTRA_CARGO_FLAGS "--features $ENV{KATAGLYPHIS_RUST_FEATURES}")
  message(STATUS "Rust crate features: $ENV{KATAGLYPHIS_RUST_FEATURES}")
endif()

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(
  ${PROJECT_NAME}
  "${MANIFEST_REL}"
  oxidant
  "")

# ort dlopens ORT, so no ELF dependency bundles it. See docs/source/camera-streaming.md § Relocatable Linux bundles
set(oxidant_extra_bundled_libraries "")
if(CARGOKIT_EXTRA_CARGO_FLAGS MATCHES "onnxruntime")
  if(DEFINED ENV{ORT_LIB_LOCATION}
     AND NOT
         "$ENV{ORT_LIB_LOCATION}"
         STREQUAL
         "")
    set(ORT_CHAIN_LIB_DIR "$ENV{ORT_LIB_LOCATION}")
  else()
    set(ORT_CHAIN_LIB_DIR "/usr/local/lib/onnxruntime-cpu/lib")
  endif()
  unset(ONNXRUNTIME_LIB CACHE)
  find_library(
    ONNXRUNTIME_LIB
    NAMES onnxruntime
    PATHS "${ORT_CHAIN_LIB_DIR}"
    NO_DEFAULT_PATH)
  if(NOT ONNXRUNTIME_LIB)
    message(
      FATAL_ERROR
        "KATAGLYPHIS_RUST_FEATURES asks for onnxruntime but the chain-built libonnxruntime.so is not in ${ORT_CHAIN_LIB_DIR}. Build inside the family image; no other ONNX Runtime may be bundled."
    )
  endif()
  # The real file: install(FILES) on the distro symlink would copy a link that dangles in the bundle.
  get_filename_component(ONNXRUNTIME_REAL "${ONNXRUNTIME_LIB}" REALPATH)
  # ORT embeds its source path via __FILE__, so a foreign ORT that ORT_LIB_LOCATION names is refused.
  file(
    STRINGS "${ONNXRUNTIME_REAL}" _ort_chain_hit
    LIMIT_COUNT 1
    REGEX "/opt/onnxruntime/onnxruntime/core/")
  if(NOT _ort_chain_hit)
    message(
      FATAL_ERROR
        "${ONNXRUNTIME_REAL} is not the family's chain-built ONNX Runtime (no /opt/onnxruntime/onnxruntime/core/ source path in it). ORT_LIB_LOCATION may only name the image's chain build."
    )
  endif()
  # Both sonames as real copies: the plugin DT_NEEDs .so.1 while ort dlopens the bare .so.
  foreach(_ort_name libonnxruntime.so libonnxruntime.so.1)
    set(_ort_staged "${CMAKE_CURRENT_BINARY_DIR}/${_ort_name}")
    configure_file("${ONNXRUNTIME_REAL}" "${_ort_staged}" COPYONLY)
    list(APPEND oxidant_extra_bundled_libraries "${_ort_staged}")
  endforeach()
  message(STATUS "Bundling ONNX Runtime (both sonames): ${ONNXRUNTIME_REAL}")
endif()

# Absolute paths of the libraries bundled with the plugin.
set(oxidant_bundled_libraries
    "${${PROJECT_NAME}_cargokit_lib}" ${oxidant_extra_bundled_libraries}
    PARENT_SCOPE)
