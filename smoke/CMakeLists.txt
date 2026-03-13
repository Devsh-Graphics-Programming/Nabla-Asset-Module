cmake_minimum_required(VERSION 3.25)
project(NablaAssetManifestsSmoke NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../nam.cmake")

option(NAM_SMOKE_NO_SYMLINKS "Force copy materialization in the smoke consumer." OFF)
set(NAM_SMOKE_LINK_MODE "auto" CACHE STRING "Smoke materialization mode override.")
set_property(CACHE NAM_SMOKE_LINK_MODE PROPERTY STRINGS auto symlink hardlink copy)
set(NAM_SMOKE_CACHE_ROOT "" CACHE PATH "Shared cache root for smoke runs.")
set(NAM_SMOKE_MANIFEST_ROOT "" CACHE PATH "Manifest root override for smoke runs.")
set(NAM_SMOKE_REPO "Devsh-Graphics-Programming/Nabla-Asset-Manifests" CACHE STRING "GitHub repository override for smoke runs.")
set(NAM_SMOKE_TAG "media" CACHE STRING "Release tag override for smoke runs.")
set(NAM_SMOKE_CHANNEL "media" CACHE STRING "Channel override for smoke runs.")

string(TOLOWER "${NAM_SMOKE_LINK_MODE}" _nam_smoke_link_mode)
if (
    NOT _nam_smoke_link_mode STREQUAL "auto"
    AND NOT _nam_smoke_link_mode STREQUAL "copy"
    AND NOT _nam_smoke_link_mode STREQUAL "hardlink"
    AND NOT _nam_smoke_link_mode STREQUAL "symlink"
)
    message(FATAL_ERROR "NAM_SMOKE_LINK_MODE must be one of: auto, symlink, hardlink, copy")
endif()

if (
    NAM_SMOKE_NO_SYMLINKS
    AND NOT _nam_smoke_link_mode STREQUAL "auto"
    AND NOT _nam_smoke_link_mode STREQUAL "copy"
)
    message(FATAL_ERROR "NAM_SMOKE_NO_SYMLINKS conflicts with NAM_SMOKE_LINK_MODE=`${_nam_smoke_link_mode}`")
endif()

set(_nam_extra_args)
if (NAM_SMOKE_CACHE_ROOT)
    list(APPEND _nam_extra_args CACHE_ROOT "${NAM_SMOKE_CACHE_ROOT}")
endif()
if (NAM_SMOKE_MANIFEST_ROOT)
    list(APPEND _nam_extra_args MANIFEST_ROOT "${NAM_SMOKE_MANIFEST_ROOT}")
endif()
if (NAM_SMOKE_REPO)
    list(APPEND _nam_extra_args REPO "${NAM_SMOKE_REPO}")
endif()
if (NAM_SMOKE_TAG)
    list(APPEND _nam_extra_args TAG "${NAM_SMOKE_TAG}")
endif()
if (NAM_SMOKE_CHANNEL)
    list(APPEND _nam_extra_args CHANNEL "${NAM_SMOKE_CHANNEL}")
endif()

unset(NAM_INTERNAL_FORCE_FILE_LINK_MODE)
if (_nam_smoke_link_mode STREQUAL "copy" OR NAM_SMOKE_NO_SYMLINKS)
    list(APPEND _nam_extra_args NO_SYMLINKS)
elseif(NOT _nam_smoke_link_mode STREQUAL "auto")
    set(NAM_INTERNAL_FORCE_FILE_LINK_MODE "${_nam_smoke_link_mode}")
endif()

nam_add_channel_target(
    TARGET media
    DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}"
    ${_nam_extra_args}
)

unset(NAM_INTERNAL_FORCE_FILE_LINK_MODE)
