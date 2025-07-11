// mf_format_converter.cpp
#include "mf_format_converter.h"
#include <mfapi.h>
#include <wmcodecdsp.h>

namespace ndi_bridge {
namespace media_foundation {

void FormatConverter::YUY2toUYVY(const uint8_t* src, uint8_t* dst, int width, int height) {
    int totalPixels = width * height;
    for (int i = 0; i < totalPixels; i += 2) {
        // YUY2: Y0 U Y1 V
        // UYVY: U Y0 V Y1
        dst[0] = src[1];  // U
        dst[1] = src[0];  // Y0
        dst[2] = src[3];  // V
        dst[3] = src[2];  // Y1
        src += 4;
        dst += 4;
    }
}

void FormatConverter::NV12toUYVY(const uint8_t* nv12, uint8_t* uyvy, int width, int height) {
    const uint8_t* Yplane = nv12;
    const uint8_t* UVplane = nv12 + width * height;
    
    for (int y = 0; y < height; y++) {
        int uvRow = y / 2;
        for (int x = 0; x < width; x += 2) {
            uint8_t Y0 = Yplane[y * width + x];
            uint8_t Y1 = Yplane[y * width + (x + 1)];
            int uvCol = x / 2;
            uint8_t U = UVplane[uvRow * (width / 2) * 2 + uvCol * 2 + 0];
            uint8_t V = UVplane[uvRow * (width / 2) * 2 + uvCol * 2 + 1];
            
            int outIndex = (y * width + x) * 2;
            uyvy[outIndex + 0] = U;
            uyvy[outIndex + 1] = Y0;
            uyvy[outIndex + 2] = V;
            uyvy[outIndex + 3] = Y1;
        }
    }
}

bool FormatConverter::RequiresConversion(const GUID& subtype) {
    // UYVY doesn't require conversion
    if (subtype == MFVideoFormat_UYVY) {
        return false;
    }
    // YUY2 and NV12 require conversion
    if (subtype == MFVideoFormat_YUY2 || subtype.Data1 == 0x3231564E) {
        return true;
    }
    // Other formats would need conversion but aren't supported yet
    return true;
}

size_t FormatConverter::GetUYVYBufferSize(int width, int height) {
    // UYVY uses 2 bytes per pixel
    return static_cast<size_t>(width) * height * 2;
}

size_t FormatConverter::GetInputBufferSize(const GUID& subtype, int width, int height) {
    if (subtype == MFVideoFormat_UYVY || subtype == MFVideoFormat_YUY2) {
        // 2 bytes per pixel
        return static_cast<size_t>(width) * height * 2;
    }
    if (subtype.Data1 == 0x3231564E) { // NV12
        // 1.5 bytes per pixel (Y plane + UV plane)
        return static_cast<size_t>(width) * height * 3 / 2;
    }
    // Default to 2 bytes per pixel
    return static_cast<size_t>(width) * height * 2;
}

bool FormatConverter::ConvertToUYVY(const GUID& subtype, 
                                   const uint8_t* src, 
                                   uint8_t* dst, 
                                   int width, 
                                   int height) {
    if (subtype == MFVideoFormat_UYVY) {
        // Direct copy
        size_t size = GetUYVYBufferSize(width, height);
        memcpy(dst, src, size);
        return true;
    }
    
    if (subtype == MFVideoFormat_YUY2) {
        YUY2toUYVY(src, dst, width, height);
        return true;
    }
    
    if (subtype.Data1 == 0x3231564E) { // NV12
        NV12toUYVY(src, dst, width, height);
        return true;
    }
    
    // Unsupported format
    return false;
}

std::string FormatConverter::GetFormatName(const GUID& subtype) {
    if (subtype == MFVideoFormat_UYVY) return "UYVY";
    if (subtype == MFVideoFormat_YUY2) return "YUY2";
    if (subtype.Data1 == 0x3231564E) return "NV12";
    
    // Return GUID as string for unknown formats
    wchar_t guidStr[40] = {0};
    StringFromGUID2(subtype, guidStr, 40);
    char mbStr[40] = {0};
    wcstombs(mbStr, guidStr, 39);
    return std::string(mbStr);
}

} // namespace media_foundation
} // namespace ndi_bridge
