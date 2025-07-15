// version.h
#pragma once

#define NDI_BRIDGE_VERSION "1.1.6"
#define NDI_BRIDGE_VERSION_MAJOR 1
#define NDI_BRIDGE_VERSION_MINOR 1
#define NDI_BRIDGE_VERSION_PATCH 6

#ifdef _WIN32
#define NDI_BRIDGE_PLATFORM "Windows"
#elif __linux__
#define NDI_BRIDGE_PLATFORM "Linux"
#else
#define NDI_BRIDGE_PLATFORM "Unknown"
#endif

#ifdef _DEBUG
#define NDI_BRIDGE_BUILD_TYPE "Debug"
#else
#define NDI_BRIDGE_BUILD_TYPE "Release"
#endif
