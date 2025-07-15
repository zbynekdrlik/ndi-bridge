// mf_error_handling.h
#pragma once

#include <windows.h>
#include <string>
#include <sstream>
#include <comdef.h>

// Define missing error codes if not already defined
#ifndef MF_E_HW_MFT_FAILED_START_STREAMING
#define MF_E_HW_MFT_FAILED_START_STREAMING ((HRESULT)0xC00D3EA2L)
#endif

#ifndef MF_E_DEVICE_INVALIDATED
#define MF_E_DEVICE_INVALIDATED ((HRESULT)0xC00D36B4L)
#endif

#ifndef MF_E_NO_MORE_TYPES
#define MF_E_NO_MORE_TYPES ((HRESULT)0xC00D36B9L)
#endif

#ifndef MF_E_VIDEO_RECORDING_DEVICE_LOCKED
#define MF_E_VIDEO_RECORDING_DEVICE_LOCKED ((HRESULT)0xC00D3E85L)
#endif

namespace ndi_bridge {
namespace media_foundation {

// Error handling utilities
class MFErrorHandler {
public:
    // Convert HRESULT to string with detailed error message
    static std::string HResultToString(HRESULT hr);
    
    // Check if HRESULT failed and log error
    static bool CheckFailed(const char* operation, HRESULT hr);
    
    // Check if error indicates device disconnection/invalidation
    static bool IsDeviceError(HRESULT hr);
    
    // Check if error indicates we should reinitialize Media Foundation
    static bool RequiresMediaFoundationReinit(HRESULT hr);
    
    // Log error with context
    static void LogError(const std::string& context, HRESULT hr);
    
    // Get last error message (thread-local)
    static std::string GetLastError();
    
private:
    static thread_local std::string last_error_;
};

// RAII wrapper for COM initialization
class ComInitializer {
public:
    ComInitializer();
    ~ComInitializer();
    
    ComInitializer(const ComInitializer&) = delete;
    ComInitializer& operator=(const ComInitializer&) = delete;
    
    bool IsInitialized() const { return initialized_; }
    
private:
    bool initialized_;
};

// RAII wrapper for Media Foundation initialization
class MFInitializer {
public:
    MFInitializer();
    ~MFInitializer();
    
    MFInitializer(const MFInitializer&) = delete;
    MFInitializer& operator=(const MFInitializer&) = delete;
    
    bool IsInitialized() const { return initialized_; }
    HRESULT Reinitialize();
    
private:
    bool initialized_;
};

} // namespace media_foundation
} // namespace ndi_bridge
