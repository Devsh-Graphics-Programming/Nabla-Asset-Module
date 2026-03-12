if (NOT DEFINED INPUT OR "${INPUT}" STREQUAL "")
    message(FATAL_ERROR "NablaAssetManifestsExtract: INPUT is required")
endif()

if (NOT DEFINED DESTINATION OR "${DESTINATION}" STREQUAL "")
    message(FATAL_ERROR "NablaAssetManifestsExtract: DESTINATION is required")
endif()

file(ARCHIVE_EXTRACT INPUT "${INPUT}" DESTINATION "${DESTINATION}")
