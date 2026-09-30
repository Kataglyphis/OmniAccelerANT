cmake_minimum_required(VERSION 3.31.6)

# Project-level configuration.
set(PROJECT_NAME "kataglyphis_native_inference")
project(${PROJECT_NAME} LANGUAGES CXX)

# Opt in to modern behavior to avoid warnings from recent CMake.
cmake_policy(VERSION 3.14...3.25)

# Builds that use this plugin are generated against this name; never change it.
set(PLUGIN_NAME "kataglyphis_native_inference_plugin")

# Any new source files that you add to the plugin should be added here.
list(
  APPEND
  PLUGIN_SOURCES
  "kataglyphis_native_inference_plugin.cpp"
  "kataglyphis_native_inference_plugin.h"
  "kataglyphis_texture.cpp"
  "kataglyphis_texture.h")

set(RUST_FEATURES "TRUE")
# Resolve, then walk up: a ".." inside REALPATH collapses lexically into .plugin_symlinks (AGENTS.md section 3).
get_filename_component(_KCI_PLUGIN_PLATFORM_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
get_filename_component(_KCI_PLUGIN_ROOT "${_KCI_PLUGIN_PLATFORM_DIR}" DIRECTORY)
get_filename_component(_KCI_PACKAGES "${_KCI_PLUGIN_ROOT}" DIRECTORY)
get_filename_component(_KCI_REPO_ROOT "${_KCI_PACKAGES}" DIRECTORY)
set(KCI_DIR "${_KCI_REPO_ROOT}/third_party/AccelerANTgine")
# Windows arm64 links a cross-built AccelerANTgine with its own C API headers (AGENTS.md § 5, the arm64 lane).
if(DEFINED ENV{KATAGLYPHIS_ACCELERANTGINE_PREBUILT}
   AND NOT
       "$ENV{KATAGLYPHIS_ACCELERANTGINE_PREBUILT}"
       STREQUAL
       "")
  # A CMake path: install() re-parses the DLL path, where a backslash sequence like "\a" is an escape.
  file(TO_CMAKE_PATH "$ENV{KATAGLYPHIS_ACCELERANTGINE_PREBUILT}" _KCI_PREBUILT)
  foreach(_kci_file "bin/AccelerANTgine.dll" "lib/AccelerANTgine.lib" "include/kataglyphis_c_api.h")
    if(NOT EXISTS "${_KCI_PREBUILT}/${_kci_file}")
      message(FATAL_ERROR "KATAGLYPHIS_ACCELERANTGINE_PREBUILT lacks ${_kci_file}: ${_KCI_PREBUILT}")
    endif()
  endforeach()
  add_library(AccelerANTgine SHARED IMPORTED)
  set_target_properties(
    AccelerANTgine
    PROPERTIES IMPORTED_LOCATION "${_KCI_PREBUILT}/bin/AccelerANTgine.dll"
               IMPORTED_IMPLIB "${_KCI_PREBUILT}/lib/AccelerANTgine.lib"
               INTERFACE_INCLUDE_DIRECTORIES "${_KCI_PREBUILT}/include")
  set(_KCI_BUNDLED "${_KCI_PREBUILT}/bin/AccelerANTgine.dll")
else()
  add_subdirectory(${KCI_DIR} ${CMAKE_CURRENT_BINARY_DIR}/native_build)
  set(_KCI_BUNDLED "")
endif()

# Named PLUGIN_NAME, which must not change.
add_library(${PLUGIN_NAME} SHARED "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin_c_api.h"
                                  "kataglyphis_native_inference_plugin_c_api.cpp" ${PLUGIN_SOURCES})

# Build settings from the application-level CMakeLists.txt.
apply_standard_settings(${PLUGIN_NAME})

# Hidden by default against cross-plugin symbol clashes; export with FLUTTER_PLUGIN_EXPORT.
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE "${KCI_DIR}/Src")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
target_link_libraries(${PLUGIN_NAME} PRIVATE AccelerANTgine)
# Absolute paths of the libraries bundled with the plugin.
set(kataglyphis_native_inference_bundled_libraries
    "${_KCI_BUNDLED}"
    PARENT_SCOPE)

# Tests

# Only the example sets this, so plugin clients never build the tests.
if(${include_${PROJECT_NAME}_tests})
  set(TEST_RUNNER "${PROJECT_NAME}_test")
  enable_testing()

  # Add the Google Test dependency.
  include(FetchContent)
  FetchContent_Declare(googletest
                       URL https://github.com/google/googletest/archive/56efe3983185e3f37e43415d1afa97e3860f187f.zip)
  # Prevent overriding the parent project's compiler/linker settings
  set(gtest_force_shared_crt
      ON
      CACHE BOOL "" FORCE)
  # Disable install commands for gtest so it doesn't end up in the bundle.
  set(INSTALL_GTEST
      OFF
      CACHE BOOL "Disable installation of googletest" FORCE)
  FetchContent_MakeAvailable(googletest)

  # The C API is too narrow to unit-test, so compile the sources into the test binary.
  add_executable(${TEST_RUNNER} test/kataglyphis_native_inference_plugin_test.cpp ${PLUGIN_SOURCES})
  apply_standard_settings(${TEST_RUNNER})
  target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
  target_link_libraries(${TEST_RUNNER} PRIVATE flutter_wrapper_plugin)
  target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)
  # flutter_wrapper_plugin has link dependencies on the Flutter DLL.
  add_custom_command(
    TARGET ${TEST_RUNNER}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${FLUTTER_LIBRARY}" $<TARGET_FILE_DIR:${TEST_RUNNER}>)

  # Enable automatic test discovery.
  include(GoogleTest)
  gtest_discover_tests(${TEST_RUNNER})
endif()
