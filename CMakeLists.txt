cmake_minimum_required(VERSION 3.15)
project(ndi-bridge VERSION 1.3.7)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Compiler settings
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Platform detection
if(WIN32)
    add_definitions(-DPLATFORM_WINDOWS)
    set(PLATFORM_NAME "Windows")
elseif(UNIX AND NOT APPLE)
    add_definitions(-DPLATFORM_LINUX)
    set(PLATFORM_NAME "Linux")
    
    # Add compile options for Linux
    add_compile_options(-Wall -Wextra -Wpedantic)
    
    # Enable position independent code
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
    
    # Add threading support
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads REQUIRED)
else()
    message(FATAL_ERROR "Unsupported platform")
endif()

# Output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# NDI SDK
if(NOT DEFINED ENV{NDI_SDK_DIR})
    if(WIN32)
        set(NDI_SDK_DIR "C:/Program Files/NDI/NDI 5 SDK")
    else()
        # Try common Linux locations
        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/NDI SDK for Linux")
            set(NDI_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/NDI SDK for Linux")
        elseif(EXISTS "/usr/local/ndi")
            set(NDI_SDK_DIR "/usr/local/ndi")
        else()
            message(FATAL_ERROR "NDI SDK not found. Please set NDI_SDK_DIR environment variable")
        endif()
    endif()
else()
    set(NDI_SDK_DIR "$ENV{NDI_SDK_DIR}")
endif()

message(STATUS "NDI SDK Directory: ${NDI_SDK_DIR}")

# Verify NDI SDK exists
if(NOT EXISTS "${NDI_SDK_DIR}")
    message(FATAL_ERROR "NDI SDK directory does not exist: ${NDI_SDK_DIR}")
endif()

# Source files
set(COMMON_SOURCES
    src/main.cpp
    src/common/logger.cpp
    src/common/version.cpp
    src/ndi/ndi_sender.cpp
    src/ndi/ndi_receiver.cpp
)

# Platform-specific sources
if(WIN32)
    list(APPEND PLATFORM_SOURCES
        src/windows/capture/media_foundation_capture.cpp
        src/windows/capture/decklink_capture.cpp
        src/windows/capture/decklink_discovery.cpp
    )
elseif(UNIX AND NOT APPLE)
    list(APPEND PLATFORM_SOURCES
        src/linux/v4l2/v4l2_capture.cpp
        src/linux/v4l2/v4l2_device_enumerator.cpp
        src/linux/v4l2/v4l2_format_converter.cpp
        src/linux/v4l2/v4l2_format_converter_avx2.cpp
    )
endif()

# Create executable
add_executable(${PROJECT_NAME} ${COMMON_SOURCES} ${PLATFORM_SOURCES})

# Set version definitions
target_compile_definitions(${PROJECT_NAME} PRIVATE
    NDI_BRIDGE_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
    NDI_BRIDGE_VERSION_MINOR=${PROJECT_VERSION_MINOR}
    NDI_BRIDGE_VERSION_PATCH=${PROJECT_VERSION_PATCH}
    NDI_BRIDGE_VERSION_STRING="${PROJECT_VERSION}"
)

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    "${NDI_SDK_DIR}/include"
)

# Link directories and libraries
if(WIN32)
    # Windows x64
    target_link_directories(${PROJECT_NAME} PRIVATE
        "${NDI_SDK_DIR}/lib/x64"
    )
    
    target_link_libraries(${PROJECT_NAME} PRIVATE
        Processing.NDI.Lib.x64
        mfplat
        mf
        mfreadwrite
        mfuuid
        ole32
        strmiids
    )
    
    # Copy NDI runtime DLL to output directory
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${NDI_SDK_DIR}/bin/x64/Processing.NDI.Lib.x64.dll"
        $<TARGET_FILE_DIR:${PROJECT_NAME}>
    )
elseif(UNIX AND NOT APPLE)
    # Linux
    target_link_directories(${PROJECT_NAME} PRIVATE
        "${NDI_SDK_DIR}/lib/x86_64-linux-gnu"
    )
    
    target_link_libraries(${PROJECT_NAME} PRIVATE
        ndi
        Threads::Threads
        dl
        m
    )
    
    # V4L2 doesn't require additional libraries
    # RPATH for finding NDI library
    set_target_properties(${PROJECT_NAME} PROPERTIES
        INSTALL_RPATH "${NDI_SDK_DIR}/lib/x86_64-linux-gnu"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
    
    # AVX2 support for optimized format conversion
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        set_source_files_properties(
            src/linux/v4l2/v4l2_format_converter_avx2.cpp
            PROPERTIES COMPILE_FLAGS "-mavx2"
        )
    endif()
endif()

# Installation rules
install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

# Print configuration summary
message(STATUS "")
message(STATUS "Configuration Summary:")
message(STATUS "  Platform: ${PLATFORM_NAME}")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "  NDI SDK: ${NDI_SDK_DIR}")
message(STATUS "  Version: ${PROJECT_VERSION}")
message(STATUS "")
