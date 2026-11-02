include("${CMAKE_CURRENT_LIST_DIR}/../../rust_builder/linux/oxidant-ort-devices.cmake")

function(omni_windows_ort_device output oxidant_dir)
  if(NOT DEFINED OMNI_WINDOWS_ORT_PROVIDER OR OMNI_WINDOWS_ORT_PROVIDER STREQUAL "")
    set(OMNI_WINDOWS_ORT_PROVIDER "cpu")
  endif()
  if(NOT
     OMNI_WINDOWS_ORT_PROVIDER
     MATCHES
     "^(cpu|cuda|directml)$")
    message(FATAL_ERROR "OMNI_WINDOWS_ORT_PROVIDER must be cpu, cuda, or directml")
  endif()
  if(NOT
     OMNI_WINDOWS_ORT_PROVIDER
     STREQUAL
     "cpu")
    foreach(_arch IN ITEMS "${FLUTTER_TARGET_PLATFORM}" "${CMAKE_GENERATOR_PLATFORM}" "${CMAKE_CXX_COMPILER_TARGET}")
      if(_arch MATCHES "[Aa][Rr][Mm]|[Aa][Aa][Rr][Cc][Hh]64")
        message(FATAL_ERROR "Windows GPU builds are supported on x64 only")
      endif()
    endforeach()
    omni_oxidant_advertises_ort_device(_supported "${oxidant_dir}" "${OMNI_WINDOWS_ORT_PROVIDER}")
    if(NOT _supported)
      message(
        FATAL_ERROR
          "Windows GPU builds require an OxidANT pin advertising strict ${OMNI_WINDOWS_ORT_PROVIDER} selection")
    endif()
  endif()
  set(${output}
      "${OMNI_WINDOWS_ORT_PROVIDER}"
      PARENT_SCOPE)
endfunction()
