if (NOT DEFINED NAM_RELEASE_INDEX_FILE OR "${NAM_RELEASE_INDEX_FILE}" STREQUAL "")
    set(ExternalData_CUSTOM_ERROR "NAM_RELEASE_INDEX_FILE is not set")
    return()
endif()

if (NOT EXISTS "${NAM_RELEASE_INDEX_FILE}")
    set(ExternalData_CUSTOM_ERROR "NAM_RELEASE_INDEX_FILE does not exist: ${NAM_RELEASE_INDEX_FILE}")
    return()
endif()

file(STRINGS "${NAM_RELEASE_INDEX_FILE}" _nam_release_index_lines)

set(_nam_match "")
foreach(_nam_line IN LISTS _nam_release_index_lines)
    if (_nam_line MATCHES "^([^|]+)\\|([^|]+)\\|(.*)$")
        set(_nam_hash "${CMAKE_MATCH_1}")
        set(_nam_name "${CMAKE_MATCH_2}")
        set(_nam_url "${CMAKE_MATCH_3}")
        if (_nam_hash STREQUAL "${ExternalData_CUSTOM_LOCATION}")
            set(_nam_match "${_nam_url}")
            break()
        endif()
    endif()
endforeach()

if (_nam_match STREQUAL "")
    set(ExternalData_CUSTOM_ERROR "No release asset URL found for hash ${ExternalData_CUSTOM_LOCATION}")
    return()
endif()

set(_nam_download_args
    "${_nam_match}"
    "${ExternalData_CUSTOM_FILE}"
    STATUS _nam_status
    SHOW_PROGRESS
)
file(DOWNLOAD ${_nam_download_args})
list(GET _nam_status 0 _nam_status_code)
if (NOT _nam_status_code EQUAL 0)
    list(GET _nam_status 1 _nam_status_message)
    set(ExternalData_CUSTOM_ERROR "Failed to download ${_nam_match}: ${_nam_status_message}")
endif()
