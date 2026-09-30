cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "oxidant")
project(${PROJECT_NAME} LANGUAGES CXX)

# Not REALPATH, unlike linux/: Windows normalizes ".." lexically from the junction (AGENTS.md § 4).
get_filename_component(MANIFEST_ABS "${CMAKE_SOURCE_DIR}/../third_party/OxidANT" ABSOLUTE)
file(
  RELATIVE_PATH
  MANIFEST_REL
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${MANIFEST_ABS}")

include("../cargokit/cmake/cargokit.cmake")

# Features reach cargo via the local CARGOKIT_EXTRA_CARGO_FLAGS patch (AGENTS.md § 1); keep identical to linux/.
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

# Absolute paths of the libraries bundled with the plugin.
set(oxidant_bundled_libraries
    "${${PROJECT_NAME}_cargokit_lib}"
    PARENT_SCOPE)
