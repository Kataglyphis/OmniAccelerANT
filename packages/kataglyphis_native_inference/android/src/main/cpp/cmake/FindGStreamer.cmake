# FindGStreamer.cmake - Find GStreamer for Android
#
# This module defines:
#   GSTREAMER_FOUND        - True if GStreamer was found
#   GSTREAMER_INCLUDE_DIRS - Include directories for GStreamer
#   GSTREAMER_LIBRARIES    - Libraries to link against
#   GSTREAMER_VERSION      - GStreamer version string
#
# Expected variables:
#   GStreamer_ROOT_DIR     - Root directory of GStreamer Android SDK (per-ABI)
#   GStreamer_USE_STATIC_LIBS - Whether to use static libraries

if(NOT DEFINED GStreamer_ROOT_DIR)
    message(FATAL_ERROR "GStreamer_ROOT_DIR must be set to the GStreamer Android SDK root (per-ABI)")
endif()

message(STATUS "FindGStreamer: Using GStreamer_ROOT_DIR=${GStreamer_ROOT_DIR}")

# The Android GStreamer SDK can be laid out in (at least) two ways:
#  - "classic" prefix: include/ + lib/ under GStreamer_ROOT_DIR
#  - "flat" prefix (as in our GHCR image): headers and .a/.so live directly under GStreamer_ROOT_DIR
#    with directories like gstreamer-1.0/, glib-2.0/, pkgconfig/ at the top.

set(_GSTREAMER_INCLUDE_HINTS
    ${GStreamer_ROOT_DIR}/include
    ${GStreamer_ROOT_DIR}
)

set(_GSTREAMER_LIBRARY_HINTS
    ${GStreamer_ROOT_DIR}/lib
    ${GStreamer_ROOT_DIR}
)

# Find GStreamer include directory
find_path(GSTREAMER_INCLUDE_DIR
    NAMES gst/gst.h
    HINTS 
        ${GStreamer_ROOT_DIR}/include/gstreamer-1.0
        ${GStreamer_ROOT_DIR}/include
        ${GStreamer_ROOT_DIR}
    PATH_SUFFIXES gstreamer-1.0
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

# Find GLib include directories (required by GStreamer)
find_path(GLIB_INCLUDE_DIR
    NAMES glib.h
    HINTS ${_GSTREAMER_INCLUDE_HINTS}
    PATH_SUFFIXES glib-2.0
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_path(GLIB_CONFIG_INCLUDE_DIR
    NAMES glibconfig.h
    HINTS 
        ${GStreamer_ROOT_DIR}/lib/glib-2.0/include
        ${GStreamer_ROOT_DIR}/glib-2.0/include
        ${GStreamer_ROOT_DIR}/lib
        ${GStreamer_ROOT_DIR}
    PATH_SUFFIXES glib-2.0/include
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

# Determine library suffix based on static/shared preference
if(GStreamer_USE_STATIC_LIBS)
    set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
else()
    set(CMAKE_FIND_LIBRARY_SUFFIXES ".so")
endif()

# Find core GStreamer libraries
find_library(GSTREAMER_LIBRARY
    NAMES gstreamer-1.0 libgstreamer-1.0
    HINTS ${_GSTREAMER_LIBRARY_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_library(GSTREAMER_BASE_LIBRARY
    NAMES gstbase-1.0 libgstbase-1.0
    HINTS ${_GSTREAMER_LIBRARY_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_library(GSTREAMER_VIDEO_LIBRARY
    NAMES gstvideo-1.0 libgstvideo-1.0
    HINTS ${_GSTREAMER_LIBRARY_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_library(GSTREAMER_APP_LIBRARY
    NAMES gstapp-1.0 libgstapp-1.0
    HINTS ${_GSTREAMER_LIBRARY_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

# Find GLib libraries (dependencies)
find_library(GLIB_LIBRARY
    NAMES glib-2.0 libglib-2.0
    HINTS ${_GSTREAMER_LIBRARY_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_library(GOBJECT_LIBRARY
    NAMES gobject-2.0 libgobject-2.0
    HINTS ${_GSTREAMER_LIBRARY_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

find_library(GIO_LIBRARY
    NAMES gio-2.0 libgio-2.0
    HINTS ${_GSTREAMER_LIBRARY_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

# Find INTL library (often required on Android)
find_library(INTL_LIBRARY
    NAMES intl libintl
    HINTS ${_GSTREAMER_LIBRARY_HINTS}
    NO_DEFAULT_PATH
    NO_CMAKE_FIND_ROOT_PATH
)

# Try to get version from pkgconfig
set(_GSTREAMER_PC_CANDIDATES
    "${GStreamer_ROOT_DIR}/lib/pkgconfig/gstreamer-1.0.pc"
    "${GStreamer_ROOT_DIR}/pkgconfig/gstreamer-1.0.pc"
)
foreach(_pc IN LISTS _GSTREAMER_PC_CANDIDATES)
    if(EXISTS "${_pc}")
        set(_GSTREAMER_PC_FILE "${_pc}")
        break()
    endif()
endforeach()

if(DEFINED _GSTREAMER_PC_FILE AND EXISTS "${_GSTREAMER_PC_FILE}")
    file(STRINGS "${_GSTREAMER_PC_FILE}" _GSTREAMER_VERSION_LINE REGEX "^Version:")
    if(_GSTREAMER_VERSION_LINE)
        string(REGEX REPLACE "^Version:[ \t]*" "" GSTREAMER_VERSION "${_GSTREAMER_VERSION_LINE}")
        string(STRIP "${GSTREAMER_VERSION}" GSTREAMER_VERSION)
    endif()
endif()

if(NOT GSTREAMER_VERSION)
    set(GSTREAMER_VERSION "1.0.0")  # Fallback
endif()

# Collect include directories
set(GSTREAMER_INCLUDE_DIRS)
if(GSTREAMER_INCLUDE_DIR)
    list(APPEND GSTREAMER_INCLUDE_DIRS ${GSTREAMER_INCLUDE_DIR})
endif()
if(GLIB_INCLUDE_DIR)
    list(APPEND GSTREAMER_INCLUDE_DIRS ${GLIB_INCLUDE_DIR})
endif()
if(GLIB_CONFIG_INCLUDE_DIR)
    list(APPEND GSTREAMER_INCLUDE_DIRS ${GLIB_CONFIG_INCLUDE_DIR})
endif()
# Add general include path
if(EXISTS "${GStreamer_ROOT_DIR}/include")
    list(APPEND GSTREAMER_INCLUDE_DIRS ${GStreamer_ROOT_DIR}/include)
else()
    # Flat prefix layout
    list(APPEND GSTREAMER_INCLUDE_DIRS ${GStreamer_ROOT_DIR})
endif()

# Collect libraries
set(GSTREAMER_LIBRARIES)
if(GSTREAMER_LIBRARY)
    list(APPEND GSTREAMER_LIBRARIES ${GSTREAMER_LIBRARY})
endif()
if(GSTREAMER_BASE_LIBRARY)
    list(APPEND GSTREAMER_LIBRARIES ${GSTREAMER_BASE_LIBRARY})
endif()
if(GSTREAMER_VIDEO_LIBRARY)
    list(APPEND GSTREAMER_LIBRARIES ${GSTREAMER_VIDEO_LIBRARY})
endif()
if(GSTREAMER_APP_LIBRARY)
    list(APPEND GSTREAMER_LIBRARIES ${GSTREAMER_APP_LIBRARY})
endif()
if(GLIB_LIBRARY)
    list(APPEND GSTREAMER_LIBRARIES ${GLIB_LIBRARY})
endif()
if(GOBJECT_LIBRARY)
    list(APPEND GSTREAMER_LIBRARIES ${GOBJECT_LIBRARY})
endif()
if(GIO_LIBRARY)
    list(APPEND GSTREAMER_LIBRARIES ${GIO_LIBRARY})
endif()
if(INTL_LIBRARY)
    list(APPEND GSTREAMER_LIBRARIES ${INTL_LIBRARY})
endif()

# Standard CMake find_package handling
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(GStreamer
    REQUIRED_VARS
        GSTREAMER_LIBRARY
        GSTREAMER_INCLUDE_DIR
        GLIB_LIBRARY
        GOBJECT_LIBRARY
    VERSION_VAR GSTREAMER_VERSION
)

# Create imported targets for modern CMake usage
if(GSTREAMER_FOUND AND NOT TARGET GStreamer::GStreamer)
    add_library(GStreamer::GStreamer UNKNOWN IMPORTED)
    set_target_properties(GStreamer::GStreamer PROPERTIES
        IMPORTED_LOCATION "${GSTREAMER_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${GSTREAMER_INCLUDE_DIRS}"
    )
    
    if(GSTREAMER_BASE_LIBRARY)
        add_library(GStreamer::Base UNKNOWN IMPORTED)
        set_target_properties(GStreamer::Base PROPERTIES
            IMPORTED_LOCATION "${GSTREAMER_BASE_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${GSTREAMER_INCLUDE_DIRS}"
        )
    endif()
    
    if(GSTREAMER_VIDEO_LIBRARY)
        add_library(GStreamer::Video UNKNOWN IMPORTED)
        set_target_properties(GStreamer::Video PROPERTIES
            IMPORTED_LOCATION "${GSTREAMER_VIDEO_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${GSTREAMER_INCLUDE_DIRS}"
        )
    endif()
    
    if(GSTREAMER_APP_LIBRARY)
        add_library(GStreamer::App UNKNOWN IMPORTED)
        set_target_properties(GStreamer::App PROPERTIES
            IMPORTED_LOCATION "${GSTREAMER_APP_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${GSTREAMER_INCLUDE_DIRS}"
        )
    endif()
endif()

mark_as_advanced(
    GSTREAMER_INCLUDE_DIR
    GSTREAMER_LIBRARY
    GSTREAMER_BASE_LIBRARY
    GSTREAMER_VIDEO_LIBRARY
    GSTREAMER_APP_LIBRARY
    GLIB_INCLUDE_DIR
    GLIB_CONFIG_INCLUDE_DIR
    GLIB_LIBRARY
    GOBJECT_LIBRARY
    GIO_LIBRARY
    INTL_LIBRARY
)

message(STATUS "FindGStreamer: GSTREAMER_FOUND=${GSTREAMER_FOUND}")
message(STATUS "FindGStreamer: GSTREAMER_INCLUDE_DIRS=${GSTREAMER_INCLUDE_DIRS}")
message(STATUS "FindGStreamer: GSTREAMER_LIBRARIES=${GSTREAMER_LIBRARIES}")
