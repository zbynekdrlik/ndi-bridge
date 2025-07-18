#pragma once

#define VERSION_MAJOR 2
#define VERSION_MINOR 1
#define VERSION_PATCH 1

#define VERSION_STRING "2.1.1"

// Additional defines for main.cpp compatibility
#define NDI_BRIDGE_VERSION VERSION_STRING

// Build type and platform detection
#ifdef _DEBUG
#define NDI_BRIDGE_BUILD_TYPE "Debug"
#else
#define NDI_BRIDGE_BUILD_TYPE "Release"
#endif

#ifdef _WIN32
#define NDI_BRIDGE_PLATFORM "Windows"
#elif defined(__linux__)
#define NDI_BRIDGE_PLATFORM "Linux"
#else
#define NDI_BRIDGE_PLATFORM "Unknown"
#endif