# Consumer module for the Nabla-Asset-Manifests repository.
#
# Maintainer-side source of truth:
# - physical layout under channel roots such as `media/`
# - `.dvc` files produced by `dvc add`
#
# Consumer-side behavior:
# - pure public `ExternalData` API
# - no hand-maintained asset catalog

include_guard(GLOBAL)

function(_nam_summary MESSAGE_TEXT)
    message(STATUS "NablaAssetManifests: ${MESSAGE_TEXT}")
endfunction()

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
    set(_probe_root "${CMAKE_CURRENT_BINARY_DIR}/.nam_probe")
    file(MAKE_DIRECTORY "${_probe_root}")
    set(_src "${_probe_root}/src.txt")
    set(_dst "${_probe_root}/dst.txt")
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
    if (DEFINED NAM_INTERNAL_FORCE_FILE_LINK_MODE AND NOT "${NAM_INTERNAL_FORCE_FILE_LINK_MODE}" STREQUAL "")
        _nam_validate_file_link_mode("${NAM_INTERNAL_FORCE_FILE_LINK_MODE}" _forced_mode)
        set(${OUT_VAR} "${_forced_mode}" PARENT_SCOPE)
        return()
    endif()

    _nam_detect_file_link_mode(_detected_mode)
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

function(_nam_get_channel_root OUT_VAR)
    set(options)
    set(oneValueArgs CHANNEL)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_CHANNEL OR "${NAM_CHANNEL}" STREQUAL "")
        set(NAM_CHANNEL "media")
    endif()

    nam_get_repo_root(_repo_root)
    set(_channel_root "${_repo_root}/${NAM_CHANNEL}")
    if (NOT EXISTS "${_channel_root}")
        message(FATAL_ERROR "NablaAssetManifests: channel root `${_channel_root}` does not exist")
    endif()
    set(${OUT_VAR} "${_channel_root}" PARENT_SCOPE)
endfunction()

function(_nam_parse_dvc_file)
    set(options)
    set(oneValueArgs DVC_FILE CHANNEL OUT_RELATIVE_PATH OUT_RELEASE_ASSET OUT_KEY)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT NAM_DVC_FILE)
        message(FATAL_ERROR "NablaAssetManifests: DVC_FILE is required")
    endif()

    _nam_get_channel_root(_channel_root CHANNEL "${NAM_CHANNEL}")
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
    get_filename_component(_tracked_abs "${_dvc_dir}/${_path}" ABSOLUTE)
    file(RELATIVE_PATH _relative_path "${_channel_root}" "${_tracked_abs}")
    file(TO_CMAKE_PATH "${_relative_path}" _relative_path)

    if (_md5 MATCHES "\\.dir$")
        get_filename_component(_name "${_tracked_abs}" NAME)
        set(_release_asset "${_name}.zip")
        set(_relative_path "${_relative_path}.zip")
    else()
        get_filename_component(_release_asset "${_tracked_abs}" NAME)
    endif()

    set(${NAM_OUT_RELATIVE_PATH} "${_relative_path}" PARENT_SCOPE)
    set(${NAM_OUT_RELEASE_ASSET} "${_release_asset}" PARENT_SCOPE)
    set(${NAM_OUT_KEY} "${_relative_path}" PARENT_SCOPE)
endfunction()

function(nam_get_channel_asset_keys OUT_VAR)
    set(options)
    set(oneValueArgs CHANNEL)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_CHANNEL OR "${NAM_CHANNEL}" STREQUAL "")
        set(NAM_CHANNEL "media")
    endif()

    _nam_get_channel_root(_channel_root CHANNEL "${NAM_CHANNEL}")
    file(GLOB_RECURSE _dvc_files "${_channel_root}/*.dvc")
    list(SORT _dvc_files)

    set(_keys)
    foreach(_dvc IN LISTS _dvc_files)
        _nam_parse_dvc_file(
            DVC_FILE "${_dvc}"
            CHANNEL "${NAM_CHANNEL}"
            OUT_RELATIVE_PATH _relative_path
            OUT_RELEASE_ASSET _release_asset
            OUT_KEY _key
        )
        list(APPEND _keys "${_key}")
    endforeach()
    set(${OUT_VAR} "${_keys}" PARENT_SCOPE)
endfunction()

function(_nam_find_channel_asset)
    set(options)
    set(oneValueArgs CHANNEL ASSET OUT_RELATIVE_PATH OUT_RELEASE_ASSET OUT_KEY)
    cmake_parse_arguments(NAM "${options}" "${oneValueArgs}" "" ${ARGN})

    if (NOT DEFINED NAM_CHANNEL OR "${NAM_CHANNEL}" STREQUAL "")
        set(NAM_CHANNEL "media")
    endif()
    if (NOT NAM_ASSET)
        message(FATAL_ERROR "NablaAssetManifests: ASSET is required")
    endif()

    _nam_get_channel_root(_channel_root CHANNEL "${NAM_CHANNEL}")
    file(GLOB_RECURSE _dvc_files "${_channel_root}/*.dvc")
    list(SORT _dvc_files)

    set(_match_count 0)
    foreach(_dvc IN LISTS _dvc_files)
        _nam_parse_dvc_file(
            DVC_FILE "${_dvc}"
            CHANNEL "${NAM_CHANNEL}"
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
    set(_api_url "https://api.github.com/repos/${NAM_REPO}/releases/tags/${NAM_TAG}")
    file(DOWNLOAD "${_api_url}" "${_json_file}" STATUS _status)
    list(GET _status 0 _status_code)
    if (NOT _status_code EQUAL 0)
        message(FATAL_ERROR "NablaAssetManifests: failed to query release metadata for `${NAM_REPO}` tag `${NAM_TAG}`")
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

function(nam_add_channel_target)
    set(options NO_SYMLINKS VERBOSE)
    set(oneValueArgs TARGET CHANNEL REPO TAG CACHE_ROOT DESTINATION_ROOT SHOW_PROGRESS)
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

    if (NAM_ITEMS)
        set(_items ${NAM_ITEMS})
    else()
        nam_get_channel_asset_keys(_items CHANNEL "${NAM_CHANNEL}")
    endif()

    list(LENGTH _items _item_count)
    _nam_get_backend_kind(_backend_kind)
    _nam_resolve_cache_root(_cache_root CACHE_ROOT "${NAM_CACHE_ROOT}")
    _nam_summary("configure channel target `${NAM_TARGET}`: channel=`${NAM_CHANNEL}`, repo=`${NAM_REPO}`, tag=`${NAM_TAG}`, backend=`${_backend_kind}`, cache_root=`${_cache_root}`, total=${_item_count}")

    _nam_get_github_release_index_file(_index_file REPO "${NAM_REPO}" TAG "${NAM_TAG}" CACHE_ROOT "${NAM_CACHE_ROOT}")

    set(_build_root "${CMAKE_CURRENT_BINARY_DIR}/.nam/${NAM_TARGET}")
    set(_fetch_script "${_build_root}/NablaAssetManifestsExternalDataFetch.cmake")
    file(MAKE_DIRECTORY "${_build_root}")
    file(WRITE "${_fetch_script}" "set(CMAKE_MESSAGE_LOG_LEVEL NOTICE)\nset(NAM_RELEASE_INDEX_FILE [=[${_index_file}]=])\ninclude([=[${CMAKE_CURRENT_FUNCTION_LIST_DIR}/NablaAssetManifestsExternalDataFetch.cmake]=])\n")

    include(ExternalData)
    set(ExternalData_OBJECT_STORES "${_cache_root}/objects")
    set(ExternalData_URL_TEMPLATES "ExternalDataCustomScript://NAM/%(hash)")
    set(ExternalData_CUSTOM_SCRIPT_NAM "${_fetch_script}")
    add_custom_target("${NAM_TARGET}")
    _nam_resolve_file_link_mode(_file_link_mode)
    if (NAM_NO_SYMLINKS)
        set(_file_link_mode "copy")
    endif()
    _nam_summary("materialization mode for file assets: `${_file_link_mode}`")

    set(_asset_refs)
    set(_asset_relpaths)
    foreach(_asset IN LISTS _items)
        _nam_find_channel_asset(
            CHANNEL "${NAM_CHANNEL}"
            ASSET "${_asset}"
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
        get_filename_component(_link_dir "${CMAKE_CURRENT_SOURCE_DIR}/${_data_name}" DIRECTORY)
        file(MAKE_DIRECTORY "${_link_dir}")
        file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/${_data_name}.sha256" "${_sha256}\n")
        list(APPEND _asset_refs "DATA{${_data_name}}")
        list(APPEND _asset_relpaths "${_relative_path}")
    endforeach()

    if (_asset_refs)
        set(_asset_target "${NAM_TARGET}__externaldata")
        set(ExternalData_SOURCE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")
        set(ExternalData_BINARY_ROOT "${_build_root}/assets")
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

        list(LENGTH _asset_expanded _asset_expanded_count)
        math(EXPR _asset_last "${_asset_expanded_count} - 1")
        foreach(_index RANGE ${_asset_last})
            list(GET _asset_expanded ${_index} _expanded_path)
            list(GET _asset_relpaths ${_index} _relative_path)
            set(_target_path "${NAM_DESTINATION_ROOT}/${NAM_CHANNEL}/${_relative_path}")
            set(_stamp "${_build_root}/file_stamps/${_index}.stamp")
            get_filename_component(_stamp_dir "${_stamp}" DIRECTORY)
            file(MAKE_DIRECTORY "${_stamp_dir}")
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

    if (_materialize_stamps)
        add_custom_target("${NAM_TARGET}__materialize" DEPENDS ${_materialize_stamps})
        add_dependencies("${NAM_TARGET}" "${NAM_TARGET}__materialize")
    endif()

    _nam_summary("channel target `${NAM_TARGET}` ready: total=${_item_count}, destination=`${NAM_DESTINATION_ROOT}`")
endfunction()
