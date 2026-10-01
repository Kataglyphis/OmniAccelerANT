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

# Builds that use this plugin are generated against this name; never change it.
set(PLUGIN_NAME "kataglyphis_native_inference_plugin")

# Any new source files that you add to the plugin should be added here.
list(
  APPEND
  PLUGIN_SOURCES
  "kataglyphis_native_inference_plugin.cc"
  "runtime_paths.cc"
  "my_texture.cc")

list(APPEND PLUGIN_MODULES "my_texture.ixx")

# Add your native library - source folder is ../native
set(RUST_FEATURES "TRUE")
# Resolve, then walk up: a ".." inside REALPATH collapses lexically into .plugin_symlinks (AGENTS.md section 3).
get_filename_component(_KCI_PLUGIN_PLATFORM_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
get_filename_component(_KCI_PLUGIN_ROOT "${_KCI_PLUGIN_PLATFORM_DIR}" DIRECTORY)
get_filename_component(_KCI_PACKAGES "${_KCI_PLUGIN_ROOT}" DIRECTORY)
get_filename_component(_KCI_REPO_ROOT "${_KCI_PACKAGES}" DIRECTORY)
set(KCI_DIR "${_KCI_REPO_ROOT}/third_party/AccelerANTgine")
# Otherwise AccelerANTgine's Cache.cmake unsets the lane's sccache launcher for every later target.
set(myproject_ENABLE_CACHE OFF)
add_subdirectory(${KCI_DIR} ${CMAKE_CURRENT_BINARY_DIR}/native_build)

# Named PLUGIN_NAME, which must not change.
add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

target_sources(
  ${PLUGIN_NAME}
  PUBLIC FILE_SET
         CXX_MODULES
         BASE_DIRS
         ${CMAKE_CURRENT_SOURCE_DIR}
         FILES
         ${PLUGIN_MODULES})

target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_20)

# Build settings from the application-level CMakeLists.txt.
apply_standard_settings(${PLUGIN_NAME})

find_package(PkgConfig REQUIRED)
pkg_check_modules(
  GST
  REQUIRED
  IMPORTED_TARGET
  gstreamer-1.0)
pkg_check_modules(
  GST_APP
  REQUIRED
  IMPORTED_TARGET
  gstreamer-app-1.0)
pkg_check_modules(
  GST_VIDEO
  REQUIRED
  IMPORTED_TARGET
  gstreamer-video-1.0)

# Hidden by default against cross-plugin symbol clashes; export with FLUTTER_PLUGIN_EXPORT.
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include" "${KCI_DIR}/Src")

target_include_directories(${PLUGIN_NAME} PRIVATE ${GST_INCLUDE_DIRS} ${GST_APP_INCLUDE_DIRS} ${GST_VIDEO_INCLUDE_DIRS})

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE AccelerANTgine)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GST PkgConfig::GST_APP PkgConfig::GST_VIDEO)
# Absolute paths of the libraries bundled with the plugin.
set(kataglyphis_native_inference_bundled_libraries
    "$<TARGET_FILE:AccelerANTgine>"
    PARENT_SCOPE)

# Tests

# Set by the example and by the lanes (KATAGLYPHIS_PLUGIN_TESTS), so a client build never fetches googletest.
if(${include_${PROJECT_NAME}_tests})
  if(${CMAKE_VERSION} VERSION_LESS "3.11.0")
    message("Unit tests require CMake 3.11.0 or later")
  else()
    set(TEST_RUNNER "${PROJECT_NAME}_test")
    enable_testing()

    # Add the Google Test dependency; EXCLUDE_FROM_ALL, so only the test target builds it.
    include(FetchContent)
    FetchContent_Declare(googletest URL https://github.com/google/googletest/archive/refs/tags/v1.18.0.zip
                                        EXCLUDE_FROM_ALL)
    # A normal variable, not a FORCEd cache entry, so AccelerANTgine's own googletest keeps its setting.
    set(INSTALL_GTEST OFF)

    FetchContent_MakeAvailable(googletest)

    # The sources compiled in, as the export is too narrow; EXCLUDE_FROM_ALL, so a broken test never breaks the app build.
    add_executable(${TEST_RUNNER} EXCLUDE_FROM_ALL test/kataglyphis_native_inference_plugin_test.cc ${PLUGIN_SOURCES})
    target_sources(
      ${TEST_RUNNER}
      PUBLIC FILE_SET
             CXX_MODULES
             BASE_DIRS
             ${CMAKE_CURRENT_SOURCE_DIR}
             FILES
             ${PLUGIN_MODULES})
    target_compile_features(${TEST_RUNNER} PRIVATE cxx_std_20)
    apply_standard_settings(${TEST_RUNNER})
    target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" "${KCI_DIR}/Src")
    target_include_directories(${TEST_RUNNER} PRIVATE ${GST_INCLUDE_DIRS} ${GST_APP_INCLUDE_DIRS}
                                                      ${GST_VIDEO_INCLUDE_DIRS})
    target_link_libraries(${TEST_RUNNER} PRIVATE flutter)
    target_link_libraries(${TEST_RUNNER} PRIVATE PkgConfig::GTK)
    # The plugin's own dependencies, since its sources are compiled in.
    target_link_libraries(${TEST_RUNNER} PRIVATE AccelerANTgine)
    target_link_libraries(${TEST_RUNNER} PRIVATE PkgConfig::GST PkgConfig::GST_APP PkgConfig::GST_VIDEO)
    target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)

    # PRE_TEST: listing the tests runs the binary, which belongs in ctest, not in the build.
    include(GoogleTest)
    gtest_discover_tests(${TEST_RUNNER} DISCOVERY_MODE PRE_TEST)

  endif() # CMake version check
endif() # include_${PROJECT_NAME}_tests
