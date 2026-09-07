# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "oxidant")
project(${PROJECT_NAME} LANGUAGES CXX)

# Resolve Rust manifest relative to CMAKE_CURRENT_SOURCE_DIR so the path works
# regardless of whether this CMakeLists.txt is processed from its original
# location (rust_builder/windows/) or from a Flutter ephemeral symlink copy
# (flutter/ephemeral/.plugin_symlinks/oxidant/windows/).
get_filename_component(MANIFEST_ABS "${CMAKE_SOURCE_DIR}/../third_party/OxidANT" ABSOLUTE)
file(
  RELATIVE_PATH
  MANIFEST_REL
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${MANIFEST_ABS}")

include("../cargokit/cmake/cargokit.cmake")

# Windows-only cargo feature set (webcam capture + runtime-loaded ONNX). Read
# from the environment at configure time so the container build script controls
# it; unset (e.g. plain `flutter run` on a host without GStreamer dev files)
# builds the crate feature-less and the webcam API reports itself disabled.
if(DEFINED ENV{KATAGLYPHIS_RUST_FEATURES}
   AND NOT
       "$ENV{KATAGLYPHIS_RUST_FEATURES}"
       STREQUAL
       "")
  set(CARGOKIT_EXTRA_CARGO_FLAGS "--features $ENV{KATAGLYPHIS_RUST_FEATURES}")
  message(STATUS "Rust crate features: $ENV{KATAGLYPHIS_RUST_FEATURES}")
endif()

apply_cargokit(
  ${PROJECT_NAME}
  "${MANIFEST_REL}"
  oxidant
  "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(oxidant_bundled_libraries
    "${${PROJECT_NAME}_cargokit_lib}"
    PARENT_SCOPE)
