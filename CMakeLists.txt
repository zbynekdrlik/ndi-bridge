cmake_minimum_required(VERSION 3.16)

# Read version from version.h to have single source of truth
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/common/version.h" version_file)
string(REGEX MATCH "VERSION_MAJOR ([0-9]+)" _ ${version_file})
set(VERSION_MAJOR ${CMAKE_MATCH_1})
string(REGEX MATCH "VERSION_MINOR ([0-9]+)" _ ${version_file})
set(VERSION_MINOR ${CMAKE_MATCH_1})
string(REGEX MATCH "VERSION_PATCH ([0-9]+)" _ ${version_file})
set(VERSION_PATCH ${CMAKE_MATCH_1})

project(media-bridge VERSION ${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH} LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Options
option(BUILD_TESTS "Build unit tests" OFF)
option(VERBOSE_BUILD "Enable verbose build output" OFF)

# Platform detection - Linux only
if(UNIX AND NOT APPLE)
    set(PLATFORM_LINUX TRUE)
    add_definitions(-DPLATFORM_LINUX)
else()
    message(FATAL_ERROR "Media Bridge only supports Linux")
endif()

# Set build type if not specified
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
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
    src/common/frame_queue.h
    src/common/frame_queue.cpp
    src/common/pipeline_thread_pool.h
    src/common/pipeline_thread_pool.cpp
    src/capture/ICaptureDevice.h
    src/capture/IFormatConverter.h
    src/capture/FormatConverterFactory.h
    src/capture/BasicFormatConverter.cpp
)

# Linux-specific sources
set(PLATFORM_SOURCES
    src/linux/v4l2/v4l2_capture.cpp
    src/linux/v4l2/v4l2_device_enumerator.cpp
    src/linux/v4l2/v4l2_format_converter.cpp
    src/linux/v4l2/v4l2_format_converter_avx2.cpp
)

# Linux compiler flags
add_compile_options(-Wall -Wextra -Wpedantic)
add_compile_options(-Wno-unused-parameter)

# Enable position independent code
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Add threading support
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)

# Find NDI SDK - Linux only
# Linux NDI SDK paths
    # First check if NDI_SDK_DIR environment variable is set
    if(DEFINED ENV{NDI_SDK_DIR})
        set(NDI_SEARCH_PATHS
            "$ENV{NDI_SDK_DIR}/include"
            "$ENV{NDI_SDK_DIR}"
        )
        set(NDI_LIB_SEARCH_PATHS
            "$ENV{NDI_SDK_DIR}/lib/x86_64-linux-gnu"
            "$ENV{NDI_SDK_DIR}/lib"
        )
    else()
        set(NDI_SEARCH_PATHS
            "${CMAKE_CURRENT_SOURCE_DIR}/NDI SDK for Linux/include"
            "${CMAKE_CURRENT_SOURCE_DIR}/NDI SDK for Linux"
            "/usr/local/ndi/include"
            "/usr/local/ndi"
            "/usr/include"
        )
        set(NDI_LIB_SEARCH_PATHS
            "${CMAKE_CURRENT_SOURCE_DIR}/NDI SDK for Linux/lib/x86_64-linux-gnu"
            "/usr/local/ndi/lib/x86_64-linux-gnu"
            "/usr/local/lib"
            "/usr/lib"
        )
    endif()
    
    find_path(NDI_INCLUDE_DIR
        NAMES Processing.NDI.Lib.h
        PATHS ${NDI_SEARCH_PATHS}
    )

    find_library(NDI_LIBRARY
        NAMES ndi
        PATHS ${NDI_LIB_SEARCH_PATHS}
    )

if(NOT NDI_INCLUDE_DIR)
    message(FATAL_ERROR "NDI SDK include directory not found. Please install NDI SDK or set NDI_SDK_DIR environment variable.")
endif()

if(NOT NDI_LIBRARY)
    message(FATAL_ERROR "NDI SDK library not found. Please install NDI SDK or set NDI_SDK_DIR environment variable.")
endif()

message(STATUS "NDI SDK found:")
message(STATUS "  Include: ${NDI_INCLUDE_DIR}")
message(STATUS "  Library: ${NDI_LIBRARY}")

# Add NDI include directory
include_directories(${NDI_INCLUDE_DIR})

# DeckLink support removed - Linux appliance uses V4L2 only

# Main executable (capture application)
add_executable(ndi-capture
    src/main.cpp
    ${COMMON_SOURCES}
    ${PLATFORM_SOURCES}
)

# Set executable properties
set_target_properties(ndi-capture PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# NDI Display executable (Linux only)
if(PLATFORM_LINUX)
    add_executable(ndi-display
        src/display/main.cpp
        src/display/ndi_receiver.cpp
        src/display/ndi_receiver.h
        src/display/status_reporter.h
        src/display/display_output.h
        src/display/display_output.cpp
        src/display/drm_display_output.cpp
        src/display/audio_output.h
        src/display/alsa_audio_output.h
        src/display/alsa_audio_output.cpp
        src/display/audio_processor.h
        src/display/audio_processor.cpp
        src/common/logger.cpp
        src/common/logger.h
        src/common/version.h
    )
    
    # Set executable properties
    set_target_properties(ndi-display PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    )
    
    # Include directories for ndi-display
    target_include_directories(ndi-display PRIVATE
        ${NDI_INCLUDE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    
    # Include DRM headers
    target_include_directories(ndi-display PRIVATE 
        /usr/include/libdrm
    )
    
    # Link libraries for ndi-display
    # Note: Requires libdrm-dev package on Ubuntu/Debian (apt-get install libdrm-dev)
    target_link_libraries(ndi-display PRIVATE
        ${NDI_LIBRARY}
        pthread
        drm      # For DRM/KMS display output with hardware scaling
        asound   # For ALSA audio output to HDMI
    )
    
    # Set version definitions
    target_compile_definitions(ndi-display PRIVATE
        NDI_BRIDGE_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
        NDI_BRIDGE_VERSION_MINOR=${PROJECT_VERSION_MINOR}
        NDI_BRIDGE_VERSION_PATCH=${PROJECT_VERSION_PATCH}
        NDI_BRIDGE_VERSION_STRING="${PROJECT_VERSION}"
    )
endif()

# Set version definitions
target_compile_definitions(ndi-capture PRIVATE
    NDI_BRIDGE_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
    NDI_BRIDGE_VERSION_MINOR=${PROJECT_VERSION_MINOR}
    NDI_BRIDGE_VERSION_PATCH=${PROJECT_VERSION_PATCH}
    NDI_BRIDGE_VERSION_STRING="${PROJECT_VERSION}"
)

# Set synchronous mode flag if enabled
if(MF_SYNCHRONOUS_MODE)
    target_compile_definitions(ndi-capture PRIVATE MF_SYNCHRONOUS_CAPTURE)
    message(STATUS "Media Foundation synchronous mode: ENABLED (experimental)")
else()
    message(STATUS "Media Foundation synchronous mode: DISABLED")
endif()

# Link libraries
target_link_libraries(ndi-capture PRIVATE ${NDI_LIBRARY})

if(PLATFORM_WINDOWS)
    # Windows Media Foundation and system libraries
    target_link_libraries(ndi-capture PRIVATE
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
        add_custom_command(TARGET ndi-capture POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${NDI_DLL}"
            $<TARGET_FILE_DIR:ndi-capture>
        )
    endif()
elseif(PLATFORM_LINUX)
    # Linux system libraries
    target_link_libraries(ndi-capture PRIVATE
        Threads::Threads
        dl
        m
    )
    
    # V4L2 doesn't require additional libraries
    # RPATH for finding NDI library
    if(NDI_LIBRARY)
        get_filename_component(NDI_LIB_DIR ${NDI_LIBRARY} DIRECTORY)
        set_target_properties(ndi-capture PROPERTIES
            INSTALL_RPATH "${NDI_LIB_DIR}"
            BUILD_WITH_INSTALL_RPATH TRUE
        )
    endif()
    
    # AVX2 support for optimized format conversion
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        set_source_files_properties(
            src/linux/v4l2/v4l2_format_converter_avx2.cpp
            PROPERTIES COMPILE_FLAGS "-mavx2"
        )
        # Also compile NDI sender with AVX2 for YUYV optimization
        set_source_files_properties(
            src/common/ndi_sender.cpp
            PROPERTIES COMPILE_FLAGS "-mavx2"
        )
    endif()
endif()

# Installation rules
install(TARGETS ndi-capture
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
message(STATUS "Media Bridge Configuration:")
message(STATUS "  Version: ${PROJECT_VERSION}")
message(STATUS "  Platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "  Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "  Build tests: ${BUILD_TESTS}")
message(STATUS "  DeckLink support: ${USE_DECKLINK}")
if(PLATFORM_WINDOWS)
    message(STATUS "  MSVC Version: ${MSVC_VERSION}")
endif()
message(STATUS "")
