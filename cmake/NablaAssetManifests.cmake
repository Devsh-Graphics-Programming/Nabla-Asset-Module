# Consumer module with Nabla-Asset-Manifests defaults.
#
# Maintainer-side source of truth:
# - physical layout under channel roots such as `media/`
# - `.dvc` files produced by `dvc add`
#
# Consumer-side behavior:
# - ExternalData-compatible public API surface
# - no hand-maintained asset catalog

include_guard(GLOBAL)

if (NOT DEFINED NAM_USE_VENDORED_EXTERNALDATA)
    set(
        NAM_USE_VENDORED_EXTERNALDATA
        ON
        CACHE BOOL
        "Use the vendored ExternalData module bundled with NAM instead of the stock host module"
    )
endif()
mark_as_advanced(NAM_USE_VENDORED_EXTERNALDATA)

function(_nam_summary MESSAGE_TEXT)
    message(STATUS "NablaAssetManifests: ${MESSAGE_TEXT}")
endfunction()

macro(_nam_include_externaldata OUT_VAR)
    if (NAM_USE_VENDORED_EXTERNALDATA)
        include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/vendor/ExternalData-NAM.cmake")
        set(_provider "vendored")
    else()
        include(ExternalData)
        set(_provider "stock")
    endif()
    set(${OUT_VAR} "${_provider}")
endmacro()

function(_nam_validate_file_link_mode MODE_VALUE OUT_VAR)
    string(TOLOWER "${MODE_VALUE}" _mode)
    if (
        NOT _mode STREQUAL "copy"
        AND NOT _mode STREQUAL "hardlink"
        AND NOT _mode STREQUAL "symlink"
    )
        message(FATAL_ERROR "NablaAssetManifests: unsupported file link mode `${MODE_VALUE}`")
    endif()
    set(${OUT_VAR} "${_mode}" PARENT_SCOPE)
endfunction()

function(_nam_detect_file_link_mode OUT_VAR)
    set(options)
    set(oneValueArgs SOURCE_ROOT DESTINATION_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (DEFINED NAM_SOURCE_ROOT AND NOT "${NAM_SOURCE_ROOT}" STREQUAL "")
        set(_source_root "${NAM_SOURCE_ROOT}")
    else()
        set(_source_root "${CMAKE_CURRENT_BINARY_DIR}")
    endif()

    if (DEFINED NAM_DESTINATION_ROOT AND NOT "${NAM_DESTINATION_ROOT}" STREQUAL "")
        set(_destination_root "${NAM_DESTINATION_ROOT}")
    else()
        set(_destination_root "${CMAKE_CURRENT_BINARY_DIR}")
    endif()

    file(MAKE_DIRECTORY "${_source_root}" "${_destination_root}")
    string(RANDOM LENGTH 12 ALPHABET "0123456789abcdef" _probe_id)
    set(_src "${_source_root}/.nam_probe_${_probe_id}_src.txt")
    set(_dst "${_destination_root}/.nam_probe_${_probe_id}_dst.txt")
    file(WRITE "${_src}" "probe\n")
    file(REMOVE "${_dst}")

    if (WIN32)
        file(CREATE_LINK "${_src}" "${_dst}" RESULT _result)
        if (NOT _result)
            set(${OUT_VAR} "hardlink" PARENT_SCOPE)
            file(REMOVE "${_dst}" "${_src}")
            return()
        endif()
        file(CREATE_LINK "${_src}" "${_dst}" SYMBOLIC RESULT _result)
        if (NOT _result)
            set(${OUT_VAR} "symlink" PARENT_SCOPE)
            file(REMOVE "${_dst}" "${_src}")
            return()
        endif()
    else()
        file(CREATE_LINK "${_src}" "${_dst}" SYMBOLIC RESULT _result)
        if (NOT _result)
            set(${OUT_VAR} "symlink" PARENT_SCOPE)
            file(REMOVE "${_dst}" "${_src}")
            return()
        endif()
        file(CREATE_LINK "${_src}" "${_dst}" RESULT _result)
        if (NOT _result)
            set(${OUT_VAR} "hardlink" PARENT_SCOPE)
            file(REMOVE "${_dst}" "${_src}")
            return()
        endif()
    endif()

    file(REMOVE "${_dst}" "${_src}")
    set(${OUT_VAR} "copy" PARENT_SCOPE)
endfunction()

function(_nam_resolve_file_link_mode OUT_VAR)
    set(options)
    set(oneValueArgs SOURCE_ROOT DESTINATION_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (DEFINED NAM_INTERNAL_FORCE_FILE_LINK_MODE AND NOT "${NAM_INTERNAL_FORCE_FILE_LINK_MODE}" STREQUAL "")
        _nam_validate_file_link_mode("${NAM_INTERNAL_FORCE_FILE_LINK_MODE}" _forced_mode)
        set(${OUT_VAR} "${_forced_mode}" PARENT_SCOPE)
        return()
    endif()

    _nam_detect_file_link_mode(
        _detected_mode
        SOURCE_ROOT "${NAM_SOURCE_ROOT}"
        DESTINATION_ROOT "${NAM_DESTINATION_ROOT}"
    )
    set(${OUT_VAR} "${_detected_mode}" PARENT_SCOPE)
endfunction()

function(nam_get_repo_root OUT_VAR)
    if (DEFINED CMAKE_CURRENT_FUNCTION_LIST_DIR AND NOT "${CMAKE_CURRENT_FUNCTION_LIST_DIR}" STREQUAL "")
        get_filename_component(_root "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
    else()
        get_filename_component(_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
    endif()
    set(${OUT_VAR} "${_root}" PARENT_SCOPE)
endfunction()

function(nam_get_default_cache_root OUT_VAR)
    if (WIN32)
        if (DEFINED ENV{LOCALAPPDATA} AND NOT "$ENV{LOCALAPPDATA}" STREQUAL "")
            set(_base "$ENV{LOCALAPPDATA}")
        elseif(DEFINED ENV{USERPROFILE} AND NOT "$ENV{USERPROFILE}" STREQUAL "")
            set(_base "$ENV{USERPROFILE}/AppData/Local")
        else()
            nam_get_repo_root(_repo_root)
            set(_base "${_repo_root}/.nam-cache")
        endif()
    elseif(DEFINED ENV{XDG_CACHE_HOME} AND NOT "$ENV{XDG_CACHE_HOME}" STREQUAL "")
        set(_base "$ENV{XDG_CACHE_HOME}")
    elseif(DEFINED ENV{HOME} AND NOT "$ENV{HOME}" STREQUAL "")
        set(_base "$ENV{HOME}/.cache")
    else()
        nam_get_repo_root(_repo_root)
        set(_base "${_repo_root}/.nam-cache")
    endif()

    file(TO_CMAKE_PATH "${_base}/nabla/assets" _cache_root)
    set(${OUT_VAR} "${_cache_root}" PARENT_SCOPE)
endfunction()

function(_nam_resolve_cache_root OUT_VAR)
    set(options)
    set(oneValueArgs CACHE_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (DEFINED NAM_CACHE_ROOT AND NOT "${NAM_CACHE_ROOT}" STREQUAL "")
        file(TO_CMAKE_PATH "${NAM_CACHE_ROOT}" _root)
    else()
        nam_get_default_cache_root(_root)
    endif()
    set(${OUT_VAR} "${_root}" PARENT_SCOPE)
endfunction()

function(_nam_resolve_manifest_root OUT_VAR)
    set(options)
    set(oneValueArgs MANIFEST_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (DEFINED NAM_MANIFEST_ROOT AND NOT "${NAM_MANIFEST_ROOT}" STREQUAL "")
        file(TO_CMAKE_PATH "${NAM_MANIFEST_ROOT}" _root)
    else()
        nam_get_repo_root(_root)
    endif()
    set(${OUT_VAR} "${_root}" PARENT_SCOPE)
endfunction()

function(_nam_get_channel_root OUT_VAR)
    set(options)
    set(oneValueArgs CHANNEL MANIFEST_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_CHANNEL OR "${NAM_CHANNEL}" STREQUAL "")
        set(NAM_CHANNEL "media")
    endif()

    _nam_resolve_manifest_root(_manifest_root MANIFEST_ROOT "${NAM_MANIFEST_ROOT}")
    set(_channel_root "${_manifest_root}/${NAM_CHANNEL}")
    if (NOT EXISTS "${_channel_root}")
        message(FATAL_ERROR "NablaAssetManifests: channel root `${_channel_root}` does not exist")
    endif()
    set(${OUT_VAR} "${_channel_root}" PARENT_SCOPE)
endfunction()

function(nam_get_flat_release_asset_name OUT_VAR RELATIVE_PATH)
    if ("${RELATIVE_PATH}" STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: RELATIVE_PATH is required")
    endif()

    file(TO_CMAKE_PATH "${RELATIVE_PATH}" _relative_path)
    string(HEX "${_relative_path}" _relative_path_hex)
    string(TOLOWER "${_relative_path_hex}" _relative_path_hex)
    get_filename_component(_basename "${_relative_path}" NAME)
    set(${OUT_VAR} "${_relative_path_hex}__${_basename}" PARENT_SCOPE)
endfunction()

function(_nam_compute_release_asset_name OUT_VAR RELATIVE_PATH)
    set(options FLAT_RELEASE_ASSET_NAMES)
    set(oneValueArgs)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if ("${RELATIVE_PATH}" STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: RELATIVE_PATH is required")
    endif()

    file(TO_CMAKE_PATH "${RELATIVE_PATH}" _relative_path)
    if (NAM_FLAT_RELEASE_ASSET_NAMES)
        nam_get_flat_release_asset_name(_release_asset "${_relative_path}")
    else()
        get_filename_component(_release_asset "${_relative_path}" NAME)
    endif()

    set(${OUT_VAR} "${_release_asset}" PARENT_SCOPE)
endfunction()

function(_nam_parse_dvc_file)
    set(options FLAT_RELEASE_ASSET_NAMES)
    set(oneValueArgs DVC_FILE CHANNEL MANIFEST_ROOT OUT_RELATIVE_PATH OUT_RELEASE_ASSET OUT_KEY)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT NAM_DVC_FILE)
        message(FATAL_ERROR "NablaAssetManifests: DVC_FILE is required")
    endif()

    _nam_get_channel_root(_channel_root CHANNEL "${NAM_CHANNEL}" MANIFEST_ROOT "${NAM_MANIFEST_ROOT}")
    file(STRINGS "${NAM_DVC_FILE}" _lines)

    set(_path "")
    set(_md5 "")
    foreach(_line IN LISTS _lines)
        if (_line MATCHES "^[ ]*path:[ ]+(.+)$")
            set(_path "${CMAKE_MATCH_1}")
        elseif(_line MATCHES "^[ ]*[-]?[ ]*md5:[ ]+(.+)$")
            set(_md5 "${CMAKE_MATCH_1}")
        endif()
    endforeach()

    if (_path STREQUAL "" OR _md5 STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: failed to parse `${NAM_DVC_FILE}`")
    endif()

    get_filename_component(_dvc_dir "${NAM_DVC_FILE}" DIRECTORY)
    file(REAL_PATH "${_channel_root}" _channel_root_real)
    file(REAL_PATH "${_dvc_dir}" _dvc_dir_real)
    file(RELATIVE_PATH _relative_dir "${_channel_root_real}" "${_dvc_dir_real}")
    file(TO_CMAKE_PATH "${_relative_dir}" _relative_dir)
    if (_relative_dir STREQUAL ".")
        set(_relative_path "${_path}")
    else()
        set(_relative_path "${_relative_dir}/${_path}")
    endif()
    file(TO_CMAKE_PATH "${_relative_path}" _relative_path)

    if (_md5 MATCHES "\\.dir$")
        set(_relative_path "${_relative_path}.zip")
    endif()
    set(_release_asset_args)
    if (NAM_FLAT_RELEASE_ASSET_NAMES)
        list(APPEND _release_asset_args FLAT_RELEASE_ASSET_NAMES)
    endif()
    _nam_compute_release_asset_name(
        _release_asset
        "${_relative_path}"
        ${_release_asset_args}
    )

    set(${NAM_OUT_RELATIVE_PATH} "${_relative_path}" PARENT_SCOPE)
    set(${NAM_OUT_RELEASE_ASSET} "${_release_asset}" PARENT_SCOPE)
    set(${NAM_OUT_KEY} "${_relative_path}" PARENT_SCOPE)
endfunction()

function(nam_get_channel_asset_keys OUT_VAR)
    set(options)
    set(oneValueArgs CHANNEL MANIFEST_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_CHANNEL OR "${NAM_CHANNEL}" STREQUAL "")
        set(NAM_CHANNEL "media")
    endif()

    _nam_get_channel_root(_channel_root CHANNEL "${NAM_CHANNEL}" MANIFEST_ROOT "${NAM_MANIFEST_ROOT}")
    file(GLOB_RECURSE _dvc_files "${_channel_root}/*.dvc")
    list(SORT _dvc_files)

    set(_keys)
    foreach(_dvc IN LISTS _dvc_files)
        _nam_parse_dvc_file(
            DVC_FILE "${_dvc}"
            CHANNEL "${NAM_CHANNEL}"
            MANIFEST_ROOT "${NAM_MANIFEST_ROOT}"
            OUT_RELATIVE_PATH _relative_path
            OUT_RELEASE_ASSET _release_asset
            OUT_KEY _key
        )
        list(APPEND _keys "${_key}")
    endforeach()
    set(${OUT_VAR} "${_keys}" PARENT_SCOPE)
endfunction()

function(_nam_find_channel_asset)
    set(options FLAT_RELEASE_ASSET_NAMES)
    set(oneValueArgs CHANNEL MANIFEST_ROOT ASSET OUT_RELATIVE_PATH OUT_RELEASE_ASSET OUT_KEY)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_CHANNEL OR "${NAM_CHANNEL}" STREQUAL "")
        set(NAM_CHANNEL "media")
    endif()
    if (NOT NAM_ASSET)
        message(FATAL_ERROR "NablaAssetManifests: ASSET is required")
    endif()

    _nam_get_channel_root(_channel_root CHANNEL "${NAM_CHANNEL}" MANIFEST_ROOT "${NAM_MANIFEST_ROOT}")
    file(GLOB_RECURSE _dvc_files "${_channel_root}/*.dvc")
    list(SORT _dvc_files)

    set(_match_count 0)
    foreach(_dvc IN LISTS _dvc_files)
        set(_parse_args)
        if (NAM_FLAT_RELEASE_ASSET_NAMES)
            list(APPEND _parse_args FLAT_RELEASE_ASSET_NAMES)
        endif()
        _nam_parse_dvc_file(
            DVC_FILE "${_dvc}"
            CHANNEL "${NAM_CHANNEL}"
            MANIFEST_ROOT "${NAM_MANIFEST_ROOT}"
            ${_parse_args}
            OUT_RELATIVE_PATH _relative_path
            OUT_RELEASE_ASSET _release_asset
            OUT_KEY _key
        )
        if (_key STREQUAL "${NAM_ASSET}" OR _release_asset STREQUAL "${NAM_ASSET}")
            math(EXPR _match_count "${_match_count}+1")
            set(_resolved_relative_path "${_relative_path}")
            set(_resolved_release_asset "${_release_asset}")
            set(_resolved_key "${_key}")
        endif()
    endforeach()

    if (_match_count EQUAL 0)
        message(FATAL_ERROR "NablaAssetManifests: unknown asset `${NAM_ASSET}` in channel `${NAM_CHANNEL}`")
    endif()
    if (_match_count GREATER 1)
        message(FATAL_ERROR "NablaAssetManifests: ambiguous asset selector `${NAM_ASSET}` in channel `${NAM_CHANNEL}`")
    endif()

    set(${NAM_OUT_RELATIVE_PATH} "${_resolved_relative_path}" PARENT_SCOPE)
    set(${NAM_OUT_RELEASE_ASSET} "${_resolved_release_asset}" PARENT_SCOPE)
    set(${NAM_OUT_KEY} "${_resolved_key}" PARENT_SCOPE)
endfunction()

function(_nam_get_backend_kind OUT_VAR)
    set(${OUT_VAR} "github_release" PARENT_SCOPE)
endfunction()

function(_nam_release_json_cache_key OUT_VAR REPO TAG)
    string(REPLACE "/" "__" _repo_key "${REPO}")
    set(${OUT_VAR} "NAM_RELEASE_JSON_${_repo_key}_${TAG}" PARENT_SCOPE)
endfunction()

function(_nam_get_github_release_json OUT_JSON_VAR)
    set(options)
    set(oneValueArgs REPO TAG CACHE_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_REPO OR "${NAM_REPO}" STREQUAL "")
        set(NAM_REPO "Devsh-Graphics-Programming/Nabla-Asset-Manifests")
    endif()
    if (NOT DEFINED NAM_TAG OR "${NAM_TAG}" STREQUAL "")
        set(NAM_TAG "media")
    endif()

    _nam_release_json_cache_key(_cache_key "${NAM_REPO}" "${NAM_TAG}")
    get_property(_cached_json GLOBAL PROPERTY "${_cache_key}")
    if (_cached_json)
        set(${OUT_JSON_VAR} "${_cached_json}" PARENT_SCOPE)
        return()
    endif()

    _nam_resolve_cache_root(_cache_root CACHE_ROOT "${NAM_CACHE_ROOT}")
    set(_meta_dir "${_cache_root}/meta/${NAM_REPO}")
    file(MAKE_DIRECTORY "${_meta_dir}")
    set(_json_file "${_meta_dir}/${NAM_TAG}.json")
    if (EXISTS "${_json_file}")
        file(READ "${_json_file}" _cached_file_json)
        if (NOT _cached_file_json STREQUAL "")
            set_property(GLOBAL PROPERTY "${_cache_key}" "${_cached_file_json}")
            set(${OUT_JSON_VAR} "${_cached_file_json}" PARENT_SCOPE)
            return()
        endif()
    endif()

    set(_api_url "https://api.github.com/repos/${NAM_REPO}/releases/tags/${NAM_TAG}")
    set(_download_ok OFF)
    set(_last_status_code "")
    foreach(_attempt RANGE 1 3)
        file(DOWNLOAD "${_api_url}" "${_json_file}" STATUS _status TLS_VERIFY ON)
        list(GET _status 0 _status_code)
        set(_last_status_code "${_status_code}")
        if (_status_code EQUAL 0)
            set(_download_ok ON)
            break()
        endif()
    endforeach()
    if (NOT _download_ok)
        message(FATAL_ERROR "NablaAssetManifests: failed to query release metadata for `${NAM_REPO}` tag `${NAM_TAG}` after 3 attempts, last status `${_last_status_code}`")
    endif()
    file(READ "${_json_file}" _json)
    if (_json STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: release metadata response for `${NAM_REPO}` tag `${NAM_TAG}` is empty")
    endif()

    set_property(GLOBAL PROPERTY "${_cache_key}" "${_json}")
    set(${OUT_JSON_VAR} "${_json}" PARENT_SCOPE)
endfunction()

function(_nam_get_github_release_index_file OUT_VAR)
    set(options)
    set(oneValueArgs REPO TAG CACHE_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_REPO OR "${NAM_REPO}" STREQUAL "")
        set(NAM_REPO "Devsh-Graphics-Programming/Nabla-Asset-Manifests")
    endif()
    if (NOT DEFINED NAM_TAG OR "${NAM_TAG}" STREQUAL "")
        set(NAM_TAG "media")
    endif()

    _nam_resolve_cache_root(_cache_root CACHE_ROOT "${NAM_CACHE_ROOT}")
    set(_index_file "${_cache_root}/meta/${NAM_REPO}/${NAM_TAG}.assets")
    if (EXISTS "${_index_file}")
        set(${OUT_VAR} "${_index_file}" PARENT_SCOPE)
        return()
    endif()

    _nam_get_github_release_json(_json REPO "${NAM_REPO}" TAG "${NAM_TAG}" CACHE_ROOT "${NAM_CACHE_ROOT}")
    get_filename_component(_index_dir "${_index_file}" DIRECTORY)
    file(MAKE_DIRECTORY "${_index_dir}")

    string(JSON _asset_count LENGTH "${_json}" assets)
    if (_asset_count STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: release `${NAM_TAG}` has no assets")
    endif()

    math(EXPR _asset_last "${_asset_count} - 1")
    set(_index_lines "")
    foreach(_index RANGE ${_asset_last})
        string(JSON _name GET "${_json}" assets ${_index} name)
        string(JSON _digest GET "${_json}" assets ${_index} digest)
        string(JSON _url GET "${_json}" assets ${_index} browser_download_url)
        string(REPLACE "sha256:" "" _digest "${_digest}")
        string(TOLOWER "${_digest}" _digest)
        string(APPEND _index_lines "${_digest}|${_name}|${_url}\n")
    endforeach()

    file(WRITE "${_index_file}" "${_index_lines}")
    set(${OUT_VAR} "${_index_file}" PARENT_SCOPE)
endfunction()

function(_nam_resolve_remote_asset OUT_DIGEST_VAR OUT_URL_VAR)
    set(options)
    set(oneValueArgs REPO TAG RELEASE_ASSET CACHE_ROOT)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_REPO OR "${NAM_REPO}" STREQUAL "")
        set(NAM_REPO "Devsh-Graphics-Programming/Nabla-Asset-Manifests")
    endif()
    if (NOT DEFINED NAM_TAG OR "${NAM_TAG}" STREQUAL "")
        set(NAM_TAG "media")
    endif()

    _nam_get_github_release_json(_json REPO "${NAM_REPO}" TAG "${NAM_TAG}" CACHE_ROOT "${NAM_CACHE_ROOT}")
    string(JSON _asset_count LENGTH "${_json}" assets)
    if (_asset_count STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: release `${NAM_TAG}` has no assets")
    endif()

    math(EXPR _asset_last "${_asset_count} - 1")
    foreach(_index RANGE ${_asset_last})
        string(JSON _name GET "${_json}" assets ${_index} name)
        if (_name STREQUAL "${NAM_RELEASE_ASSET}")
            string(JSON _digest GET "${_json}" assets ${_index} digest)
            string(JSON _url GET "${_json}" assets ${_index} browser_download_url)
            string(REPLACE "sha256:" "" _digest "${_digest}")
            string(TOLOWER "${_digest}" _digest)
            set(${OUT_DIGEST_VAR} "${_digest}" PARENT_SCOPE)
            set(${OUT_URL_VAR} "${_url}" PARENT_SCOPE)
            return()
        endif()
    endforeach()

    message(FATAL_ERROR "NablaAssetManifests: release asset `${NAM_RELEASE_ASSET}` not found in `${NAM_REPO}` tag `${NAM_TAG}`")
endfunction()

function(_nam_get_object_store_path OUT_VAR)
    set(options)
    set(oneValueArgs CACHE_ROOT HASH)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_HASH OR "${NAM_HASH}" STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: HASH is required")
    endif()

    _nam_resolve_cache_root(_cache_root CACHE_ROOT "${NAM_CACHE_ROOT}")
    set(${OUT_VAR} "${_cache_root}/objects/SHA256/${NAM_HASH}" PARENT_SCOPE)
endfunction()

function(_nam_materialize_single_file SOURCE_PATH DESTINATION_PATH LINK_MODE)
    get_filename_component(_destination_dir "${DESTINATION_PATH}" DIRECTORY)
    file(MAKE_DIRECTORY "${_destination_dir}")
    if (EXISTS "${DESTINATION_PATH}" OR IS_SYMLINK "${DESTINATION_PATH}")
        file(REMOVE "${DESTINATION_PATH}")
    endif()

    if ("${LINK_MODE}" STREQUAL "" OR LINK_MODE STREQUAL "copy")
        file(COPY_FILE "${SOURCE_PATH}" "${DESTINATION_PATH}" ONLY_IF_DIFFERENT)
    elseif(LINK_MODE STREQUAL "hardlink")
        file(REAL_PATH "${SOURCE_PATH}" _source_for_link)
        file(CREATE_LINK "${_source_for_link}" "${DESTINATION_PATH}" RESULT _result)
        if (_result)
            message(FATAL_ERROR "NablaAssetManifests: failed to create hardlink from `${_source_for_link}` to `${DESTINATION_PATH}`: ${_result}")
        endif()
    elseif(LINK_MODE STREQUAL "symlink")
        file(CREATE_LINK "${SOURCE_PATH}" "${DESTINATION_PATH}" SYMBOLIC RESULT _result)
        if (_result)
            message(FATAL_ERROR "NablaAssetManifests: failed to create symlink from `${SOURCE_PATH}` to `${DESTINATION_PATH}`: ${_result}")
        endif()
    else()
        message(FATAL_ERROR "NablaAssetManifests: unsupported LINK_MODE `${LINK_MODE}`")
    endif()
endfunction()

function(_nam_fetch_object_now OUT_OBJECT_PATH)
    set(options SHOW_PROGRESS)
    set(oneValueArgs CACHE_ROOT HASH URL)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_HASH OR "${NAM_HASH}" STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: HASH is required")
    endif()
    if (NOT DEFINED NAM_URL OR "${NAM_URL}" STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: URL is required")
    endif()

    _nam_get_object_store_path(_object_path CACHE_ROOT "${NAM_CACHE_ROOT}" HASH "${NAM_HASH}")
    if (EXISTS "${_object_path}")
        set(${OUT_OBJECT_PATH} "${_object_path}" PARENT_SCOPE)
        return()
    endif()

    get_filename_component(_object_dir "${_object_path}" DIRECTORY)
    file(MAKE_DIRECTORY "${_object_dir}")

    string(RANDOM LENGTH 12 ALPHABET "0123456789abcdef" _random_suffix)
    set(_tmp_path "${_object_dir}/.nam_tmp_${NAM_HASH}_${_random_suffix}")
    set(_download_args
        "${NAM_URL}"
        "${_tmp_path}"
        STATUS _status
        TLS_VERIFY ON
    )
    if (NAM_SHOW_PROGRESS)
        list(APPEND _download_args SHOW_PROGRESS)
    endif()
    file(DOWNLOAD ${_download_args})
    list(GET _status 0 _status_code)
    if (NOT _status_code EQUAL 0)
        list(GET _status 1 _status_message)
        file(REMOVE "${_tmp_path}")
        message(FATAL_ERROR "NablaAssetManifests: failed to download `${NAM_URL}`: ${_status_message}")
    endif()

    file(SHA256 "${_tmp_path}" _download_hash)
    string(TOLOWER "${_download_hash}" _download_hash)
    if (NOT _download_hash STREQUAL "${NAM_HASH}")
        file(REMOVE "${_tmp_path}")
        message(FATAL_ERROR "NablaAssetManifests: downloaded asset hash mismatch for `${NAM_URL}`. Expected `${NAM_HASH}`, got `${_download_hash}`")
    endif()

    if (EXISTS "${_object_path}")
        file(REMOVE "${_tmp_path}")
    else()
        file(RENAME "${_tmp_path}" "${_object_path}")
    endif()

    set(${OUT_OBJECT_PATH} "${_object_path}" PARENT_SCOPE)
endfunction()

function(nam_materialize_channel_now)
    set(options NO_SYMLINKS VERBOSE FLAT_RELEASE_ASSET_NAMES SHOW_PROGRESS)
    set(oneValueArgs CHANNEL MANIFEST_ROOT REPO TAG CACHE_ROOT DESTINATION_ROOT OUT_CHANNEL_ROOT OUT_ITEM_COUNT)
    set(multiValueArgs ITEMS)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (NOT DEFINED NAM_CHANNEL OR "${NAM_CHANNEL}" STREQUAL "")
        set(NAM_CHANNEL "media")
    endif()
    if (NOT DEFINED NAM_REPO OR "${NAM_REPO}" STREQUAL "")
        set(NAM_REPO "Devsh-Graphics-Programming/Nabla-Asset-Manifests")
    endif()
    if (NOT DEFINED NAM_TAG OR "${NAM_TAG}" STREQUAL "")
        set(NAM_TAG "media")
    endif()
    if (NOT DEFINED NAM_DESTINATION_ROOT OR "${NAM_DESTINATION_ROOT}" STREQUAL "")
        set(NAM_DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}")
    endif()

    _nam_resolve_manifest_root(_manifest_root MANIFEST_ROOT "${NAM_MANIFEST_ROOT}")
    _nam_resolve_cache_root(_cache_root CACHE_ROOT "${NAM_CACHE_ROOT}")

    if (NAM_ITEMS)
        set(_items ${NAM_ITEMS})
    else()
        nam_get_channel_asset_keys(_items CHANNEL "${NAM_CHANNEL}" MANIFEST_ROOT "${_manifest_root}")
    endif()

    list(LENGTH _items _item_count)
    _nam_get_backend_kind(_backend_kind)
    _nam_summary("materialize channel now `${NAM_CHANNEL}`: manifest_root=`${_manifest_root}`, repo=`${NAM_REPO}`, tag=`${NAM_TAG}`, backend=`${_backend_kind}`, cache_root=`${_cache_root}`, total=${_item_count}")

    _nam_resolve_file_link_mode(
        _file_link_mode
        SOURCE_ROOT "${_cache_root}/objects/SHA256"
        DESTINATION_ROOT "${NAM_DESTINATION_ROOT}/${NAM_CHANNEL}"
    )
    if (NAM_NO_SYMLINKS)
        set(_file_link_mode "copy")
    endif()
    _nam_summary("configure-time materialization mode: `${_file_link_mode}`")

    foreach(_asset IN LISTS _items)
        set(_find_args)
        if (NAM_FLAT_RELEASE_ASSET_NAMES)
            list(APPEND _find_args FLAT_RELEASE_ASSET_NAMES)
        endif()
        _nam_find_channel_asset(
            CHANNEL "${NAM_CHANNEL}"
            MANIFEST_ROOT "${_manifest_root}"
            ASSET "${_asset}"
            ${_find_args}
            OUT_RELATIVE_PATH _relative_path
            OUT_RELEASE_ASSET _release_asset
            OUT_KEY _key
        )
        _nam_resolve_remote_asset(
            _sha256
            _url
            REPO "${NAM_REPO}"
            TAG "${NAM_TAG}"
            RELEASE_ASSET "${_release_asset}"
            CACHE_ROOT "${NAM_CACHE_ROOT}"
        )
        set(_fetch_object_args
            CACHE_ROOT "${NAM_CACHE_ROOT}"
            HASH "${_sha256}"
            URL "${_url}"
        )
        if (NAM_SHOW_PROGRESS)
            list(APPEND _fetch_object_args SHOW_PROGRESS)
        endif()
        _nam_fetch_object_now(
            _object_path
            ${_fetch_object_args}
        )
        _nam_materialize_single_file(
            "${_object_path}"
            "${NAM_DESTINATION_ROOT}/${NAM_CHANNEL}/${_relative_path}"
            "${_file_link_mode}"
        )
    endforeach()

    if (NAM_OUT_CHANNEL_ROOT)
        set(${NAM_OUT_CHANNEL_ROOT} "${NAM_DESTINATION_ROOT}/${NAM_CHANNEL}" PARENT_SCOPE)
    endif()
    if (NAM_OUT_ITEM_COUNT)
        set(${NAM_OUT_ITEM_COUNT} "${_item_count}" PARENT_SCOPE)
    endif()
endfunction()

function(nam_add_channel_target)
    set(options NO_SYMLINKS VERBOSE FLAT_RELEASE_ASSET_NAMES)
    set(oneValueArgs TARGET CHANNEL MANIFEST_ROOT REPO TAG CACHE_ROOT DESTINATION_ROOT SHOW_PROGRESS)
    set(multiValueArgs ITEMS)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (NOT DEFINED NAM_TARGET OR "${NAM_TARGET}" STREQUAL "")
        message(FATAL_ERROR "NablaAssetManifests: TARGET is required")
    endif()
    if (NOT DEFINED NAM_CHANNEL OR "${NAM_CHANNEL}" STREQUAL "")
        set(NAM_CHANNEL "media")
    endif()
    if (NOT DEFINED NAM_REPO OR "${NAM_REPO}" STREQUAL "")
        set(NAM_REPO "Devsh-Graphics-Programming/Nabla-Asset-Manifests")
    endif()
    if (NOT DEFINED NAM_TAG OR "${NAM_TAG}" STREQUAL "")
        set(NAM_TAG "media")
    endif()
    if (NOT DEFINED NAM_DESTINATION_ROOT OR "${NAM_DESTINATION_ROOT}" STREQUAL "")
        set(NAM_DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}")
    endif()
    if (NOT DEFINED NAM_SHOW_PROGRESS OR "${NAM_SHOW_PROGRESS}" STREQUAL "")
        set(NAM_SHOW_PROGRESS ON)
    endif()

    _nam_resolve_manifest_root(_manifest_root MANIFEST_ROOT "${NAM_MANIFEST_ROOT}")

    if (NAM_ITEMS)
        set(_items ${NAM_ITEMS})
    else()
        nam_get_channel_asset_keys(_items CHANNEL "${NAM_CHANNEL}" MANIFEST_ROOT "${_manifest_root}")
    endif()

    list(LENGTH _items _item_count)
    _nam_get_backend_kind(_backend_kind)
    _nam_resolve_cache_root(_cache_root CACHE_ROOT "${NAM_CACHE_ROOT}")
    _nam_include_externaldata(_externaldata_provider)
    _nam_summary("configure channel target `${NAM_TARGET}`: channel=`${NAM_CHANNEL}`, manifest_root=`${_manifest_root}`, repo=`${NAM_REPO}`, tag=`${NAM_TAG}`, backend=`${_backend_kind}`, externaldata=`${_externaldata_provider}`, cache_root=`${_cache_root}`, total=${_item_count}")

    _nam_get_github_release_index_file(_index_file REPO "${NAM_REPO}" TAG "${NAM_TAG}" CACHE_ROOT "${NAM_CACHE_ROOT}")

    set(_build_root "${CMAKE_CURRENT_BINARY_DIR}/.nam/${NAM_TARGET}")
    set(_fetch_script "${_build_root}/NablaAssetManifestsExternalDataFetch.cmake")
    file(MAKE_DIRECTORY "${_build_root}")
    file(WRITE "${_fetch_script}" "set(CMAKE_MESSAGE_LOG_LEVEL NOTICE)\nset(NAM_RELEASE_INDEX_FILE [=[${_index_file}]=])\ninclude([=[${CMAKE_CURRENT_FUNCTION_LIST_DIR}/NablaAssetManifestsExternalDataFetch.cmake]=])\n")

    set(ExternalData_OBJECT_STORES "${_cache_root}/objects")
    set(ExternalData_URL_TEMPLATES "ExternalDataCustomScript://NAM/%(hash)")
    set(ExternalData_CUSTOM_SCRIPT_NAM "${_fetch_script}")
    add_custom_target("${NAM_TARGET}")
    set(_refs_root "${_build_root}/refs")
    set(_externaldata_binary_root "${_build_root}/assets")
    if (_externaldata_provider STREQUAL "vendored")
        set(_materialization_source_root "${_cache_root}/objects/SHA256")
    else()
        set(_materialization_source_root "${_externaldata_binary_root}")
    endif()
    _nam_resolve_file_link_mode(
        _file_link_mode
        SOURCE_ROOT "${_materialization_source_root}"
        DESTINATION_ROOT "${NAM_DESTINATION_ROOT}/${NAM_CHANNEL}"
    )
    if (NAM_NO_SYMLINKS)
        set(_file_link_mode "copy")
    endif()
    _nam_summary("materialization mode for file assets: `${_file_link_mode}`")

    set(_asset_refs)
    set(_asset_relpaths)
    foreach(_asset IN LISTS _items)
        set(_find_args)
        if (NAM_FLAT_RELEASE_ASSET_NAMES)
            list(APPEND _find_args FLAT_RELEASE_ASSET_NAMES)
        endif()
        _nam_find_channel_asset(
            CHANNEL "${NAM_CHANNEL}"
            MANIFEST_ROOT "${_manifest_root}"
            ASSET "${_asset}"
            ${_find_args}
            OUT_RELATIVE_PATH _relative_path
            OUT_RELEASE_ASSET _release_asset
            OUT_KEY _key
        )
        _nam_resolve_remote_asset(
            _sha256
            _url
            REPO "${NAM_REPO}"
            TAG "${NAM_TAG}"
            RELEASE_ASSET "${_release_asset}"
            CACHE_ROOT "${NAM_CACHE_ROOT}"
        )

        set(_data_name "${NAM_CHANNEL}/${_relative_path}")
        set(_data_ref "${_refs_root}/${_data_name}")
        get_filename_component(_link_dir "${_data_ref}" DIRECTORY)
        file(MAKE_DIRECTORY "${_link_dir}")
        file(WRITE "${_data_ref}.sha256" "${_sha256}\n")
        list(APPEND _asset_refs "DATA{${_data_ref}}")
        list(APPEND _asset_relpaths "${_relative_path}")
    endforeach()

    if (_asset_refs)
        set(_asset_target "${NAM_TARGET}__externaldata")
        set(ExternalData_SOURCE_ROOT "${_refs_root}")
        if (_externaldata_provider STREQUAL "vendored")
            set(ExternalData_BINARY_ROOT "${NAM_DESTINATION_ROOT}")
            set(ExternalData_STATE_ROOT "${_build_root}/state")
            set(ExternalData_LINK_MODE "${_file_link_mode}")
        else()
            set(ExternalData_BINARY_ROOT "${_externaldata_binary_root}")
            unset(ExternalData_STATE_ROOT)
            unset(ExternalData_LINK_MODE)
        endif()
        unset(ExternalData_NO_SYMLINKS)
        set(_old_suppress_dev "${CMAKE_SUPPRESS_DEVELOPER_WARNINGS}")
        set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS 1)
        ExternalData_Expand_Arguments("${_asset_target}" _asset_expanded ${_asset_refs})
        set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS "${_old_suppress_dev}")
        ExternalData_Add_Target("${_asset_target}" SHOW_PROGRESS "${NAM_SHOW_PROGRESS}")
        set(_externaldata_config "${CMAKE_CURRENT_BINARY_DIR}/${_asset_target}_config.cmake")
        if (EXISTS "${_externaldata_config}")
            if (NAM_VERBOSE)
                set(_externaldata_log_level "STATUS")
            else()
                set(_externaldata_log_level "NOTICE")
            endif()
            file(READ "${_externaldata_config}" _externaldata_config_contents)
            file(WRITE "${_externaldata_config}" "set(CMAKE_MESSAGE_LOG_LEVEL ${_externaldata_log_level})\n${_externaldata_config_contents}")
        endif()
        add_dependencies("${NAM_TARGET}" "${_asset_target}")

        if (NOT _externaldata_provider STREQUAL "vendored")
            list(LENGTH _asset_expanded _asset_expanded_count)
            math(EXPR _asset_last "${_asset_expanded_count} - 1")
            foreach(_index RANGE ${_asset_last})
                list(GET _asset_expanded ${_index} _expanded_path)
                set(_stamp "${_build_root}/file_stamps/${_index}.stamp")
                get_filename_component(_stamp_dir "${_stamp}" DIRECTORY)
                file(MAKE_DIRECTORY "${_stamp_dir}")
                list(GET _asset_relpaths ${_index} _relative_path)
                set(_target_path "${NAM_DESTINATION_ROOT}/${NAM_CHANNEL}/${_relative_path}")
                add_custom_command(
                    OUTPUT "${_stamp}"
                    COMMAND "${CMAKE_COMMAND}" -DINPUT=${_expanded_path} -DDESTINATION=${_target_path} -DLINK_MODE=${_file_link_mode} -P "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/NablaAssetManifestsMaterialize.cmake"
                    COMMAND "${CMAKE_COMMAND}" -E touch "${_stamp}"
                    DEPENDS "${_expanded_path}"
                    VERBATIM
                )
                list(APPEND _materialize_stamps "${_stamp}")
            endforeach()
        endif()
    endif()

    if (_materialize_stamps)
        add_custom_target("${NAM_TARGET}__materialize" DEPENDS ${_materialize_stamps})
        add_dependencies("${NAM_TARGET}" "${NAM_TARGET}__materialize")
    endif()

    _nam_summary("channel target `${NAM_TARGET}` ready: total=${_item_count}, destination=`${NAM_DESTINATION_ROOT}`")
endfunction()
