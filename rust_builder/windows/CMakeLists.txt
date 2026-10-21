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

apply_cargokit(
  ${PROJECT_NAME}
  "${MANIFEST_REL}"
  oxidant
  "")

# Absolute paths of the libraries bundled with the plugin.
set(oxidant_bundled_libraries
    "${${PROJECT_NAME}_cargokit_lib}"
    PARENT_SCOPE)
