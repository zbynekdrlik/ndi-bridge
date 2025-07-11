cmake_minimum_required(VERSION 3.16)
project(ndi-bridge VERSION 0.1.0 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Options
option(BUILD_TESTS "Build unit tests" OFF)
option(USE_DECKLINK "Build with DeckLink support" ON)

# Platform detection
if(WIN32)
    set(PLATFORM_WINDOWS TRUE)
    add_definitions(-DPLATFORM_WINDOWS)
elseif(UNIX AND NOT APPLE)
    set(PLATFORM_LINUX TRUE)
    add_definitions(-DPLATFORM_LINUX)
else()
    message(FATAL_ERROR "Unsupported platform")
endif()

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src/common
)

# Source files
set(COMMON_SOURCES
    src/common/version.h
)

if(PLATFORM_WINDOWS)
    set(PLATFORM_SOURCES
        # Windows-specific sources will be added here
    )
elseif(PLATFORM_LINUX)
    set(PLATFORM_SOURCES
        # Linux-specific sources will be added here
    )
endif()

# Find NDI SDK
find_path(NDI_INCLUDE_DIR
    NAMES Processing.NDI.Lib.h
    PATHS
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/include
        $ENV{NDI_SDK_DIR}/include
)

find_library(NDI_LIBRARY
    NAMES Processing.NDI.Lib.x64
    PATHS
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/ndi/lib/x64
        $ENV{NDI_SDK_DIR}/lib/x64
)

if(NOT NDI_INCLUDE_DIR OR NOT NDI_LIBRARY)
    message(FATAL_ERROR "NDI SDK not found. Please download and place in deps/ndi/")
endif()

# Main executable
add_executable(${PROJECT_NAME}
    ${COMMON_SOURCES}
    ${PLATFORM_SOURCES}
)

# Link libraries
if(PLATFORM_WINDOWS)
    target_link_libraries(${PROJECT_NAME}
        ${NDI_LIBRARY}
        # Windows-specific libraries will be added here
    )
elseif(PLATFORM_LINUX)
    target_link_libraries(${PROJECT_NAME}
        ${NDI_LIBRARY}
        pthread
        # Linux-specific libraries will be added here
    )
endif()

# Tests
if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
