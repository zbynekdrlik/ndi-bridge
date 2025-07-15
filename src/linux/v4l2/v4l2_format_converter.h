// v4l2_format_converter.h
#pragma once

#include <cstdint>
#include <vector>
#include <linux/videodev2.h>

namespace ndi_bridge {
namespace v4l2 {

/**
 * @brief Converts V4L2 pixel formats to NDI-compatible formats
 * 
 * Handles conversion from common V4L2 formats (YUYV, MJPEG, etc.)
 * to BGRA format required by NDI.
 * 
 * Version: 1.3.0
 */
class V4L2FormatConverter {
public:
    V4L2FormatConverter();
    ~V4L2FormatConverter();
    
    /**
     * @brief Convert frame from V4L2 format to BGRA
     * @param input Input buffer
     * @param input_size Input buffer size
     * @param width Frame width
     * @param height Frame height
     * @param pixelformat V4L2 pixel format
     * @param output Output buffer (will be resized)
     * @return true if conversion successful
     */
    bool convertToBGRA(const void* input, size_t input_size,
                       int width, int height, uint32_t pixelformat,
                       std::vector<uint8_t>& output);
    
    /**
     * @brief Check if format is supported for conversion
     * @param pixelformat V4L2 pixel format
     * @return true if format can be converted
     */
    static bool isFormatSupported(uint32_t pixelformat);
    
    /**
     * @brief Get format name
     * @param pixelformat V4L2 pixel format
     * @return Human-readable format name
     */
    static std::string getFormatName(uint32_t pixelformat);
    
    /**
     * @brief Calculate output buffer size for BGRA
     * @param width Frame width
     * @param height Frame height
     * @return Required buffer size in bytes
     */
    static size_t calculateBGRASize(int width, int height);
    
private:
    // YUV to RGB conversion helpers
    static inline uint8_t clamp(int value) {
        return value < 0 ? 0 : (value > 255 ? 255 : static_cast<uint8_t>(value));
    }
    
    // Convert YUYV (YUV 4:2:2) to BGRA
    bool convertYUYVtoBGRA(const uint8_t* input, int width, int height,
                           uint8_t* output);
    
    // Convert UYVY (YUV 4:2:2) to BGRA
    bool convertUYVYtoBGRA(const uint8_t* input, int width, int height,
                           uint8_t* output);
    
    // Convert NV12 (YUV 4:2:0) to BGRA
    bool convertNV12toBGRA(const uint8_t* input, int width, int height,
                           uint8_t* output);
    
    // Convert RGB24 to BGRA
    bool convertRGB24toBGRA(const uint8_t* input, int width, int height,
                            uint8_t* output);
    
    // Convert BGR24 to BGRA
    bool convertBGR24toBGRA(const uint8_t* input, int width, int height,
                            uint8_t* output);
    
    // Decompress MJPEG to BGRA (if libjpeg available)
    bool decompressMJPEGtoBGRA(const uint8_t* input, size_t input_size,
                               int width, int height, uint8_t* output);
    
    // YUV to RGB conversion
    static void yuvToRgb(uint8_t y, uint8_t u, uint8_t v,
                         uint8_t& r, uint8_t& g, uint8_t& b);
};

} // namespace v4l2
} // namespace ndi_bridge
