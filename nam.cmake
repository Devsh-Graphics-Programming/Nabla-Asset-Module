include("${CMAKE_CURRENT_LIST_DIR}/cmake/NablaAssetManifests.cmake")

if (CMAKE_SCRIPT_MODE_FILE)
    set(_nam_args)
    if (DEFINED CMAKE_ARGC)
        math(EXPR _nam_last "${CMAKE_ARGC} - 1")
        foreach(_idx RANGE 3 ${_nam_last})
            list(APPEND _nam_args "${CMAKE_ARGV${_idx}}")
        endforeach()
    endif()

    if (NOT _nam_args)
        message(FATAL_ERROR "Usage: cmake -P nam.cmake <cmake-function> [function-args...]")
    endif()

    list(POP_FRONT _nam_args _nam_function)
    cmake_language(CALL "${_nam_function}" ${_nam_args})
endif()
