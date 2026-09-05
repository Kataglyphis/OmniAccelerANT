cmake_minimum_required(VERSION 3.22)
project(kataglyphis_native_inference LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Resolve GStreamer Android SDK root.
# Prefer an explicitly provided CMake variable (-DGSTREAMER_ROOT_ANDROID=...),
# otherwise fall back to the environment variable.
if(NOT GSTREAMER_ROOT_ANDROID)
    if(DEFINED ENV{GSTREAMER_ROOT_ANDROID})
        set(GSTREAMER_ROOT_ANDROID "$ENV{GSTREAMER_ROOT_ANDROID}")
    endif()
endif()

if(NOT GSTREAMER_ROOT_ANDROID)
    message(FATAL_ERROR "GSTREAMER_ROOT_ANDROID must be set (either environment variable GSTREAMER_ROOT_ANDROID or -DGSTREAMER_ROOT_ANDROID=/path/to/gstreamer/android/sdk)")
endif()

# Some Android GStreamer SDKs name ABI dirs differently (e.g., arm64-v8a vs arm64).
set(_GSTREAMER_ALT_ABI "${CMAKE_ANDROID_ARCH_ABI}")
if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
    set(_GSTREAMER_ALT_ABI "arm64")
elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "armeabi-v7a")
    set(_GSTREAMER_ALT_ABI "armv7")
endif()

# The Android GStreamer SDK may be installed either as:
#   - per-ABI subdirectories under GSTREAMER_ROOT_ANDROID (preferred), or
#   - a single flat prefix (include/, lib/, ...).
set(GStreamer_ROOT_DIR "${GSTREAMER_ROOT_ANDROID}")
if(EXISTS "${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/lib")
    set(GStreamer_ROOT_DIR "${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}")
elseif(EXISTS "${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/lib")
    set(GStreamer_ROOT_DIR "${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}")
endif()

# Prefer static libs when the SDK provides them; otherwise fall back to shared.
# (The official Android "universal" packages often ship shared .so libs.)
if(NOT DEFINED GStreamer_USE_STATIC_LIBS)
    if(EXISTS "${GStreamer_ROOT_DIR}/lib/libgstreamer-1.0.a" OR EXISTS "${GStreamer_ROOT_DIR}/libgstreamer-1.0.a")
        set(GStreamer_USE_STATIC_LIBS ON)
    else()
        set(GStreamer_USE_STATIC_LIBS OFF)
    endif()
endif()
# Pull in extra modules we need (video).
set(GSTREAMER_EXTRA_DEPS gstreamer-video-1.0)

# Help CMake discover the config package shipped with the Android GStreamer SDK.
set(_GSTREAMER_HINT_DIRS
    ${GSTREAMER_ROOT_ANDROID}
    ${GSTREAMER_ROOT_ANDROID}/cmake
    ${GSTREAMER_ROOT_ANDROID}/lib/cmake
    ${GSTREAMER_ROOT_ANDROID}/lib/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/lib/cmake/GStreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/share/cmake
    ${GSTREAMER_ROOT_ANDROID}/share/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/share/cmake/GStreamer-1.0
    # ABI-scoped subdirs used by the official Android GStreamer SDK layout
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/lib/cmake
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/lib/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/lib/cmake/GStreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/share/cmake
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/share/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/share/cmake/GStreamer-1.0
    # Alternate ABI folder names sometimes used by prebuilt SDKs
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/lib/cmake
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/lib/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/lib/cmake/GStreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/share/cmake
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/share/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/share/cmake/GStreamer-1.0
)
list(PREPEND CMAKE_PREFIX_PATH ${_GSTREAMER_HINT_DIRS})
list(PREPEND CMAKE_FIND_ROOT_PATH ${GSTREAMER_ROOT_ANDROID})
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

# Add local cmake module path FIRST (contains our FindGStreamer.cmake)
list(PREPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)

list(PREPEND CMAKE_MODULE_PATH
    ${GSTREAMER_ROOT_ANDROID}/share/cmake
    ${GSTREAMER_ROOT_ANDROID}/share/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/share/cmake/GStreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/share/cmake
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/share/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/share/cmake/GStreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/share/cmake
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/share/cmake/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/share/cmake/GStreamer-1.0
)

# Prefer the SDK-provided find module, fallback to our local FindGStreamer.cmake
list(APPEND CMAKE_MODULE_PATH
    ${GStreamer_ROOT_DIR}/share/cmake
    ${GStreamer_ROOT_DIR}/share/cmake/gstreamer-1.0
)

find_package(GStreamer REQUIRED MODULE)

# GLib regex pulls in pcre2; the Android SDK ships it as a static lib.
find_library(PCRE2_LIB
    NAMES pcre2-8
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

# GLib plugin loading needs gmodule; conversions need iconv; gobject marshalling needs ffi.
find_library(GMODULE_LIB
    NAMES gmodule-2.0
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(ICONV_LIB
    NAMES iconv
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(FFI_LIB
    NAMES ffi
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

# Candidate locations for GStreamer plugin libs (.a/.so modules)
set(_GST_PLUGIN_DIR_HINTS
    ${GStreamer_ROOT_DIR}/lib/gstreamer-1.0
    ${GStreamer_ROOT_DIR}/lib
    ${GStreamer_ROOT_DIR}/gstreamer-1.0
    ${GStreamer_ROOT_DIR}/gst-android
    ${GStreamer_ROOT_DIR}
    ${GSTREAMER_ROOT_ANDROID}/lib/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/gstreamer-1.0
    ${GSTREAMER_ROOT_ANDROID}/gst-android
)

# Static plugin libs we need (coreelements contains videoconvert/appsink; add videotestsrc and androidmedia).
find_library(GST_COREELEMENTS_LIB
    NAMES gstcoreelements gstcoreelements-1.0 gstcoreelements-1.0
    HINTS ${_GST_PLUGIN_DIR_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_library(GST_APP_LIB
    NAMES gstapp gstapp-1.0
    HINTS ${_GST_PLUGIN_DIR_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_library(GST_VIDEOTESTSRC_LIB
    NAMES gstvideotestsrc gstvideotestsrc-1.0
    HINTS ${_GST_PLUGIN_DIR_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

# Autodetect plugin (provides autovideosrc).
find_library(GST_AUTODETECT_LIB
    NAMES gstautodetect gstautodetect-1.0
    HINTS ${_GST_PLUGIN_DIR_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH)

# Android media plugin.
# In the GStreamer SDK this typically follows the pattern libgst<plugin>.a/.so,
# i.e. libgstandroidmedia.* (NOT libgstandroidmedia.*).
find_library(GST_ANDROIDMEDIA_LIB
    NAMES
        gstandroidmedia gstandroidmedia-1.0
    HINTS 
        ${GStreamer_ROOT_DIR}/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/${_GSTREAMER_ALT_ABI}/lib/gstreamer-1.0
    PATHS 
        ${GSTREAMER_ROOT_ANDROID}/arm64/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/armv7/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/x86/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/x86_64/lib/gstreamer-1.0
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH)

find_library(GST_AHC_LIB
    NAMES gstahc-1.0 gstahc gstndk-1.0 gstndk gstcamera-1.0 gstcamera
    HINTS ${GStreamer_ROOT_DIR}/lib/gstreamer-1.0 ${GStreamer_ROOT_DIR}
    PATHS 
        ${GSTREAMER_ROOT_ANDROID}/${CMAKE_ANDROID_ARCH_ABI}/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/arm64/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/armv7/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/x86/lib/gstreamer-1.0
        ${GSTREAMER_ROOT_ANDROID}/x86_64/lib/gstreamer-1.0
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH)

find_library(GST_OPENGL_LIB
    NAMES gstopengl gstopengl-1.0
    HINTS ${_GST_PLUGIN_DIR_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_library(GST_GL_LIB
    NAMES gstgl-1.0
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(GST_PBUTILS_LIB
    NAMES gstpbutils-1.0
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

# Video format conversion and filters (optional - may be part of coreelements)
find_library(GST_VIDEOCONVERT_LIB
    NAMES
        gstvideoconvert-1.0 gstvideoconvert
        gstvideoconvertscale-1.0 gstvideoconvertscale
    HINTS ${GStreamer_ROOT_DIR}/lib/gstreamer-1.0 ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH)

find_library(GST_VIDEOSCALE_LIB
    NAMES gstvideoscale-1.0 gstvideoscale
    HINTS ${GStreamer_ROOT_DIR}/lib/gstreamer-1.0 ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH)

find_library(GST_AUDIO_LIB
    NAMES gstaudio-1.0
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(GST_PHOTOGRAPHY_LIB
    NAMES gstphotography-1.0
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(ORC_LIB
    NAMES orc-0.4
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(PNG_LIB
    NAMES png16 png
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(JPEG_LIB
    NAMES jpeg
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(ZLIB_LIB
    NAMES z zlib
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(GRAPHENE_LIB
    NAMES graphene-1.0 graphene
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

find_library(GST_CONTROLLER_LIB
    NAMES gstcontroller-1.0
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

# Core app library (contains gst_app_src/sink types).
find_library(GST_APP_CORE_LIB
    NAMES gstapp-1.0
    HINTS ${GStreamer_ROOT_DIR}/lib ${GStreamer_ROOT_DIR}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)

add_library(kataglyphis_native_inference SHARED gstreamer_native.cpp)

# Set compile definitions if optional plugins are available
if(GST_ANDROIDMEDIA_LIB)
    target_compile_definitions(kataglyphis_native_inference PRIVATE GST_ANDROIDMEDIA_AVAILABLE)
    message(STATUS "Enabling GST_ANDROIDMEDIA_AVAILABLE")
else()
    message(STATUS "GST_ANDROIDMEDIA_LIB not found - androidmedia plugin will NOT be linked")
endif()
if(GST_AHC_LIB)
    target_compile_definitions(kataglyphis_native_inference PRIVATE GST_AHC_AVAILABLE)
    message(STATUS "Enabling GST_AHC_AVAILABLE")
endif()
if(GST_VIDEOCONVERT_LIB)
    target_compile_definitions(kataglyphis_native_inference PRIVATE GST_VIDEOCONVERT_AVAILABLE)
    message(STATUS "Enabling GST_VIDEOCONVERT_AVAILABLE")
endif()
if(GST_AUTODETECT_LIB)
    target_compile_definitions(kataglyphis_native_inference PRIVATE GST_AUTODETECT_AVAILABLE)
    message(STATUS "Enabling GST_AUTODETECT_AVAILABLE")
endif()

# Build plugin list for whole-archive (only what exists in the SDK)
set(_WHOLE_ARCHIVE_PLUGINS)
if(GST_COREELEMENTS_LIB)
    list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_COREELEMENTS_LIB})
else()
    message(STATUS "GST_COREELEMENTS_LIB not found - continuing without static coreelements")
endif()
if(GST_APP_LIB)
    list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_APP_LIB})
else()
    message(STATUS "GST_APP_LIB (plugin) not found - continuing without static gstapp plugin")
endif()
if(GST_VIDEOTESTSRC_LIB)
    list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_VIDEOTESTSRC_LIB})
else()
    message(STATUS "GST_VIDEOTESTSRC_LIB not found - continuing without static videotestsrc")
endif()
if(GST_OPENGL_LIB)
    list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_OPENGL_LIB})
else()
    message(STATUS "GST_OPENGL_LIB (plugin) not found - continuing without static gstopengl")
endif()

# Diagnose: Print which optional plugins are available
message(STATUS "=== GStreamer Build Configuration ===")
message(STATUS "CMAKE_ANDROID_ARCH_ABI: ${CMAKE_ANDROID_ARCH_ABI}")
message(STATUS "GStreamer_ROOT_DIR: ${GStreamer_ROOT_DIR}")
message(STATUS "GSTREAMER_ROOT_ANDROID: ${GSTREAMER_ROOT_ANDROID}")
message(STATUS "=== GStreamer Plugin Availability ===")
message(STATUS "GStreamer SDK: ${GStreamer_ROOT_DIR}")
message(STATUS "Core plugins: FOUND")
if(GST_ANDROIDMEDIA_LIB)
    message(STATUS "Android Media plugin: FOUND (${GST_ANDROIDMEDIA_LIB})")
    list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_ANDROIDMEDIA_LIB})
else()
    message(STATUS "Android Media plugin: NOT FOUND")
endif()
if(GST_AHC_LIB)
    message(STATUS "Android Camera (ahc/ndk) plugin: FOUND (${GST_AHC_LIB})")
    list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_AHC_LIB})
else()
    message(STATUS "Android Camera (ahc/ndk) plugin: NOT FOUND")
    message(STATUS "  Tip: Download GStreamer SDK with gstahc or gstandroidmedia plugins")
    message(STATUS "  See: GSTREAMER_SETUP.md for detailed instructions")
endif()
if(GST_VIDEOCONVERT_LIB)
    message(STATUS "Videoconvert plugin: FOUND")
    list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_VIDEOCONVERT_LIB})
endif()
if(GST_VIDEOSCALE_LIB)
    message(STATUS "Videoscale plugin: FOUND")
    # Avoid duplicate symbols if videoscale is provided by videoconvertscale (combined plugin).
    if(NOT GST_VIDEOSCALE_LIB STREQUAL GST_VIDEOCONVERT_LIB)
        list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_VIDEOSCALE_LIB})
    endif()
endif()
if(GST_AUTODETECT_LIB)
    message(STATUS "Autodetect plugin: FOUND (${GST_AUTODETECT_LIB})")
    list(APPEND _WHOLE_ARCHIVE_PLUGINS ${GST_AUTODETECT_LIB})
else()
    message(STATUS "Autodetect plugin: NOT FOUND")
endif()
message(STATUS "======================================")


target_link_libraries(kataglyphis_native_inference
    PRIVATE
        GStreamer::GStreamer
        ${PCRE2_LIB}
        ${GMODULE_LIB}
        ${ICONV_LIB}
        ${FFI_LIB}
        ${GST_APP_CORE_LIB}
        ${GST_GL_LIB}
        ${GST_AUDIO_LIB}
        ${GST_PHOTOGRAPHY_LIB}
        ${PNG_LIB}
        ${JPEG_LIB}
        ${ZLIB_LIB}
        ${GRAPHENE_LIB}
        ${GST_CONTROLLER_LIB}
        -Wl,--start-group
            -Wl,--whole-archive ${_WHOLE_ARCHIVE_PLUGINS} -Wl,--no-whole-archive
            ${GSTREAMER_VIDEO_LIBRARY}
            ${GST_GL_LIB}
            ${GST_PBUTILS_LIB}
            ${GSTREAMER_BASE_LIBRARY}
            ${GSTREAMER_LIBRARY}
            ${GOBJECT_LIBRARY}
            ${GLIB_LIBRARY}
            ${ORC_LIB}
        -Wl,--end-group
        android
        log
        EGL
        GLESv2
        mediandk     # Required for androidmedia plugin (Camera2 API)
        camera2ndk   # Required for ahc2src element (Camera2 NDK)
        ${INTL_LIBRARY}
        m
        dl
        atomic)

# Keep plugin register symbols alive
set(_PLUGIN_SYMBOLS
    # Keep JNI_OnLoad from libgstreamer-1.0.a alive - this registers the native method
    # for org.freedesktop.gstreamer.GStreamer.nativeInit() which sets up the application
    # context and class loader needed by the androidmedia plugin.
    -Wl,-u,JNI_OnLoad)

if(GST_COREELEMENTS_LIB)
    list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_coreelements_register)
endif()
if(GST_APP_LIB)
    list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_app_register)
endif()
if(GST_VIDEOTESTSRC_LIB)
    list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_videotestsrc_register)
endif()
if(GST_OPENGL_LIB)
    list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_opengl_register)
endif()
if(GST_ANDROIDMEDIA_LIB)
    list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_androidmedia_register)
endif()
if(GST_AHC_LIB)
    list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_ahc_register -Wl,-u,gst_plugin_ndk_register)
endif()
if(GST_VIDEOCONVERT_LIB)
    list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_videoconvertscale_register)
endif()
if(GST_VIDEOSCALE_LIB)
    # Avoid forcing an unresolved symbol if videoscale comes from the combined videoconvertscale plugin.
    if(NOT GST_VIDEOSCALE_LIB STREQUAL GST_VIDEOCONVERT_LIB)
        list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_videoscale_register)
    endif()
endif()
if(GST_AUTODETECT_LIB)
    list(APPEND _PLUGIN_SYMBOLS -Wl,-u,gst_plugin_autodetect_register)
endif()

target_link_options(kataglyphis_native_inference PRIVATE ${_PLUGIN_SYMBOLS})

target_compile_definitions(kataglyphis_native_inference PRIVATE GST_DISABLE_DEPRECATED)
