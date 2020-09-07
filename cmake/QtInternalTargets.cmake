
function(qt_internal_set_warnings_are_errors_flags target)
    set(flags "")
    if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
        # Regular clang 3.0+
        if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "3.0.0")
            list(APPEND flags -Werror -Wno-error=\#warnings -Wno-error=deprecated-declarations)
        endif()
        if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
            # Clang will otherwise show error about inline method conflicting with dllimport class attribute in tools
            # (this was tested with Clang 10)
            #    error: 'QString::operator[]' redeclared inline; 'dllimport' attribute ignored [-Werror,-Wignored-attributes]
            list(APPEND flags -Wno-ignored-attributes)
        endif()
    elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")
        # using AppleClang
        # Apple clang 4.0+
        if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "4.0.0" AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS_EQUAL "9.2")
            list(APPEND flags -Werror -Wno-error=\#warnings -Wno-error=deprecated-declarations)
        endif()
    elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
        # using GCC
        list(APPEND flags -Werror -Wno-error=cpp -Wno-error=deprecated-declarations)

        # GCC prints this bogus warning, after it has inlined a lot of code
        # error: assuming signed overflow does not occur when assuming that (X + c) < X is always false
        list(APPEND flags -Wno-error=strict-overflow)

        # GCC 7 includes -Wimplicit-fallthrough in -Wextra, but Qt is not yet free of implicit fallthroughs.
        if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "7.0.0")
            list(APPEND flags -Wno-error=implicit-fallthrough)
        endif()

        if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "9.0.0")
            # GCC 9 introduced these but we are not clean for it.
            list(APPEND flags -Wno-error=deprecated-copy -Wno-error=redundant-move -Wno-error=init-list-lifetime)
            # GCC 9 introduced -Wformat-overflow in -Wall, but it is buggy:
            list(APPEND flags -Wno-error=format-overflow)
        endif()

        # Work-around for bug https://code.google.com/p/android/issues/detail?id=58135
        if (ANDROID)
            list(APPEND flags -Wno-error=literal-suffix)
        endif()
    elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "Intel")
        # Intel CC 13.0 +, on Linux only
        if (LINUX)
            if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "13.0.0")
                # 177: function "entity" was declared but never referenced
                #      (too aggressive; ICC reports even for functions created due to template instantiation)
                # 1224: #warning directive
                # 1478: function "entity" (declared at line N) was declared deprecated
                # 1786: function "entity" (declared at line N of "file") was declared deprecated ("message")
                # 1881: argument must be a constant null pointer value
                #      (NULL in C++ is usually a literal 0)
                list(APPEND flags -Werror -ww177,1224,1478,1786,1881)
            endif()
        endif()
    elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
        # In qmake land, currently warnings as errors are only enabled for
        # MSVC 2012, 2013, 2015.
        # Respectively MSVC_VERRSIONs are: 1700-1799, 1800-1899, 1900-1909.
        if(MSVC_VERSION GREATER_EQUAL 1700 AND MSVC_VERSION LESS_EQUAL 1909)
            list(APPEND flags /WX)
        endif()
    endif()
    set(warnings_are_errors_enabled_genex
        "$<NOT:$<BOOL:$<TARGET_PROPERTY:QT_SKIP_WARNINGS_ARE_ERRORS>>>")

    # Apprently qmake only adds -Werror to CXX and OBJCXX files, not C files. We have to do the
    # same otherwise MinGW builds break when building 3rdparty\md4c\md4c.c (and probably on other
    # platforms too).
    set(cxx_only_genex "$<OR:$<COMPILE_LANGUAGE:CXX>,$<COMPILE_LANGUAGE:OBJCXX>>")
    set(final_condition_genex "$<AND:${warnings_are_errors_enabled_genex},${cxx_only_genex}>")
    set(flags_generator_expression "$<${final_condition_genex}:${flags}>")
    target_compile_options("${target}" INTERFACE "${flags_generator_expression}")
endfunction()

add_library(PlatformCommonInternal INTERFACE)
add_library(Qt::PlatformCommonInternal ALIAS PlatformCommonInternal)

add_library(PlatformModuleInternal INTERFACE)
add_library(Qt::PlatformModuleInternal ALIAS PlatformModuleInternal)
target_link_libraries(PlatformModuleInternal INTERFACE PlatformCommonInternal)

add_library(PlatformPluginInternal INTERFACE)
add_library(Qt::PlatformPluginInternal ALIAS PlatformPluginInternal)
target_link_libraries(PlatformPluginInternal INTERFACE PlatformCommonInternal)

add_library(PlatformAppInternal INTERFACE)
add_library(Qt::PlatformAppInternal ALIAS PlatformAppInternal)
target_link_libraries(PlatformAppInternal INTERFACE PlatformCommonInternal)

add_library(PlatformToolInternal INTERFACE)
add_library(Qt::PlatformToolInternal ALIAS PlatformToolInternal)
target_link_libraries(PlatformToolInternal INTERFACE PlatformAppInternal)

if(WARNINGS_ARE_ERRORS)
    qt_internal_set_warnings_are_errors_flags(PlatformModuleInternal)
    qt_internal_set_warnings_are_errors_flags(PlatformPluginInternal)
    qt_internal_set_warnings_are_errors_flags(PlatformAppInternal)
endif()
if(WIN32)
    # Needed for M_PI define. Same as mkspecs/features/qt_module.prf.
    # It's set for every module being built, but it's not propagated to user apps.
    target_compile_definitions(PlatformModuleInternal INTERFACE _USE_MATH_DEFINES)
endif()
if(FEATURE_largefile AND UNIX)
    target_compile_definitions(PlatformCommonInternal
                               INTERFACE "_LARGEFILE64_SOURCE;_LARGEFILE_SOURCE")
endif()

# We can't use the gold linker on android with the NDK, which is the default
# linker. To build our own target we will use the lld linker.
# TODO: Why not?
# Linking Android libs with lld on Windows sometimes deadlocks. Don't use lld on
# Windows. qmake doesn't use lld to build Android on any host platform.
if (ANDROID AND NOT CMAKE_HOST_WIN32)
    target_link_options(PlatformModuleInternal INTERFACE -fuse-ld=lld)
endif()

target_compile_definitions(PlatformCommonInternal INTERFACE $<$<NOT:$<CONFIG:Debug>>:QT_NO_DEBUG>)

if(MSVC)
    # To mimic mkspecs/common/msvc-desktop.conf add optimization flag for non-debug configs.
    # In qmake, the flag is added to any user project built with qmake. In CMake land, to be on the
    # safe side, only add when building Qt itself.
    target_link_options(PlatformCommonInternal INTERFACE "$<$<NOT:$<CONFIG:Debug>>:/OPT:REF>")
endif()

function(qt_internal_apply_bitcode_flags target)
    # See mkspecs/features/uikit/bitcode.prf
    set(release_flags "-fembed-bitcode")
    set(debug_flags "-fembed-bitcode-marker")

    set(is_release_genex "$<NOT:$<CONFIG:Debug>>")
    set(flags_genex "$<IF:${is_release_genex},${release_flags},${debug_flags}>")
    set(is_enabled_genex "$<NOT:$<BOOL:$<TARGET_PROPERTY:QT_NO_BITCODE>>>")

    set(bitcode_flags "$<${is_enabled_genex}:${flags_genex}>")

    target_link_options("${target}" INTERFACE ${bitcode_flags})
    target_compile_options("${target}" INTERFACE ${bitcode_flags})
endfunction()

# Apple deprecated the entire OpenGL API in favor of Metal, which
# we are aware of, so silence the deprecation warnings in code.
# This does not apply to user-code, which will need to silence
# their own warnings if they use the deprecated APIs explicitly.
if(MACOS)
    target_compile_definitions(PlatformCommonInternal INTERFACE GL_SILENCE_DEPRECATION)
elseif(UIKIT)
    target_compile_definitions(PlatformCommonInternal INTERFACE GLES_SILENCE_DEPRECATION)
endif()

if(UIKIT)
    # Do what mkspecs/features/uikit/default_pre.prf does, aka enable sse2 for
    # simulator_and_device_builds.
    if(FEATURE_simulator_and_device)
        # Setting the definition on PlatformCommonInternal behaves slightly differently from what
        # is done in qmake land. This way the define is not propagated to tests, examples, or
        # user projects built with qmake, but only modules, plugins and tools.
        # TODO: Figure out if this ok or not (sounds ok to me).
        target_compile_definitions(PlatformCommonInternal INTERFACE QT_COMPILER_SUPPORTS_SSE2)
    endif()
    qt_internal_apply_bitcode_flags(PlatformCommonInternal)
endif()

# Taken from mkspecs/common/msvc-version.conf and mkspecs/common/msvc-desktop.conf
if (MSVC)
    if (MSVC_VERSION GREATER_EQUAL 1799)
        target_compile_options(PlatformCommonInternal INTERFACE
            -FS
            -Zc:rvalueCast
            -Zc:inline
    )
    endif()
    if (MSVC_VERSION GREATER_EQUAL 1899)
        target_compile_options(PlatformCommonInternal INTERFACE
            -Zc:strictStrings
            -Zc:throwingNew
        )
    endif()
    if (MSVC_VERSION GREATER_EQUAL 1909)
        target_compile_options(PlatformCommonInternal INTERFACE
            -Zc:referenceBinding
        )
    endif()

    target_compile_options(PlatformCommonInternal INTERFACE -Zc:wchar_t)

    target_link_options(PlatformCommonInternal INTERFACE
        -DYNAMICBASE -NXCOMPAT
        $<$<CONFIG:Release>:-OPT:REF>
        $<$<CONFIG:RelWithDebInfo>:-OPT:REF>
    )
endif()

if (GCC AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "9.2")
    target_compile_options(PlatformCommonInternal INTERFACE $<$<COMPILE_LANGUAGE:CXX>:-Wsuggest-override>)
endif()

if(QT_FEATURE_force_asserts)
    target_compile_definitions(PlatformCommonInternal INTERFACE QT_FORCE_ASSERTS)
endif()

if(DEFINED QT_EXTRA_DEFINES)
    target_compile_definitions(PlatformCommonInternal INTERFACE ${QT_EXTRA_DEFINES})
endif()

if(DEFINED QT_EXTRA_INCLUDEPATHS)
    target_include_directories(PlatformCommonInternal INTERFACE ${QT_EXTRA_INCLUDEPATHS})
endif()

if(DEFINED QT_EXTRA_LIBDIRS)
    target_link_directories(PlatformCommonInternal INTERFACE ${QT_EXTRA_LIBDIRS})
endif()

if(DEFINED QT_EXTRA_FRAMEWORKPATHS AND APPLE)
    list(TRANSFORM QT_EXTRA_FRAMEWORKPATHS PREPEND "-F" OUTPUT_VARIABLE __qt_fw_flags)
    target_compile_options(PlatformCommonInternal INTERFACE ${__qt_fw_flags})
    target_link_options(PlatformCommonInternal INTERFACE ${__qt_fw_flags})
    unset(__qt_fw_flags)
endif()

if(QT_FEATURE_use_gold_linker)
    target_link_options(PlatformCommonInternal INTERFACE "-fuse-ld=gold")
elseif(QT_FEATURE_use_bfd_linker)
    target_link_options(PlatformCommonInternal INTERFACE "-fuse-ld=bfd")
elseif(QT_FEATURE_use_lld_linker)
    target_link_options(PlatformCommonInternal INTERFACE "-fuse-ld=lld")
endif()

if(QT_FEATURE_enable_gdb_index)
    target_link_options(PlatformCommonInternal INTERFACE "-Wl,--gdb-index")
endif()

function(qt_get_implicit_sse2_genex_condition out_var)
    set(is_shared_lib "$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>")
    set(is_static_lib "$<STREQUAL:$<TARGET_PROPERTY:TYPE>,STATIC_LIBRARY>")
    set(is_static_qt_build "$<NOT:$<BOOL:${QT_BUILD_SHARED_LIBS}>>")
    set(is_staitc_lib_during_static_qt_build "$<AND:${is_static_qt_build},${is_static_lib}>")
    set(enable_sse2_condition "$<OR:${is_shared_lib},${is_staitc_lib_during_static_qt_build}>")
    set(${out_var} "${enable_sse2_condition}" PARENT_SCOPE)
endfunction()

function(qt_auto_detect_implicit_sse2)
    # sse2 configuration adjustment in qt_module.prf
    # If the compiler supports SSE2, enable it unconditionally in all of Qt shared libraries
    # (and only the libraries). This is not expected to be a problem because:
    # - on Windows, sharing of libraries is uncommon
    # - on Mac OS X, all x86 CPUs already have SSE2 support (we won't even reach here)
    # - on Linux, the dynamic loader can find the libraries on LIBDIR/sse2/
    # The last guarantee does not apply to executables and plugins, so we can't enable for them.
    set(__implicit_sse2_for_qt_modules_enabled FALSE PARENT_SCOPE)
    if(TEST_subarch_sse2 AND NOT TEST_arch_${TEST_architecture_arch}_subarch_sse2)
        qt_get_implicit_sse2_genex_condition(enable_sse2_condition)
        set(enable_sse2_genex "$<${enable_sse2_condition}:${QT_CFLAGS_SSE2}>")
        target_compile_options(PlatformModuleInternal INTERFACE ${enable_sse2_genex})
        set(__implicit_sse2_for_qt_modules_enabled TRUE PARENT_SCOPE)
    endif()
endfunction()
qt_auto_detect_implicit_sse2()

function(qt_auto_detect_fpmath)
    # fpmath configuration adjustment in qt_module.prf
    set(fpmath_supported FALSE)
    if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
        if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "3.4")
            set(fpmath_supported TRUE)
        endif()
    elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")
        if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "5.1")
            set(fpmath_supported TRUE)
        endif()
    elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
        set(fpmath_supported TRUE)
    endif()
    if(fpmath_supported AND TEST_architecture_arch STREQUAL "i386" AND __implicit_sse2_for_qt_modules_enabled)
        qt_get_implicit_sse2_genex_condition(enable_sse2_condition)
        set(enable_fpmath_genex "$<${enable_sse2_condition}:-mfpmath=sse>")
        target_compile_options(PlatformModuleInternal INTERFACE ${enable_fpmath_genex})
    endif()
endfunction()
qt_auto_detect_fpmath()

function(qt_handle_apple_app_extension_api_only)
    if(APPLE)
        # Build Qt libraries with -fapplication-extension. Needed to avoid linker warnings
        # transformed into errors on darwin platforms.
        set(flags "-fapplication-extension")
        set(genex_condition "$<NOT:$<BOOL:$<TARGET_PROPERTY:QT_NO_APP_EXTENSION_ONLY_API>>>")
        set(flags "$<${genex_condition}:${flags}>")
        target_compile_options(PlatformModuleInternal INTERFACE ${flags})
        target_link_options(PlatformModuleInternal INTERFACE ${flags})
        target_compile_options(PlatformPluginInternal INTERFACE ${flags})
        target_link_options(PlatformPluginInternal INTERFACE ${flags})
    endif()
endfunction()
function(qt_disable_apple_app_extension_api_only target)
    set_target_properties("${target}" PROPERTIES QT_NO_APP_EXTENSION_ONLY_API TRUE)
endfunction()

qt_handle_apple_app_extension_api_only()
