# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "oxidant")
project(${PROJECT_NAME} LANGUAGES CXX)

# REALPATH, not CMAKE_CURRENT_SOURCE_DIR: cargokit joins this as a plain string
# onto the ephemeral symlink path, and the kernel resolves that symlink before
# applying the "..", so a chain counted from the symlink overshoots. See
# AGENTS.md § 4.
get_filename_component(MANIFEST_ABS "${CMAKE_SOURCE_DIR}/../third_party/OxidANT" ABSOLUTE)
get_filename_component(PLUGIN_LINUX_REAL "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
file(
  RELATIVE_PATH
  MANIFEST_REL
  "${PLUGIN_LINUX_REAL}"
  "${MANIFEST_ABS}")

# Cargo feature set, read from the environment at configure time — the same
# block as rust_builder/windows/CMakeLists.txt, deliberately byte-identical so
# the two cannot drift. Unset (a plain `flutter build linux`) builds the crate
# feature-less and the webcam API reports itself disabled, which is exactly
# today's behaviour. The channel is CARGOKIT_EXTRA_CARGO_FLAGS, a local patch in
# rust_builder/cargokit/cmake/cargokit.cmake with no if(WIN32) in it; the fourth
# argument to apply_cargokit is NOT a features parameter on either platform.
# Linux feature set and the ONNX runtime it needs: docs/source/camera-streaming.md.
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

# ONNX Runtime is dlopen'd at runtime by ort's load-dynamic, so it is NOT an
# ELF dependency of liboxidant.so and nothing bundles it automatically. Inside
# the build image that is invisible — libonnxruntime.so is in the ld.so cache —
# and it breaks only once the bundle is installed on a machine that has no
# system copy, which is every tar/deb/flatpak/AppImage target. Bundled only
# when the features actually ask for it, so a featureless build stays byte-for-
# byte what it was. Only the image's chain-built copy (owner rule 2026-09-23):
# NO_DEFAULT_PATH keeps out /opt/opencv5's second copy in the ld.so cache.
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
  # Staged as a real file under the UNVERSIONED name, which is the only
  # combination that works. ort's load-dynamic dlopens the bare soname
  # "libonnxruntime.so" and the runner's RPATH is $ORIGIN/lib, so the bundle
  # needs that exact name; but install(FILES) on the distro symlink copies
  # the LINK, and its target is not in the bundle — measured: a 0-byte
  # `libonnxruntime.so -> libonnxruntime.so.1.29.0` that dangles on every
  # target. Bundling the REALPATH instead gets 31 MB under a versioned name
  # dlopen never asks for. configure_file COPYONLY resolves both at once.
  get_filename_component(ONNXRUNTIME_REAL "${ONNXRUNTIME_LIB}" REALPATH)
  # ORT embeds its checkout via __FILE__: the chain's is the hub's ORT_SRC_DIR, so a
  # foreign ORT that ORT_LIB_LOCATION names is refused here, not bundled.
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
  # BOTH sonames, as real files. Measured with readelf on the built bundle:
  # the plugin DT_NEEDEDs the VERSIONED libonnxruntime.so.1, so staging only
  # the unversioned name left the linked dependency unsatisfied; and ort's
  # load-dynamic dlopens the BARE name, which needs the unversioned one. A
  # symlink is not an option — install(FILES) copies the link, whose target
  # then dangles. So two copies of a 31 MB file, deliberately.
  foreach(_ort_name libonnxruntime.so libonnxruntime.so.1)
    set(_ort_staged "${CMAKE_CURRENT_BINARY_DIR}/${_ort_name}")
    configure_file("${ONNXRUNTIME_REAL}" "${_ort_staged}" COPYONLY)
    list(APPEND oxidant_extra_bundled_libraries "${_ort_staged}")
  endforeach()
  message(STATUS "Bundling ONNX Runtime (both sonames): ${ONNXRUNTIME_REAL}")
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(oxidant_bundled_libraries
    "${${PROJECT_NAME}_cargokit_lib}" ${oxidant_extra_bundled_libraries}
    PARENT_SCOPE)
