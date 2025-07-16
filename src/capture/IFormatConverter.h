// IFormatConverter.h
#pragma once

#include <cstdint>

// Color space and range hints for conversion
struct ColorSpaceInfo {
    enum ColorSpace {
        CS_AUTO,    // Auto-detect based on resolution
        CS_BT601,   // SD color space
        CS_BT709    // HD color space
    };
    
    enum ColorRange {
        CR_AUTO,    // Auto-detect
        CR_LIMITED, // Limited range (16-235/240)
        CR_FULL     // Full range (0-255)
    };
    
    ColorSpace space = CS_AUTO;
    ColorRange range = CR_AUTO;
};

// Abstract interface for format conversion
class IFormatConverter {
public:
    virtual ~IFormatConverter() = default;
    
    // Convert UYVY (YUV 4:2:2 packed) to BGRA
    virtual bool ConvertUYVYToBGRA(const uint8_t* src, uint8_t* dst, 
                                   int width, int height, int srcStride) = 0;
    
    // Convert UYVY to BGRA with explicit color space info
    virtual bool ConvertUYVYToBGRA(const uint8_t* src, uint8_t* dst, 
                                   int width, int height, int srcStride,
                                   const ColorSpaceInfo& info) = 0;
    
    // Convert YUV420 planar to BGRA
    virtual bool ConvertYUV420ToBGRA(const uint8_t* srcY, const uint8_t* srcU, const uint8_t* srcV,
                                     uint8_t* dst, int width, int height, 
                                     int strideY, int strideU, int strideV) = 0;
    
    // Convert NV12 to BGRA
    virtual bool ConvertNV12ToBGRA(const uint8_t* srcY, const uint8_t* srcUV,
                                   uint8_t* dst, int width, int height,
                                   int strideY, int strideUV) = 0;
    
    // Convert RGB24 to BGRA
    virtual bool ConvertRGB24ToBGRA(const uint8_t* src, uint8_t* dst,
                                    int width, int height, int srcStride) = 0;
};
