// v4l2_format_converter.cpp
#include "v4l2_format_converter.h"
#include "../../common/logger.h"
#include <cstring>
#include <algorithm>

namespace ndi_bridge {
namespace v4l2 {

V4L2FormatConverter::V4L2FormatConverter() {
    Logger::log("V4L2FormatConverter: Created");
}

V4L2FormatConverter::~V4L2FormatConverter() {
}

bool V4L2FormatConverter::convertToBGRA(const void* input, size_t input_size,
                                        int width, int height, uint32_t pixelformat,
                                        std::vector<uint8_t>& output) {
    if (!input || input_size == 0 || width <= 0 || height <= 0) {
        return false;
    }
    
    // Resize output buffer
    size_t output_size = calculateBGRASize(width, height);
    output.resize(output_size);
    
    const uint8_t* input_data = static_cast<const uint8_t*>(input);
    uint8_t* output_data = output.data();
    
    bool result = false;
    
    switch (pixelformat) {
        case V4L2_PIX_FMT_YUYV:
            result = convertYUYVtoBGRA(input_data, width, height, output_data);
            break;
            
        case V4L2_PIX_FMT_UYVY:
            result = convertUYVYtoBGRA(input_data, width, height, output_data);
            break;
            
        case V4L2_PIX_FMT_NV12:
            result = convertNV12toBGRA(input_data, width, height, output_data);
            break;
            
        case V4L2_PIX_FMT_RGB24:
            result = convertRGB24toBGRA(input_data, width, height, output_data);
            break;
            
        case V4L2_PIX_FMT_BGR24:
            result = convertBGR24toBGRA(input_data, width, height, output_data);
            break;
            
        case V4L2_PIX_FMT_MJPEG:
            result = decompressMJPEGtoBGRA(input_data, input_size, width, height, output_data);
            break;
            
        default:
            Logger::log("V4L2FormatConverter: Unsupported format: " + getFormatName(pixelformat));
            return false;
    }
    
    if (!result) {
        output.clear();
    }
    
    return result;
}

bool V4L2FormatConverter::isFormatSupported(uint32_t pixelformat) {
    switch (pixelformat) {
        case V4L2_PIX_FMT_YUYV:
        case V4L2_PIX_FMT_UYVY:
        case V4L2_PIX_FMT_NV12:
        case V4L2_PIX_FMT_RGB24:
        case V4L2_PIX_FMT_BGR24:
        case V4L2_PIX_FMT_MJPEG:
            return true;
        default:
            return false;
    }
}

std::string V4L2FormatConverter::getFormatName(uint32_t pixelformat) {
    char fourcc[5] = {0};
    fourcc[0] = (pixelformat >> 0) & 0xFF;
    fourcc[1] = (pixelformat >> 8) & 0xFF;
    fourcc[2] = (pixelformat >> 16) & 0xFF;
    fourcc[3] = (pixelformat >> 24) & 0xFF;
    
    // Return human-readable name for common formats
    switch (pixelformat) {
        case V4L2_PIX_FMT_YUYV:
            return "YUYV (YUV 4:2:2)";
        case V4L2_PIX_FMT_UYVY:
            return "UYVY (YUV 4:2:2)";
        case V4L2_PIX_FMT_NV12:
            return "NV12 (YUV 4:2:0)";
        case V4L2_PIX_FMT_RGB24:
            return "RGB24";
        case V4L2_PIX_FMT_BGR24:
            return "BGR24";
        case V4L2_PIX_FMT_MJPEG:
            return "MJPEG";
        default:
            return std::string(fourcc);
    }
}

size_t V4L2FormatConverter::calculateBGRASize(int width, int height) {
    return width * height * 4; // 4 bytes per pixel
}

bool V4L2FormatConverter::convertYUYVtoBGRA(const uint8_t* input, int width, int height,
                                            uint8_t* output) {
    // YUYV format: Y0 U0 Y1 V0 | Y2 U2 Y3 V2
    // Two pixels are encoded in 4 bytes
    
    for (int y = 0; y < height; y++) {
        const uint8_t* src_row = input + y * width * 2; // 2 bytes per pixel
        uint8_t* dst_row = output + y * width * 4;      // 4 bytes per pixel
        
        for (int x = 0; x < width; x += 2) {
            uint8_t y0 = src_row[0];
            uint8_t u  = src_row[1];
            uint8_t y1 = src_row[2];
            uint8_t v  = src_row[3];
            
            uint8_t r0, g0, b0, r1, g1, b1;
            yuvToRgb(y0, u, v, r0, g0, b0);
            yuvToRgb(y1, u, v, r1, g1, b1);
            
            // Write BGRA pixels
            dst_row[0] = b0;
            dst_row[1] = g0;
            dst_row[2] = r0;
            dst_row[3] = 255; // Alpha
            
            dst_row[4] = b1;
            dst_row[5] = g1;
            dst_row[6] = r1;
            dst_row[7] = 255; // Alpha
            
            src_row += 4;
            dst_row += 8;
        }
    }
    
    return true;
}

bool V4L2FormatConverter::convertUYVYtoBGRA(const uint8_t* input, int width, int height,
                                            uint8_t* output) {
    // UYVY format: U0 Y0 V0 Y1 | U2 Y2 V2 Y3
    // Two pixels are encoded in 4 bytes
    
    for (int y = 0; y < height; y++) {
        const uint8_t* src_row = input + y * width * 2; // 2 bytes per pixel
        uint8_t* dst_row = output + y * width * 4;      // 4 bytes per pixel
        
        for (int x = 0; x < width; x += 2) {
            uint8_t u  = src_row[0];
            uint8_t y0 = src_row[1];
            uint8_t v  = src_row[2];
            uint8_t y1 = src_row[3];
            
            uint8_t r0, g0, b0, r1, g1, b1;
            yuvToRgb(y0, u, v, r0, g0, b0);
            yuvToRgb(y1, u, v, r1, g1, b1);
            
            // Write BGRA pixels
            dst_row[0] = b0;
            dst_row[1] = g0;
            dst_row[2] = r0;
            dst_row[3] = 255; // Alpha
            
            dst_row[4] = b1;
            dst_row[5] = g1;
            dst_row[6] = r1;
            dst_row[7] = 255; // Alpha
            
            src_row += 4;
            dst_row += 8;
        }
    }
    
    return true;
}

bool V4L2FormatConverter::convertNV12toBGRA(const uint8_t* input, int width, int height,
                                            uint8_t* output) {
    // NV12 format: Y plane followed by interleaved UV plane
    const uint8_t* y_plane = input;
    const uint8_t* uv_plane = input + width * height;
    
    for (int y = 0; y < height; y++) {
        const uint8_t* y_row = y_plane + y * width;
        const uint8_t* uv_row = uv_plane + (y / 2) * width;
        uint8_t* dst_row = output + y * width * 4;
        
        for (int x = 0; x < width; x++) {
            uint8_t y_val = y_row[x];
            uint8_t u = uv_row[(x / 2) * 2];
            uint8_t v = uv_row[(x / 2) * 2 + 1];
            
            uint8_t r, g, b;
            yuvToRgb(y_val, u, v, r, g, b);
            
            dst_row[x * 4 + 0] = b;
            dst_row[x * 4 + 1] = g;
            dst_row[x * 4 + 2] = r;
            dst_row[x * 4 + 3] = 255; // Alpha
        }
    }
    
    return true;
}

bool V4L2FormatConverter::convertRGB24toBGRA(const uint8_t* input, int width, int height,
                                              uint8_t* output) {
    for (int y = 0; y < height; y++) {
        const uint8_t* src_row = input + y * width * 3;
        uint8_t* dst_row = output + y * width * 4;
        
        for (int x = 0; x < width; x++) {
            dst_row[x * 4 + 0] = src_row[x * 3 + 2]; // B
            dst_row[x * 4 + 1] = src_row[x * 3 + 1]; // G
            dst_row[x * 4 + 2] = src_row[x * 3 + 0]; // R
            dst_row[x * 4 + 3] = 255;                // A
        }
    }
    
    return true;
}

bool V4L2FormatConverter::convertBGR24toBGRA(const uint8_t* input, int width, int height,
                                              uint8_t* output) {
    for (int y = 0; y < height; y++) {
        const uint8_t* src_row = input + y * width * 3;
        uint8_t* dst_row = output + y * width * 4;
        
        for (int x = 0; x < width; x++) {
            dst_row[x * 4 + 0] = src_row[x * 3 + 0]; // B
            dst_row[x * 4 + 1] = src_row[x * 3 + 1]; // G
            dst_row[x * 4 + 2] = src_row[x * 3 + 2]; // R
            dst_row[x * 4 + 3] = 255;                // A
        }
    }
    
    return true;
}

bool V4L2FormatConverter::decompressMJPEGtoBGRA(const uint8_t* input, size_t input_size,
                                                 int width, int height, uint8_t* output) {
    // For now, we don't support MJPEG without libjpeg
    // This would require linking with libjpeg or libjpeg-turbo
    Logger::log("V4L2FormatConverter: MJPEG decompression not implemented (requires libjpeg)");
    return false;
}

void V4L2FormatConverter::yuvToRgb(uint8_t y, uint8_t u, uint8_t v,
                                   uint8_t& r, uint8_t& g, uint8_t& b) {
    // ITU-R BT.601 conversion
    int c = y - 16;
    int d = u - 128;
    int e = v - 128;
    
    int r_val = (298 * c + 409 * e + 128) >> 8;
    int g_val = (298 * c - 100 * d - 208 * e + 128) >> 8;
    int b_val = (298 * c + 516 * d + 128) >> 8;
    
    r = clamp(r_val);
    g = clamp(g_val);
    b = clamp(b_val);
}

} // namespace v4l2
} // namespace ndi_bridge
