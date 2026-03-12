cmake_minimum_required(VERSION 3.25)
project(NablaAssetManifestsSmoke NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../nam.cmake")

option(NAM_SMOKE_NO_SYMLINKS "Force copy materialization in the smoke consumer." OFF)

set(_nam_extra_args)
if (NAM_SMOKE_NO_SYMLINKS)
    list(APPEND _nam_extra_args NO_SYMLINKS)
endif()

nam_add_channel_target(
    TARGET media
    DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}"
    ${_nam_extra_args}
)
