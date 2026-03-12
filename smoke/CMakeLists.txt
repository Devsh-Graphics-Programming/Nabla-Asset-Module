cmake_minimum_required(VERSION 3.25)
project(NablaAssetManifestsSmoke NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../nam.cmake")

nam_add_channel_target(
    TARGET media
    DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}"
)
