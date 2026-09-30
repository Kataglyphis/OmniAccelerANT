# Project-level configuration.
cmake_minimum_required(VERSION 3.31.6)
project(omni_accelerant LANGUAGES CXX)

# The executable's on-disk name.
set(BINARY_NAME "omni_accelerant")

# Opt in to modern CMake behaviour to avoid warnings with recent CMake.
cmake_policy(VERSION 3.14...3.25)

# Release CRT (/MD) even in Debug: ASan under clang-cl does not support /MDd.
set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES
      "Debug;Profile;Release"
      CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE
        "Debug"
        CACHE STRING "Flutter build mode" FORCE)
    set_property(
      CACHE CMAKE_BUILD_TYPE
      PROPERTY STRINGS
               "Debug"
               "Profile"
               "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Plugins use these settings by default too, so add new options to specific targets instead.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W3 /wd4100) # /WX
  # clang-cl only: MSVC's cl reads -W<n> as a warning level and stops with D8021 (the MSVC presets).
  if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(${TARGET} PRIVATE -Wno-cast-function-type-mismatch -Wno-unused-function)
  endif()
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Clang-CL compatibility: Ignore unused MSVC-specific flags like /await
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wno-unused-command-line-argument)
  add_compile_options(-Wno-unused-lambda-capture)
  add_compile_options(-Wno-error=unused-lambda-capture)
  # Warnings are never errors globally, which works around plugin bugs.
  add_compile_options(-Wno-error)
endif()

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules, which build the plugins and add them to the application.
include(flutter/generated_plugins.cmake)

# Installation: support files sit next to the executable so it also runs in place from Visual Studio.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX
      "${BUILD_BUNDLE_DIR}"
      CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)

install(
  FILES "${FLUTTER_ICU_DATA_FILE}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(
  FILES "${FLUTTER_LIBRARY}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(
    FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(
  DIRECTORY "${NATIVE_ASSETS_DIR}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Re-copy the assets directory on every build so no stale files survive.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(
  DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(
  FILES "${AOT_LIBRARY}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
