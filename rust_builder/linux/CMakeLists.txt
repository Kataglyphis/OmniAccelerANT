# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "kataglyphis_rustprojecttemplate")
project(${PROJECT_NAME} LANGUAGES CXX)

# Resolve Rust manifest relative to CMAKE_CURRENT_SOURCE_DIR so the path works
# regardless of whether this CMakeLists.txt is processed from its original
# location (rust_builder/linux/) or from a Flutter ephemeral symlink copy.
get_filename_component(MANIFEST_ABS "${CMAKE_SOURCE_DIR}/../ExternalLib/Kataglyphis-RustProjectTemplate" ABSOLUTE)
file(RELATIVE_PATH MANIFEST_REL "${CMAKE_CURRENT_SOURCE_DIR}" "${MANIFEST_ABS}")

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} "${MANIFEST_REL}" kataglyphis_rustprojecttemplate "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(kataglyphis_rustprojecttemplate_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
