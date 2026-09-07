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
# AGENTS.md § 3.
get_filename_component(MANIFEST_ABS "${CMAKE_SOURCE_DIR}/../third_party/OxidANT" ABSOLUTE)
get_filename_component(PLUGIN_LINUX_REAL "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
file(
  RELATIVE_PATH
  MANIFEST_REL
  "${PLUGIN_LINUX_REAL}"
  "${MANIFEST_ABS}")

include("../cargokit/cmake/cargokit.cmake")
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
