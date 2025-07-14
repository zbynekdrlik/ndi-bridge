// IFormatConverter.h
#pragma once

#include <cstdint>

// Abstract interface for format conversion
class IFormatConverter {
public:
    virtual ~IFormatConverter() = default;
    
    // Convert UYVY (YUV 4:2:2 packed) to BGRA
    virtual bool ConvertUYVYToBGRA(const uint8_t* src, uint8_t* dst, 
                                   int width, int height, int srcStride) = 0;
    
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
