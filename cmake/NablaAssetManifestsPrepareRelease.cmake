# Small maintainer wrapper for flattened release preparation.
# It writes the minimal `.dvc` sidecar format directly in pure CMake and does
# not require a local `dvc` installation.
# Reference format:
# https://dvc.org/doc/user-guide/project-structure/dvc-files

if(NOT DEFINED SOURCE_ROOT OR "${SOURCE_ROOT}" STREQUAL "")
    message(FATAL_ERROR "NablaAssetManifestsPrepareRelease: SOURCE_ROOT is required")
endif()
if(NOT DEFINED PAYLOAD_ROOT OR "${PAYLOAD_ROOT}" STREQUAL "")
    message(FATAL_ERROR "NablaAssetManifestsPrepareRelease: PAYLOAD_ROOT is required")
endif()
if(NOT DEFINED MANIFEST_ROOT OR "${MANIFEST_ROOT}" STREQUAL "")
    message(FATAL_ERROR "NablaAssetManifestsPrepareRelease: MANIFEST_ROOT is required")
endif()
if(NOT DEFINED CHANNEL OR "${CHANNEL}" STREQUAL "")
    message(FATAL_ERROR "NablaAssetManifestsPrepareRelease: CHANNEL is required")
endif()

get_filename_component(SOURCE_ROOT "${SOURCE_ROOT}" ABSOLUTE)
get_filename_component(PAYLOAD_ROOT "${PAYLOAD_ROOT}" ABSOLUTE)
get_filename_component(MANIFEST_ROOT "${MANIFEST_ROOT}" ABSOLUTE)
if(DEFINED MANIFESTS_ZIP AND NOT "${MANIFESTS_ZIP}" STREQUAL "")
    get_filename_component(MANIFESTS_ZIP "${MANIFESTS_ZIP}" ABSOLUTE)
endif()
set(_channel_manifest_root "${MANIFEST_ROOT}/${CHANNEL}")

if(NOT EXISTS "${SOURCE_ROOT}")
    message(FATAL_ERROR "NablaAssetManifestsPrepareRelease: SOURCE_ROOT does not exist: ${SOURCE_ROOT}")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/NablaAssetManifests.cmake")

function(_nam_write_minimal_dvc_manifest OUTPUT_PATH FILE_NAME FILE_MD5 FILE_SIZE)
    get_filename_component(_output_dir "${OUTPUT_PATH}" DIRECTORY)
    file(MAKE_DIRECTORY "${_output_dir}")
    file(WRITE "${OUTPUT_PATH}"
"outs:
- md5: ${FILE_MD5}
  size: ${FILE_SIZE}
  hash: md5
  path: ${FILE_NAME}
")
endfunction()

file(MAKE_DIRECTORY "${PAYLOAD_ROOT}" "${_channel_manifest_root}")

file(GLOB_RECURSE _source_entries RELATIVE "${SOURCE_ROOT}" LIST_DIRECTORIES false "${SOURCE_ROOT}/*")
list(SORT _source_entries)

set(_expected_payloads)
set(_expected_manifests)

foreach(_relative_path IN LISTS _source_entries)
    set(_source_path "${SOURCE_ROOT}/${_relative_path}")
    if(IS_DIRECTORY "${_source_path}")
        continue()
    endif()

    nam_get_flat_release_asset_name(_flat_asset_name "${_relative_path}")
    set(_payload_path "${PAYLOAD_ROOT}/${_flat_asset_name}")
    file(COPY_FILE "${_source_path}" "${_payload_path}" ONLY_IF_DIFFERENT)

    set(_output_manifest "${_channel_manifest_root}/${_relative_path}.dvc")
    file(MD5 "${_source_path}" _file_md5)
    file(SIZE "${_source_path}" _file_size)
    get_filename_component(_file_name "${_source_path}" NAME)
    _nam_write_minimal_dvc_manifest("${_output_manifest}" "${_file_name}" "${_file_md5}" "${_file_size}")

    list(APPEND _expected_payloads "${_payload_path}")
    list(APPEND _expected_manifests "${_output_manifest}")
endforeach()

if(PRUNE)
    file(GLOB _existing_payloads LIST_DIRECTORIES false "${PAYLOAD_ROOT}/*")
    foreach(_existing_payload IN LISTS _existing_payloads)
        list(FIND _expected_payloads "${_existing_payload}" _payload_index)
        if(_payload_index EQUAL -1)
            file(REMOVE "${_existing_payload}")
        endif()
    endforeach()

    file(GLOB_RECURSE _existing_manifests LIST_DIRECTORIES false "${_channel_manifest_root}/*.dvc")
    foreach(_existing_manifest IN LISTS _existing_manifests)
        list(FIND _expected_manifests "${_existing_manifest}" _manifest_index)
        if(_manifest_index EQUAL -1)
            file(REMOVE "${_existing_manifest}")
        endif()
    endforeach()
endif()

if(DEFINED MANIFESTS_ZIP AND NOT "${MANIFESTS_ZIP}" STREQUAL "")
    get_filename_component(_manifests_zip_dir "${MANIFESTS_ZIP}" DIRECTORY)
    file(MAKE_DIRECTORY "${_manifests_zip_dir}")
    if(EXISTS "${MANIFESTS_ZIP}")
        file(REMOVE "${MANIFESTS_ZIP}")
    endif()
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E tar cf "${MANIFESTS_ZIP}" --format=zip "${CHANNEL}"
        WORKING_DIRECTORY "${MANIFEST_ROOT}"
        RESULT_VARIABLE _zip_status
        OUTPUT_VARIABLE _zip_stdout
        ERROR_VARIABLE _zip_stderr
    )
    if(NOT _zip_status EQUAL 0)
        message(FATAL_ERROR "NablaAssetManifestsPrepareRelease: manifest zip creation failed\n${_zip_stdout}\n${_zip_stderr}")
    endif()
endif()

list(LENGTH _expected_payloads _payload_count)
message(STATUS "NablaAssetManifestsPrepareRelease: prepared ${_payload_count} files for channel `${CHANNEL}`")
