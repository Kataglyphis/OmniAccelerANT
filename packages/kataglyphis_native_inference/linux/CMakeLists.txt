cmake_minimum_required(VERSION 4.2.1)

# Project-level configuration.
set(PROJECT_NAME "kataglyphis_native_inference")
project(${PROJECT_NAME} LANGUAGES CXX)

if(CMAKE_C_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  set(GCC_TOOLCHAIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/gcc-15.2.0")
  if(EXISTS "${GCC_TOOLCHAIN_DIR}")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} --gcc-toolchain=${GCC_TOOLCHAIN_DIR}")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} --gcc-toolchain=${GCC_TOOLCHAIN_DIR}")
  endif()
endif()

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "kataglyphis_native_inference_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "kataglyphis_native_inference_plugin.cc"
  "my_texture.cc"
)

list(APPEND PLUGIN_MODULES
  "my_texture.ixx"
)

# Add your native library - source folder is ../native
set(RUST_FEATURES "TRUE")
# Resolve first, then walk up: a ".." inside the REALPATH argument is collapsed
# lexically and lands in .plugin_symlinks — AGENTS.md section 3.
get_filename_component(_KCI_PLUGIN_PLATFORM_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
get_filename_component(_KCI_PLUGIN_ROOT "${_KCI_PLUGIN_PLATFORM_DIR}" DIRECTORY)
get_filename_component(_KCI_PACKAGES "${_KCI_PLUGIN_ROOT}" DIRECTORY)
get_filename_component(_KCI_REPO_ROOT "${_KCI_PACKAGES}" DIRECTORY)
set(KCI_DIR "${_KCI_REPO_ROOT}/third_party/Cpp-Inference")
add_subdirectory(${KCI_DIR} ${CMAKE_CURRENT_BINARY_DIR}/native_build)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

target_sources(
  ${PLUGIN_NAME}
  PUBLIC FILE_SET
         CXX_MODULES
         BASE_DIRS
         ${CMAKE_CURRENT_SOURCE_DIR}
         FILES
         ${PLUGIN_MODULES}
)

target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_20)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

find_package(PkgConfig REQUIRED)
pkg_check_modules(GST REQUIRED IMPORTED_TARGET gstreamer-1.0)
pkg_check_modules(GST_APP REQUIRED IMPORTED_TARGET gstreamer-app-1.0)
pkg_check_modules(GST_VIDEO REQUIRED IMPORTED_TARGET gstreamer-video-1.0)


# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${KCI_DIR}/Src")

target_include_directories(${PLUGIN_NAME} PRIVATE
  ${GST_INCLUDE_DIRS}
  ${GST_APP_INCLUDE_DIRS}
  ${GST_VIDEO_INCLUDE_DIRS}
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE KataglyphisCppInference)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GST
  PkgConfig::GST_APP
  PkgConfig::GST_VIDEO)
# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(kataglyphis_native_inference_bundled_libraries
  "$<TARGET_FILE:KataglyphisCppInference>"
  PARENT_SCOPE
)

# === Tests ===
# These unit tests can be run from a terminal after building the example.

# Only enable test builds when building the example (which sets this variable)
# so that plugin clients aren't building the tests.
if (${include_${PROJECT_NAME}_tests})
if(${CMAKE_VERSION} VERSION_LESS "3.11.0")
message("Unit tests require CMake 3.11.0 or later")
else()
set(TEST_RUNNER "${PROJECT_NAME}_test")
enable_testing()

# Add the Google Test dependency.
include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/56efe3983185e3f37e43415d1afa97e3860f187f.zip
)
# release-1.11.0.zip
# Prevent overriding the parent project's compiler/linker settings
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
# Disable install commands for gtest so it doesn't end up in the bundle.
set(INSTALL_GTEST OFF CACHE BOOL "Disable installation of googletest" FORCE)

FetchContent_MakeAvailable(googletest)

# The plugin's exported API is not very useful for unit testing, so build the
# sources directly into the test binary rather than using the shared library.
add_executable(${TEST_RUNNER}
  test/kataglyphis_native_inference_plugin_test.cc
  ${PLUGIN_SOURCES}
)
target_sources(
  ${TEST_RUNNER}
  PUBLIC FILE_SET
         CXX_MODULES
         BASE_DIRS
         ${CMAKE_CURRENT_SOURCE_DIR}
         FILES
         ${PLUGIN_MODULES}
)
target_compile_features(${TEST_RUNNER} PRIVATE cxx_std_20)
apply_standard_settings(${TEST_RUNNER})
target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${TEST_RUNNER} PRIVATE flutter)
target_link_libraries(${TEST_RUNNER} PRIVATE PkgConfig::GTK)
target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)

# Enable automatic test discovery.
include(GoogleTest)
gtest_discover_tests(${TEST_RUNNER})

endif()  # CMake version check
endif()  # include_${PROJECT_NAME}_tests
