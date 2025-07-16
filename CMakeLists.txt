cmake_minimum_required(VERSION 3.16)
project(ndi-bridge VERSION 1.3.4 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Options
option(BUILD_TESTS "Build unit tests" OFF)
option(USE_DECKLINK "Build with DeckLink support" ON)
option(VERBOSE_BUILD "Enable verbose build output" OFF)
option(ENABLE_AVX2 "Enable AVX2 optimizations for Intel N100" ON)

# Platform detection
if(WIN32)
    set(PLATFORM_WINDOWS TRUE)
    add_definitions(-DPLATFORM_WINDOWS)
    add_definitions(-D_WIN32_WINNT=0x0601)  # Windows 7 minimum
elseif(UNIX AND NOT APPLE)
    set(PLATFORM_LINUX TRUE)
    add_definitions(-DPLATFORM_LINUX)
else()
    message(FATAL_ERROR "Unsupported platform")
endif()

# Set build type if not specified
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Linux-specific checks
if(PLATFORM_LINUX)
    # Check for V4L2 headers
    include(CheckIncludeFile)
    check_include_file("linux/videodev2.h" HAVE_V4L2_H)
    if(NOT HAVE_V4L2_H)
        message(FATAL_ERROR "V4L2 headers not found. Please install kernel headers.")
    endif()
    
    # Check CPU features for AVX2
    if(ENABLE_AVX2)
        include(CheckCXXCompilerFlag)
        check_cxx_compiler_flag("-mavx2" COMPILER_SUPPORTS_AVX2)
        if(COMPILER_SUPPORTS_AVX2)
            set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx2")
            add_definitions(-D__AVX2__)
            message(STATUS "AVX2 optimizations enabled for Intel N100")
        else()
            message(STATUS "AVX2 not supported by compiler")
        endif()
    endif()
    
    # Check for Intel CPU to apply Intel-specific optimizations
    if(CMAKE_BUILD_TYPE STREQUAL "Release" AND CMAKE_SYSTEM_PROCESSOR MATCHES "(x86_64|i686|i386)")
        # Try to detect if we're on an Intel CPU
        execute_process(
            COMMAND cat /proc/cpuinfo
            COMMAND grep -m 1 "vendor_id"
            OUTPUT_VARIABLE CPU_VENDOR
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        
        if(CPU_VENDOR MATCHES "GenuineIntel")
            message(STATUS "Intel CPU detected - enabling Intel-specific optimizations")
            # Check if it's specifically an Alder Lake CPU (like N100)
            execute_process(
                COMMAND cat /proc/cpuinfo
                COMMAND grep -m 1 "model name"
                OUTPUT_VARIABLE CPU_MODEL
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            
            if(CPU_MODEL MATCHES "(N100|N95|N200|Alder Lake)")
                message(STATUS "Intel Alder Lake detected - using specific tuning")
                add_compile_options(-mtune=alderlake)
            else()
                message(STATUS "Generic Intel CPU - using native tuning")
                add_compile_options(-mtune=native)
            endif()
        else()
            message(STATUS "Non-Intel CPU detected - using generic optimizations")
        endif()
    endif()
endif()

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Common source files
set(COMMON_SOURCES
    src/common/version.h
    src/common/capture_interface.h
    src/common/ndi_sender.h
    src/common/ndi_sender.cpp
    src/common/app_controller.h
    src/common/app_controller.cpp
    src/common/logger.h
    src/common/logger.cpp
    src/capture/ICaptureDevice.h
    src/capture/IFormatConverter.h
    src/capture/FormatConverterFactory.h
    src/capture/BasicFormatConverter.cpp
)

# Platform-specific sources
if(PLATFORM_WINDOWS)
    set(PLATFORM_SOURCES
        src/windows/media_foundation/mf_error_handling.h
        src/windows/media_foundation/mf_error_handling.cpp
        src/windows/media_foundation/mf_format_converter.h
        src/windows/media_foundation/mf_format_converter.cpp
        src/windows/media_foundation/mf_capture_device.h
        src/windows/media_foundation/mf_capture_device.cpp
        src/windows/media_foundation/mf_video_capture.h
        src/windows/media_foundation/mf_video_capture.cpp
        src/windows/media_foundation/media_foundation_capture.h
        src/windows/media_foundation/media_foundation_capture.cpp
    )
    
    # DeckLink sources (Windows)
    if(USE_DECKLINK)
        list(APPEND PLATFORM_SOURCES
            # DeckLink main classes
            src/capture/DeckLinkCaptureDevice.h
            src/capture/DeckLinkCaptureDevice.cpp
            src/capture/DeckLinkDeviceEnumerator.h
            src/capture/DeckLinkDeviceEnumerator.cpp
            # Refactored components (v1.2.0)
            include/capture/DeckLinkCaptureCallback.h
            src/capture/DeckLinkCaptureCallback.cpp
            include/capture/DeckLinkFrameQueue.h
            src/capture/DeckLinkFrameQueue.cpp
            include/capture/DeckLinkStatistics.h
            src/capture/DeckLinkStatistics.cpp
            include/capture/DeckLinkFormatManager.h
            src/capture/DeckLinkFormatManager.cpp
            include/capture/DeckLinkDeviceInitializer.h
            src/capture/DeckLinkDeviceInitializer.cpp
            # Adapter
            src/windows/decklink/decklink_capture.h
            src/windows/decklink/decklink_capture.cpp
        )
    endif()
    
    # Windows compiler flags
    add_compile_options(/W4)  # Warning level 4
    if(MSVC)
        add_compile_options(/MP)  # Multi-processor compilation
        add_compile_options(/permissive-)  # Standards conformance
        
        # Disable specific warnings
        add_compile_options(/wd4100)  # Unreferenced formal parameter
        add_compile_options(/wd4189)  # Local variable initialized but not referenced
    endif()
elseif(PLATFORM_LINUX)
    set(PLATFORM_SOURCES
        # V4L2 capture support
        src/linux/v4l2/v4l2_capture.h
        src/linux/v4l2/v4l2_capture.cpp
        src/linux/v4l2/v4l2_device_enumerator.h
        src/linux/v4l2/v4l2_device_enumerator.cpp
        src/linux/v4l2/v4l2_format_converter.h
        src/linux/v4l2/v4l2_format_converter.cpp
    )
    
    # Add AVX2 optimized sources if enabled
    if(ENABLE_AVX2 AND COMPILER_SUPPORTS_AVX2)
        list(APPEND PLATFORM_SOURCES
            src/linux/v4l2/v4l2_format_converter_avx2.h
            src/linux/v4l2/v4l2_format_converter_avx2.cpp
        )
    endif()
    
    # Linux compiler flags
    add_compile_options(-Wall -Wextra -Wpedantic)
    add_compile_options(-Wno-unused-parameter)
    
    # Optimization flags
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        add_compile_options(-O3)           # Maximum optimization
        add_compile_options(-march=native) # Use native CPU features
        add_compile_options(-ffast-math)  # Fast math operations
    endif()
endif()

# Find NDI SDK
if(WIN32)
    # Try multiple possible NDI SDK locations on Windows
    # Note: NDI 6 SDK uses capitalized directory names (Include, Lib, Bin)
    find_path(NDI_INCLUDE_DIR
        NAMES Processing.NDI.Lib.h
        PATHS
            ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/include
            $ENV{NDI_SDK_DIR}/Include
            "C:/Program Files/NDI/NDI 5 SDK/include"
            "C:/Program Files/NDI/NDI 6 SDK/Include"
            "C:/Program Files/NewTek/NDI SDK/include"
    )

    find_library(NDI_LIBRARY
        NAMES Processing.NDI.Lib.x64
        PATHS
            ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/lib/x64
            $ENV{NDI_SDK_DIR}/Lib/x64
            "C:/Program Files/NDI/NDI 5 SDK/lib/x64"
            "C:/Program Files/NDI/NDI 6 SDK/Lib/x64"
            "C:/Program Files/NewTek/NDI SDK/lib/x64"
    )
    
    # Find the DLL path - NDI 6 SDK stores DLLs in Bin directory
    find_file(NDI_DLL
        NAMES Processing.NDI.Lib.x64.dll
        PATHS
            ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/bin/x64
            $ENV{NDI_SDK_DIR}/Bin/x64
            "C:/Program Files/NDI/NDI 5 SDK/Bin/x64"
            "C:/Program Files/NDI/NDI 6 SDK/Bin/x64"
            "C:/Program Files/NewTek/NDI SDK/bin/x64"
    )
else()
    # Linux NDI SDK paths
    find_path(NDI_INCLUDE_DIR
        NAMES Processing.NDI.Lib.h
        PATHS
            ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/include
            $ENV{NDI_SDK_DIR}/include
            /usr/include
            /usr/local/include
    )

    find_library(NDI_LIBRARY
        NAMES ndi
        PATHS
            ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/lib/x86_64-linux-gnu
            $ENV{NDI_SDK_DIR}/lib/x86_64-linux-gnu
            /usr/lib
            /usr/local/lib
    )
endif()

if(NOT NDI_INCLUDE_DIR)
    message(FATAL_ERROR "NDI SDK include directory not found. Please install NDI SDK or set NDI_SDK_DIR environment variable.")
endif()

if(NOT NDI_LIBRARY)
    message(FATAL_ERROR "NDI SDK library not found. Please install NDI SDK or set NDI_SDK_DIR environment variable.")
endif()

if(WIN32 AND NOT NDI_DLL)
    message(FATAL_ERROR "NDI SDK DLL not found. Please install NDI SDK or set NDI_SDK_DIR environment variable.")
endif()

message(STATUS "NDI SDK found:")
message(STATUS "  Include: ${NDI_INCLUDE_DIR}")
message(STATUS "  Library: ${NDI_LIBRARY}")
if(WIN32)
    message(STATUS "  DLL: ${NDI_DLL}")
endif()

# Add NDI include directory
include_directories(${NDI_INCLUDE_DIR})

# Find DeckLink SDK (optional)
if(USE_DECKLINK AND WIN32)
    find_path(DECKLINK_INCLUDE_DIR
        NAMES DeckLinkAPI.h DeckLinkAPI_h.h
        PATHS
            ${CMAKE_CURRENT_SOURCE_DIR}/deps/decklink/include
            $ENV{DECKLINK_SDK_DIR}/include
            "C:/Program Files/Blackmagic Design/DeckLink SDK/Win/include"
            ${CMAKE_CURRENT_SOURCE_DIR}/docs/reference  # For DeckLinkAPI_h.h and DeckLinkAPI_i.c
    )
    
    if(DECKLINK_INCLUDE_DIR)
        message(STATUS "DeckLink SDK found: ${DECKLINK_INCLUDE_DIR}")
        include_directories(${DECKLINK_INCLUDE_DIR})
        add_definitions(-DHAS_DECKLINK)
    else()
        message(WARNING "DeckLink SDK not found. DeckLink support will be disabled.")
        message(WARNING "To enable DeckLink support, copy DeckLinkAPI_h.h and DeckLinkAPI_i.c to docs/reference/")
        set(USE_DECKLINK OFF)
    endif()
endif()

# Main executable
add_executable(${PROJECT_NAME}
    src/main.cpp
    ${COMMON_SOURCES}
    ${PLATFORM_SOURCES}
)

# Set executable properties
set_target_properties(${PROJECT_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Link libraries
target_link_libraries(${PROJECT_NAME} PRIVATE ${NDI_LIBRARY})

if(PLATFORM_WINDOWS)
    # Windows Media Foundation and system libraries
    target_link_libraries(${PROJECT_NAME} PRIVATE
        mfplat
        mfreadwrite
        mfuuid
        mf
        ole32
        shlwapi
        winmm
        ws2_32
    )
    
    # Copy NDI runtime DLL to output directory
    if(NDI_DLL)
        add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${NDI_DLL}"
            $<TARGET_FILE_DIR:${PROJECT_NAME}>
        )
    endif()
elseif(PLATFORM_LINUX)
    # Linux system libraries
    target_link_libraries(${PROJECT_NAME} PRIVATE
        pthread
        dl
        # V4L2 is part of the kernel, no specific library needed
    )
endif()

# Installation rules
install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
)

# Install NDI runtime on Windows
if(PLATFORM_WINDOWS AND NDI_DLL)
    install(FILES "${NDI_DLL}"
        DESTINATION bin
    )
endif()

# Tests
if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# Print configuration summary
message(STATUS "")
message(STATUS "NDI Bridge Configuration:")
message(STATUS "  Version: ${PROJECT_VERSION}")
message(STATUS "  Platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "  Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "  Build tests: ${BUILD_TESTS}")
if(PLATFORM_WINDOWS)
    message(STATUS "  DeckLink support: ${USE_DECKLINK}")
    message(STATUS "  MSVC Version: ${MSVC_VERSION}")
elseif(PLATFORM_LINUX)
    message(STATUS "  V4L2 support: Enabled")
    if(ENABLE_AVX2 AND COMPILER_SUPPORTS_AVX2)
        message(STATUS "  AVX2 optimizations: Enabled (Intel N100)")
    else()
        message(STATUS "  AVX2 optimizations: Disabled")
    endif()
endif()
message(STATUS "")
