#pragma once

#define NDI_BRIDGE_VERSION_MAJOR 1
#define NDI_BRIDGE_VERSION_MINOR 1
#define NDI_BRIDGE_VERSION_PATCH 5

#define NDI_BRIDGE_VERSION_STRING "1.1.5"
#define NDI_BRIDGE_VERSION NDI_BRIDGE_VERSION_STRING

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

// Feature flags
#define NDI_BRIDGE_HAS_MEDIA_FOUNDATION 1
#define NDI_BRIDGE_HAS_DECKLINK 1
#define NDI_BRIDGE_HAS_V4L2 0