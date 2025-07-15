// mf_format_converter.h
#pragma once

#include <windows.h>
#include <mfapi.h>
#include <cstdint>
#include <string>

namespace ndi_bridge {
namespace media_foundation {

// Video format conversion utilities
class FormatConverter {
public:
    // Convert YUY2 to UYVY format
    static void YUY2toUYVY(const uint8_t* src, uint8_t* dst, int width, int height);
    
    // Convert NV12 to UYVY format
    static void NV12toUYVY(const uint8_t* nv12, uint8_t* uyvy, int width, int height);
    
    // Check if a format requires conversion
    static bool RequiresConversion(const GUID& subtype);
    
    // Get output buffer size for UYVY format
    static size_t GetUYVYBufferSize(int width, int height);
    
    // Get required input buffer size for given format
    static size_t GetInputBufferSize(const GUID& subtype, int width, int height);
    
    // Convert generic format to UYVY (dispatches to appropriate converter)
    static bool ConvertToUYVY(const GUID& subtype, 
                              const uint8_t* src, 
                              uint8_t* dst, 
                              int width, 
                              int height);
    
    // Get human-readable format name
    static std::string GetFormatName(const GUID& subtype);
    
    // Format GUIDs
    static constexpr GUID GUID_NV12 = { 
        0x3231564E, 0x0000, 0x0010, 
        { 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71 } 
    };
};

} // namespace media_foundation
} // namespace ndi_bridge
