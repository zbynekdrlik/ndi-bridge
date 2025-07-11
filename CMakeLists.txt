cmake_minimum_required(VERSION 3.16)
project(ndi-bridge VERSION 1.0.1 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Options
option(BUILD_TESTS "Build unit tests" OFF)
option(USE_DECKLINK "Build with DeckLink support" ON)
option(VERBOSE_BUILD "Enable verbose build output" OFF)

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
        # Linux-specific sources will be added here
    )
    
    # Linux compiler flags
    add_compile_options(-Wall -Wextra -Wpedantic)
    add_compile_options(-Wno-unused-parameter)
endif()

# Find NDI SDK
if(WIN32)
    # Try multiple possible NDI SDK locations on Windows
    find_path(NDI_INCLUDE_DIR
        NAMES Processing.NDI.Lib.h
        PATHS
            ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/include
            $ENV{NDI_SDK_DIR}/include
            "C:/Program Files/NDI/NDI 5 SDK/include"
            "C:/Program Files/NDI/NDI 6 SDK/include"
            "C:/Program Files/NewTek/NDI SDK/include"
    )

    find_library(NDI_LIBRARY
        NAMES Processing.NDI.Lib.x64
        PATHS
            ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/lib/x64
            $ENV{NDI_SDK_DIR}/lib/x64
            "C:/Program Files/NDI/NDI 5 SDK/lib/x64"
            "C:/Program Files/NDI/NDI 6 SDK/lib/x64"
            "C:/Program Files/NewTek/NDI SDK/lib/x64"
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

message(STATUS "NDI SDK found:")
message(STATUS "  Include: ${NDI_INCLUDE_DIR}")
message(STATUS "  Library: ${NDI_LIBRARY}")

# Add NDI include directory
include_directories(${NDI_INCLUDE_DIR})

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
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${NDI_LIBRARY}/../Processing.NDI.Lib.x64.dll"
        $<TARGET_FILE_DIR:${PROJECT_NAME}>
    )
elseif(PLATFORM_LINUX)
    # Linux system libraries
    target_link_libraries(${PROJECT_NAME} PRIVATE
        pthread
        dl
        # v4l2  # TODO: Uncomment when Linux implementation is ready
    )
endif()

# Installation rules
install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
)

# Install NDI runtime on Windows
if(PLATFORM_WINDOWS)
    install(FILES "${NDI_LIBRARY}/../Processing.NDI.Lib.x64.dll"
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
    message(STATUS "  MSVC Version: ${MSVC_VERSION}")
endif()
message(STATUS "")
