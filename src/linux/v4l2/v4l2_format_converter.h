// v4l2_format_converter.h
#pragma once

#include <vector>
#include <cstdint>
#include <string>
#include <linux/videodev2.h>

namespace ndi_bridge {
namespace v4l2 {

/**
 * @brief YUV format converter for V4L2 capture
 * 
 * Handles conversion from various YUV formats to BGRA for NDI output.
 * Supports common USB capture card formats and webcam formats.
 */
class V4L2FormatConverter {
public:
    V4L2FormatConverter();
    ~V4L2FormatConverter();
    
    /**
     * @brief Convert input format to BGRA
     * 
     * @param input Input buffer
     * @param input_size Size of input data
     * @param width Frame width
     * @param height Frame height
     * @param pixelformat V4L2 pixel format (e.g., V4L2_PIX_FMT_YUYV)
     * @param output Output buffer (will be resized)
     * @return true on success
     */
    bool convertToBGRA(const void* input, size_t input_size,
                       int width, int height, uint32_t pixelformat,
                       std::vector<uint8_t>& output);
    
    /**
     * @brief Check if format is supported
     */
    static bool isFormatSupported(uint32_t pixelformat);
    
    /**
     * @brief Get human-readable format name
     */
    static std::string getFormatName(uint32_t pixelformat);
    
    /**
     * @brief Calculate BGRA buffer size
     */
    static size_t calculateBGRASize(int width, int height);
    
private:
    // Scalar conversion functions
    bool convertYUYVtoBGRA(const uint8_t* input, int width, int height, uint8_t* output);
    bool convertUYVYtoBGRA(const uint8_t* input, int width, int height, uint8_t* output);
    bool convertNV12toBGRA(const uint8_t* input, int width, int height, uint8_t* output);
    bool convertRGB24toBGRA(const uint8_t* input, int width, int height, uint8_t* output);
    bool convertBGR24toBGRA(const uint8_t* input, int width, int height, uint8_t* output);
    bool decompressMJPEGtoBGRA(const uint8_t* input, size_t input_size, 
                               int width, int height, uint8_t* output);
    
    // YUV to RGB conversion helper
    static inline void yuvToRgb(uint8_t y, uint8_t u, uint8_t v, 
                                uint8_t& r, uint8_t& g, uint8_t& b);
    
    // Clamp value to [0, 255]
    static inline uint8_t clamp(int value) {
        return (value < 0) ? 0 : (value > 255) ? 255 : static_cast<uint8_t>(value);
    }
    
    // AVX2 optimization flag
    bool use_avx2_;
    
    // Flag to track if AVX2 usage has been logged
    mutable bool avx2_logged_;
};

} // namespace v4l2
} // namespace ndi_bridge
