#pragma once

#define NDI_BRIDGE_VERSION_MAJOR 1
#define NDI_BRIDGE_VERSION_MINOR 0
#define NDI_BRIDGE_VERSION_PATCH 4

#define NDI_BRIDGE_VERSION_STRING "1.0.4"

// Build info
#ifdef _DEBUG
#define NDI_BRIDGE_BUILD_TYPE "Debug"
#else
#define NDI_BRIDGE_BUILD_TYPE "Release"
#endif

#ifdef _WIN64
#define NDI_BRIDGE_PLATFORM "Windows x64"
#elif defined(_WIN32)
#define NDI_BRIDGE_PLATFORM "Windows x86"
#elif defined(__linux__)
#define NDI_BRIDGE_PLATFORM "Linux"
#else
#define NDI_BRIDGE_PLATFORM "Unknown"
#endif
