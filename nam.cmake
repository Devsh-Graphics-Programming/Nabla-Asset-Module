include("${CMAKE_CURRENT_LIST_DIR}/cmake/NablaAssetManifests.cmake")

if (CMAKE_SCRIPT_MODE_FILE)
    message(FATAL_ERROR "nam.cmake is include-only. Use it from a normal CMake project.")
endif()
