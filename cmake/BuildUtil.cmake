include (CheckFunctionExists)
include (CheckIncludeFile)
include (CheckLibraryExists)
include (CheckSymbolExists)
include (CMakeParseArguments)
include (ExternalProject)

function (dispatch_check_decls)
    cmake_parse_arguments(args "REQUIRED" "" "INCLUDES" ${ARGN})

    foreach (decl IN LISTS args_UNPARSED_ARGUMENTS)
        string (REGEX REPLACE "[^a-zA-Z0-9_]" "_" var "${decl}")
        string(TOUPPER "${var}" var)
        set(var "HAVE_DECL_${var}")
        check_symbol_exists("${decl}" "${args_INCLUDES}" "${var}")

        if (args_REQUIRED AND NOT ${var})
            unset("${var}" CACHE)
            message(FATAL_ERROR "Could not find symbol ${decl}")
        endif ()
    endforeach ()
endfunction ()


function (dispatch_check_funcs)
    cmake_parse_arguments(args "REQUIRED" "" "" ${ARGN})

    foreach (function IN LISTS args_UNPARSED_ARGUMENTS)
        string (REGEX REPLACE "[^a-zA-Z0-9_]" "_" var "${function}")
        string(TOUPPER "${var}" var)
        set(var "HAVE_${var}")
        check_function_exists("${function}" "${var}")

        if (args_REQUIRED AND NOT ${var})
            unset("${var}" CACHE)
            message(FATAL_ERROR "Could not find function ${function}")
        endif ()
    endforeach ()
endfunction ()


function (dispatch_check_headers)
    cmake_parse_arguments(args "REQUIRED" "" "" ${ARGN})

    foreach (header IN LISTS args_UNPARSED_ARGUMENTS)
        string (REGEX REPLACE "[^a-zA-Z0-9_]" "_" var "${header}")
        string(TOUPPER "${var}" var)
        set(var "HAVE_${var}")
        check_include_file("${header}" "${var}")

        if (args_REQUIRED AND NOT ${var})
            unset("${var}" CACHE)
            message(FATAL_ERROR "Could not find header ${header}")
        endif ()
    endforeach ()
endfunction ()


function (dispatch_search_libs function)
    cmake_parse_arguments(args "REQUIRED" "" "LIBRARIES" ${ARGN})

    set (have_function_variable_name "HAVE_${function}")
    string(TOUPPER "${have_function_variable_name}" have_function_variable_name)

    set (function_libraries_variable_name "${function}_LIBRARIES")
    string(TOUPPER "${function_libraries_variable_name}"
        function_libraries_variable_name)

    if (DEFINED ${have_function_variable_name})
        return ()
    endif ()

    # First, check without linking anything in particular.
    check_function_exists("${function}" "${have_function_variable_name}")
    if (${have_function_variable_name})
        # No extra libs needed
        set (${function_libraries_variable_name} "" CACHE INTERNAL "Libraries for ${function}")
        return ()
    else ()
        unset (${have_function_variable_name} CACHE)
    endif ()

    foreach (lib IN LISTS args_LIBRARIES)
        check_library_exists("${lib}" "${function}" "" "${have_function_variable_name}")
        if (${have_function_variable_name})
            set (${function_libraries_variable_name} "${lib}" CACHE INTERNAL "Libraries for ${function}")
            return ()
        else ()
            unset (${have_function_variable_name} CACHE)
        endif ()
    endforeach ()

    if (args_REQUIRED)
        message(FATAL_ERROR "Could not find ${function} in any of: " ${args_LIBRARIES})
    endif ()

    set (${function_libraries_variable_name} "" CACHE INTERNAL "Libraries for ${function}")
    set (${have_function_variable_name} NO CACHE INTERNAL "Have function ${function}")
endfunction ()


function (dispatch_add_subproject name)
    # Wrapper around ExternalProject_Add/add_library(IMPORTED).
    #
    # Required args: SOURCE_DIR, LIBRARY
    # Optional args: INSTALL_PREFIX, INCLUDE_DIR, LIBRARY_DEBUG, CMAKE_ARGS
    #
    # CMAKE_ARGS are forwarded to the cmake configure invocation for the
    # subproject. Any unrecognised args are forwarded to ExternalProject().
    #
    # If not absolute
    # - SOURCE_DIR is assumed to be relative to the current source dir
    # - INSTALL_PREFIX is assumed to be relative to the current binary dir
    # - INCLUDE_DIR/LIBRARY/LIBRARY_DEBUG are assumed to be relative to
    #   INSTALL_PREFIX
    #
    # This function creates:
    # - An ExternalProject target called <NAME>_subproj
    # - An imported library called <NAME> that references
    #   <LIBRARY>/<LIBRARY_DEBUG>
    #
    # This function sets:
    # - <NAME>_INCLUDE_DIRS and <NAME>_LIBRARIES
    ############################################################################
    cmake_parse_arguments(args
        ""
        "SOURCE_DIR;INSTALL_PREFIX;INCLUDE_DIR;LIBRARY;LIBRARY_DEBUG"
        "CMAKE_ARGS"
        ${ARGN})

    if (NOT args_SOURCE_DIR)
        message(FATAL_ERROR "dispatch_add_subproject: SOURCE_DIR not set")
    elseif (IS_ABSOLUTE args_SOURCE_DIR)
        set(source_dir "${args_SOURCE_DIR}")
    else ()
        set(source_dir "${CMAKE_CURRENT_SOURCE_DIR}/${args_SOURCE_DIR}")
    endif ()

    if (NOT args_INSTALL_PREFIX)
        set(install_prefix "${CMAKE_CURRENT_BINARY_DIR}/${name}_subproj")
    elseif (IS_ABSOLUTE args_INSTALL_PREFIX)
        set(install_prefix "${args_INSTALL_PREFIX}")
    else ()
        set(install_prefix
            "${CMAKE_CURRENT_BINARY_DIR}/${args_INSTALL_PREFIX}")
    endif ()

    if (NOT args_LIBRARY)
        message(FATAL_ERROR "dispatch_add_subproject: LIBRARY not set")
    elseif (IS_ABSOLUTE args_LIBRARY)
        set(library_path "${args_LIBRARY}")
    else ()
        set(library_path "${install_prefix}/${args_LIBRARY}")
    endif ()

    if (NOT args_LIBRARY_DEBUG)
        set(debug_library_path "")
    elseif (IS_ABSOLUTE args_LIBRARY_DEBUG)
        set(debug_library_path "${args_LIBRARY_DEBUG}")
    else ()
        set(debug_library_path "${install_prefix}/${args_LIBRARY_DEBUG}")
    endif ()

    if (NOT args_INCLUDE_DIR)
        set(include_dir "${install_prefix}/include")
    elseif (IS_ABSOLUTE args_INCLUDE_DIR)
        set(include_dir "${args_INCLUDE_DIR}")
    else ()
        set(include_dir "${install_prefix}/${args_INCLUDE_DIR}")
    endif ()

    ############################################################################

    if (NOT CMAKE_GENERATOR MATCHES Ninja OR CMAKE_VERSION VERSION_LESS 3.2)
        set(byproducts_flags "")
    elseif (CMAKE_BUILD_TYPE MATCHES Debug AND debug_library_path)
        set(byproducts_flags BUILD_BYPRODUCTS "${debug_library_path}")
    else ()
        set(byproducts_flags BUILD_BYPRODUCTS "${library_path}")
    endif ()

    ExternalProject_Add("${name}_subproj"
        PREFIX "${install_prefix}"
        SOURCE_DIR "${source_dir}"
        CMAKE_ARGS
            "-DCMAKE_INSTALL_PREFIX=${install_prefix}"
            "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
            "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}"
            "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
            --no-warn-unused-cli
            --warn-uninitialized
            ${args_CMAKE_ARGS}
        ${byproducts_flags}
        ${args_UNPARSED_ARGUMENTS}
    )

    add_library("${name}" UNKNOWN IMPORTED)
    add_dependencies("${name}" "${name}_subproj")
    set_target_properties("${name}" PROPERTIES
        IMPORTED_LOCATION "${library_path}")
    if (debug_library_path)
        set_target_properties("${name}" PROPERTIES
            IMPORTED_LOCATION_DEBUG "${debug_library_path}" )
    endif ()

    string(TOUPPER "${name}" uppercase_name)
    set("${uppercase_name}_INCLUDE_DIRS" "${include_dir}" PARENT_SCOPE)
    set("${uppercase_name}_LIBRARIES" "${name}" PARENT_SCOPE)
endfunction()
