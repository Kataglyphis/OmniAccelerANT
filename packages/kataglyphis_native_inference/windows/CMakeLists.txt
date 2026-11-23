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

# Resolve, then walk up: a ".." inside REALPATH collapses lexically into .plugin_symlinks (AGENTS.md section 3).
get_filename_component(_KCI_PLUGIN_PLATFORM_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
get_filename_component(_KCI_PLUGIN_ROOT "${_KCI_PLUGIN_PLATFORM_DIR}" DIRECTORY)
get_filename_component(_KCI_PACKAGES "${_KCI_PLUGIN_ROOT}" DIRECTORY)
get_filename_component(_KCI_REPO_ROOT "${_KCI_PACKAGES}" DIRECTORY)
set(KCI_TEXTURE_ABI_DIR "${_KCI_REPO_ROOT}/third_party/OxidANT/include")

# Named PLUGIN_NAME, which must not change.
add_library(${PLUGIN_NAME} SHARED "include/kataglyphis_native_inference/kataglyphis_native_inference_plugin_c_api.h"
                                  "kataglyphis_native_inference_plugin_c_api.cpp" ${PLUGIN_SOURCES})

# Build settings from the application-level CMakeLists.txt.
apply_standard_settings(${PLUGIN_NAME})

# Hidden by default against cross-plugin symbol clashes; export with FLUTTER_PLUGIN_EXPORT.
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE "${KCI_TEXTURE_ABI_DIR}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
# The hub's warning set and hardening, not as errors: Flutter's wrapper headers are not this plugin's (owner D1 c).
list(APPEND CMAKE_MODULE_PATH "${_KCI_REPO_ROOT}/third_party/ANTfrastructure/cmake")
include(CompilerWarnings)
include(Hardening)
include(Sanitizers)
add_library(kci_plugin_quality INTERFACE)
myproject_set_project_warnings(
  kci_plugin_quality
  OFF
  ""
  ""
  ""
  "")
# x64 Debug keeps the ASan and UBSan AccelerANTgine's PUBLIC options gave it; such a build checks, a release one hardens.
if(myproject_ENABLE_SANITIZER_ADDRESS
   AND NOT
       CMAKE_SYSTEM_PROCESSOR
       MATCHES
       "^(ARM64|arm64|aarch64)$")
  myproject_enable_sanitizers(
    kci_plugin_quality
    ON
    OFF
    ON
    OFF
    OFF)
else()
  myproject_enable_hardening(kci_plugin_quality OFF FALSE)
endif()
target_link_libraries(${PLUGIN_NAME} PRIVATE kci_plugin_quality)
# The plugin bundles no library of its own since AccelerANTgine left it (owner D1); the Rust core ships beside it.
set(kataglyphis_native_inference_bundled_libraries
    ""
    PARENT_SCOPE)

# Tests

# Set by the example and by the lanes (-Dinclude_kataglyphis_native_inference_tests=ON), so a client build never fetches googletest.
if(${include_${PROJECT_NAME}_tests})
  set(TEST_RUNNER "${PROJECT_NAME}_test")
  enable_testing()

  # Add the Google Test dependency; EXCLUDE_FROM_ALL, so only the test target builds it.
  include(FetchContent)
  FetchContent_Declare(googletest URL https://github.com/google/googletest/archive/refs/tags/v1.18.0.zip
                                      EXCLUDE_FROM_ALL)
  # Normal variables, not FORCEd cache entries, so this googletest leaves the cache alone.
  set(gtest_force_shared_crt ON)
  set(INSTALL_GTEST OFF)
  FetchContent_MakeAvailable(googletest)

  # The sources compiled in, as the C API is too narrow; EXCLUDE_FROM_ALL, so a broken test never breaks the app build.
  add_executable(${TEST_RUNNER} EXCLUDE_FROM_ALL test/kataglyphis_native_inference_plugin_test.cpp ${PLUGIN_SOURCES})
  apply_standard_settings(${TEST_RUNNER})
  target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
  target_include_directories(${TEST_RUNNER} PRIVATE "${KCI_TEXTURE_ABI_DIR}")
  target_link_libraries(${TEST_RUNNER} PRIVATE flutter_wrapper_plugin kci_plugin_quality)
  target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)
  # flutter_wrapper_plugin has link dependencies on the Flutter DLL.
  add_custom_command(
    TARGET ${TEST_RUNNER}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${FLUTTER_LIBRARY}" $<TARGET_FILE_DIR:${TEST_RUNNER}>)

  # PRE_TEST: listing the tests runs the binary, which belongs in ctest, not in the build.
  include(GoogleTest)
  gtest_discover_tests(${TEST_RUNNER} DISCOVERY_MODE PRE_TEST)
endif()
