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
# byte what it was. Note the image has TWO copies in its cache (/opt/opencv5
# and onnxruntime-cpu); the explicit path is what keeps this deterministic.
set(oxidant_extra_bundled_libraries "")
if(CARGOKIT_EXTRA_CARGO_FLAGS MATCHES "onnxruntime")
  find_library(
    ONNXRUNTIME_LIB
    NAMES onnxruntime
    HINTS "/usr/local/lib/onnxruntime-cpu/lib"
    PATH_SUFFIXES lib)
  if(ONNXRUNTIME_LIB)
    # Staged as a real file under the UNVERSIONED name, which is the only
    # combination that works. ort's load-dynamic dlopens the bare soname
    # "libonnxruntime.so" and the runner's RPATH is $ORIGIN/lib, so the bundle
    # needs that exact name; but install(FILES) on the distro symlink copies
    # the LINK, and its target is not in the bundle — measured: a 0-byte
    # `libonnxruntime.so -> libonnxruntime.so.1.29.0` that dangles on every
    # target. Bundling the REALPATH instead gets 31 MB under a versioned name
    # dlopen never asks for. configure_file COPYONLY resolves both at once.
    get_filename_component(ONNXRUNTIME_REAL "${ONNXRUNTIME_LIB}" REALPATH)
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
  else()
    message(
      WARNING
        "KATAGLYPHIS_RUST_FEATURES asks for onnxruntime but libonnxruntime.so was not found. The bundle will start and then fail to load the model at runtime. Set ORT_DYLIB_PATH on the target, or install ONNX Runtime."
    )
  endif()
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(oxidant_bundled_libraries
    "${${PROJECT_NAME}_cargokit_lib}" ${oxidant_extra_bundled_libraries}
    PARENT_SCOPE)
